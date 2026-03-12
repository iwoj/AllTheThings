import Foundation
import CloudKit
import Combine

/// Persists sensor readings and ground-truth entries locally (JSONL) and,
/// optionally, in CloudKit for use by both training and inference pipelines.
///
/// ## CloudKit schema
/// - **SensorReading** record type: `id`, `timestamp`, `type`, `value`, `unit`
/// - **GroundTruthEntry** record type: `id`, `timestamp`, `transcription`,
///   `associatedSensorReadingIDs`
///
/// Toggle ``isCloudKitEnabled`` to switch between local-only and cloud modes.
/// When cloud mode is on the same container is used for inference: call
/// ``fetchRecentSensorReadings(ofType:limit:)`` and
/// ``fetchGroundTruthEntries(limit:)`` to read data back.
@MainActor
final class StorageManager: ObservableObject {

    // MARK: - UserDefaults key

    static let cloudKitEnabledKey = "cloudKitEnabled"

    // MARK: - Published

    @Published var isCloudKitEnabled: Bool {
        didSet { UserDefaults.standard.set(isCloudKitEnabled, forKey: Self.cloudKitEnabledKey) }
    }
    @Published private(set) var isSyncing      = false
    @Published private(set) var syncError:   Error?
    @Published private(set) var sensorCount  = 0
    @Published private(set) var truthCount   = 0

    // MARK: - CloudKit

    private let ckContainer: CKContainer
    private var privateDB: CKDatabase { ckContainer.privateCloudDatabase }

    // MARK: - Local paths

    private let dataDir:        URL
    private let sensorFile      = "sensor_readings.jsonl"
    private let groundTruthFile = "ground_truth.jsonl"

    // MARK: - In-memory buffer (flushed in batches)

    private var sensorBuffer = [SensorReading]()
    private let batchSize    = 100

    // MARK: - Init

    init(cloudKitContainerID: String = "iCloud.com.allthethings.app") {
        self.ckContainer      = CKContainer(identifier: cloudKitContainerID)
        self.isCloudKitEnabled = UserDefaults.standard.bool(forKey: Self.cloudKitEnabledKey)

        let docs = FileManager.default.urls(for: .documentDirectory,
                                             in: .userDomainMask).first!
        self.dataDir = docs.appendingPathComponent("AllTheThings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir,
                                                 withIntermediateDirectories: true)
        refreshLocalStats()
    }

    // MARK: - Save sensor reading

    func save(sensorReading: SensorReading) async {
        appendLine(sensorReading, to: sensorFile)
        sensorBuffer.append(sensorReading)

        if sensorBuffer.count >= batchSize {
            await flushSensorBuffer()
        }
    }

    // MARK: - Save ground truth entry

    func save(groundTruthEntry: GroundTruthEntry) async {
        appendLine(groundTruthEntry, to: groundTruthFile)
        truthCount += 1

        if isCloudKitEnabled {
            await upload(groundTruthEntry)
        }
    }

    // MARK: - Flush buffered sensor readings

    func flushSensorBuffer() async {
        let readings = sensorBuffer
        sensorBuffer = []
        sensorCount += readings.count

        guard isCloudKitEnabled, !readings.isEmpty else { return }
        await upload(sensorReadings: readings)
    }

    // MARK: - Fetch (for inference)

    func fetchRecentSensorReadings(
        ofType type: SensorReading.SensorType,
        limit: Int = 100
    ) async throws -> [SensorReading] {
        guard isCloudKitEnabled else {
            return localSensorReadings(ofType: type, limit: limit)
        }

        let predicate = NSPredicate(format: "type == %@", type.rawValue)
        let query     = CKQuery(recordType: SensorReading.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        let (matchResults, _) = try await privateDB.records(
            matching: query,
            inZoneWith: nil,
            desiredKeys: nil,
            resultsLimit: limit
        )
        return matchResults.compactMap { _, result in
            if case .success(let record) = result { return SensorReading.fromCKRecord(record) }
            return nil
        }
    }

    func fetchGroundTruthEntries(limit: Int = 50) async throws -> [GroundTruthEntry] {
        guard isCloudKitEnabled else {
            return localGroundTruthEntries(limit: limit)
        }

        let query = CKQuery(recordType: GroundTruthEntry.recordType,
                            predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        let (matchResults, _) = try await privateDB.records(
            matching: query,
            inZoneWith: nil,
            desiredKeys: nil,
            resultsLimit: limit
        )
        return matchResults.compactMap { _, result in
            if case .success(let record) = result { return GroundTruthEntry.fromCKRecord(record) }
            return nil
        }
    }

    // MARK: - Local data directory (for export / training pipeline)

    /// URL of the directory containing the JSONL data files.
    var localDataDirectoryURL: URL { dataDir }

    // MARK: - CloudKit upload helpers

    private func upload(sensorReadings: [SensorReading]) async {
        isSyncing = true
        defer { isSyncing = false }

        let records   = sensorReadings.map { $0.toCKRecord() }
        let operation = CKModifyRecordsOperation(recordsToSave: records,
                                                 recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged
        operation.isAtomic   = false

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:           cont.resume()
                    case .failure(let err):  cont.resume(throwing: err)
                    }
                }
                privateDB.add(operation)
            }
            syncError = nil
        } catch {
            syncError = error
        }
    }

    private func upload(_ entry: GroundTruthEntry) async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                privateDB.save(entry.toCKRecord()) { _, error in
                    if let error { cont.resume(throwing: error) }
                    else         { cont.resume() }
                }
            }
            syncError = nil
        } catch {
            syncError = error
        }
    }

    // MARK: - Local file helpers

    private func appendLine<T: Encodable>(_ value: T, to filename: String) {
        let url = dataDir.appendingPathComponent(filename)
        guard
            let data = try? JSONEncoder().encode(value),
            let line = String(data: data, encoding: .utf8)
        else { return }

        let bytes = (line + "\n").data(using: .utf8)!

        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            handle.seekToEndOfFile()
            handle.write(bytes)
            try? handle.close()
        } else {
            try? bytes.write(to: url, options: .atomic)
        }
    }

    private func refreshLocalStats() {
        sensorCount = lineCount(in: sensorFile)
        truthCount  = lineCount(in: groundTruthFile)
    }

    private func lineCount(in filename: String) -> Int {
        let url = dataDir.appendingPathComponent(filename)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return content.components(separatedBy: "\n").filter { !$0.isEmpty }.count
    }

    private func localSensorReadings(ofType type: SensorReading.SensorType,
                                     limit: Int) -> [SensorReading] {
        let url = dataDir.appendingPathComponent(sensorFile)
        let decoder = JSONDecoder()
        // Read lines in reverse so we reach `limit` quickly without loading everything.
        return lastLines(of: url, count: limit * 20)  // over-fetch to allow for type filter
            .compactMap { try? decoder.decode(SensorReading.self, from: Data($0.utf8)) }
            .filter { $0.type == type }
            .prefix(limit)
            .map { $0 }
    }

    private func localGroundTruthEntries(limit: Int) -> [GroundTruthEntry] {
        let url = dataDir.appendingPathComponent(groundTruthFile)
        let decoder = JSONDecoder()
        return lastLines(of: url, count: limit)
            .compactMap { try? decoder.decode(GroundTruthEntry.self, from: Data($0.utf8)) }
    }

    /// Returns up to `count` non-empty lines from the end of a file, in newest-first order.
    private func lastLines(of url: URL, count: Int) -> [String] {
        guard
            let data = try? Data(contentsOf: url),
            !data.isEmpty
        else { return [] }

        let newline = UInt8(ascii: "\n")
        var lines   = [String]()
        var end     = data.endIndex

        while lines.count < count, end > data.startIndex {
            // Step back past any trailing newline
            var lineEnd = end
            if lineEnd > data.startIndex, data[data.index(before: lineEnd)] == newline {
                lineEnd = data.index(before: lineEnd)
            }
            guard lineEnd > data.startIndex else { break }

            // Find start of this line
            var start = lineEnd
            while start > data.startIndex {
                let prev = data.index(before: start)
                if data[prev] == newline { break }
                start = prev
            }

            let slice = data[start ..< lineEnd]
            if !slice.isEmpty, let line = String(data: slice, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
            end = start
        }

        return lines
    }

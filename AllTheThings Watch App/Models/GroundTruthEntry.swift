import Foundation
import CloudKit

/// A timestamped voice-to-text annotation that serves as ground truth for ML training.
public struct GroundTruthEntry: Codable, Identifiable, Sendable {

    // MARK: - Properties

    public let id: UUID
    /// UTC timestamp when the voice recording was finalised.
    public let timestamp: Date
    /// Full transcription of the spoken annotation.
    public let transcription: String
    /// IDs of SensorReadings whose timestamps fall within the recording window.
    public let associatedSensorReadingIDs: [UUID]

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        transcription: String,
        associatedSensorReadingIDs: [UUID] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.transcription = transcription
        self.associatedSensorReadingIDs = associatedSensorReadingIDs
    }
}

// MARK: - CloudKit

extension GroundTruthEntry {

    static let recordType = "GroundTruthEntry"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: id.uuidString)
        )
        record["timestamp"]                  = timestamp as CKRecordValue
        record["transcription"]              = transcription as CKRecordValue
        record["associatedSensorReadingIDs"] = associatedSensorReadingIDs
            .map(\.uuidString) as CKRecordValue
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> GroundTruthEntry? {
        guard
            let timestamp     = record["timestamp"] as? Date,
            let transcription = record["transcription"] as? String
        else { return nil }

        let idStrings = record["associatedSensorReadingIDs"] as? [String] ?? []
        let ids = idStrings.compactMap { UUID(uuidString: $0) }

        return GroundTruthEntry(
            id:                          UUID(uuidString: record.recordID.recordName) ?? UUID(),
            timestamp:                   timestamp,
            transcription:               transcription,
            associatedSensorReadingIDs:  ids
        )
    }
}

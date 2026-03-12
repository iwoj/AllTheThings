import Foundation
import CloudKit

/// A single timestamped reading from one of the device's sensors.
public struct SensorReading: Codable, Identifiable, Sendable {

    // MARK: - Sensor Types

    public enum SensorType: String, Codable, CaseIterable, Sendable {
        case accelerometerX
        case accelerometerY
        case accelerometerZ
        case gyroscopeX
        case gyroscopeY
        case gyroscopeZ
        case attitudeRoll
        case attitudePitch
        case attitudeYaw
        case gravityX
        case gravityY
        case gravityZ
        case heartRate
        case bloodOxygen
    }

    // MARK: - Properties

    public let id: UUID
    /// UTC timestamp of the reading.
    public let timestamp: Date
    public let type: SensorType
    /// Primary scalar value (used for single-axis or scalar sensors).
    public let value: Double
    /// Human-readable unit string (e.g. "m/s²", "rad/s", "BPM").
    public let unit: String

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: SensorType,
        value: Double,
        unit: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.value = value
        self.unit = unit
    }
}

// MARK: - CloudKit

extension SensorReading {

    static let recordType = "SensorReading"

    func toCKRecord() -> CKRecord {
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: id.uuidString)
        )
        record["timestamp"] = timestamp as CKRecordValue
        record["type"]      = type.rawValue as CKRecordValue
        record["value"]     = value as CKRecordValue
        record["unit"]      = unit as CKRecordValue
        return record
    }

    static func fromCKRecord(_ record: CKRecord) -> SensorReading? {
        guard
            let timestamp  = record["timestamp"] as? Date,
            let typeString = record["type"] as? String,
            let type       = SensorType(rawValue: typeString),
            let value      = record["value"] as? Double,
            let unit       = record["unit"] as? String
        else { return nil }

        return SensorReading(
            id:        UUID(uuidString: record.recordID.recordName) ?? UUID(),
            timestamp: timestamp,
            type:      type,
            value:     value,
            unit:      unit
        )
    }
}

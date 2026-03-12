import Foundation
import CoreMotion
import HealthKit

/// Collects data from the Apple Watch motion coprocessor and HealthKit sensors.
///
/// - Motion (CoreMotion): accelerometer, gyroscope, attitude, gravity at 20 Hz.
/// - Health (HealthKit): heart rate and blood-oxygen via anchored queries.
///
/// All `@Published` properties are updated on the main actor.
@MainActor
final class SensorManager: ObservableObject {

    // MARK: - Published

    @Published private(set) var isCollecting = false
    @Published private(set) var latestReadings: [SensorReading] = []

    // MARK: - Private

    private let motionManager = CMMotionManager()
    private let healthStore   = HKHealthStore()
    private var heartRateQuery:   HKQuery?
    private var bloodOxygenQuery: HKQuery?
    private var onNewReading: ((SensorReading) -> Void)?

    /// Update interval for CoreMotion (20 Hz).
    let updateInterval: TimeInterval = 1.0 / 20.0

    // MARK: - HealthKit types we want to read

    private var readableHealthTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        if let hr = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(hr)
        }
        if let spo2 = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation) {
            types.insert(spo2)
        }
        return types
    }

    // MARK: - Authorisation

    func requestAuthorisation() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await healthStore.requestAuthorization(toShare: [], read: readableHealthTypes)
    }

    // MARK: - Start / Stop

    func startCollecting(onNewReading: @escaping (SensorReading) -> Void) {
        guard !isCollecting else { return }
        isCollecting = true
        self.onNewReading = onNewReading
        startMotionUpdates()
        startHeartRateQuery()
        startBloodOxygenQuery()
    }

    func stopCollecting() {
        guard isCollecting else { return }
        isCollecting = false
        onNewReading = nil
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        if let q = heartRateQuery   { healthStore.stop(q); heartRateQuery   = nil }
        if let q = bloodOxygenQuery { healthStore.stop(q); bloodOxygenQuery = nil }
    }

    // MARK: - CoreMotion

    private func startMotionUpdates() {
        let queue = OperationQueue()
        queue.name = "com.allthethings.motionqueue"
        queue.maxConcurrentOperationCount = 1

        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = updateInterval
            motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
                guard let motion else { return }
                let readings = Self.readings(from: motion)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestReadings = readings
                    readings.forEach { self.onNewReading?($0) }
                }
            }
        } else if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = updateInterval
            motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let data else { return }
                let ts = Date()
                let readings: [SensorReading] = [
                    SensorReading(timestamp: ts, type: .accelerometerX,
                                  value: data.acceleration.x, unit: "G"),
                    SensorReading(timestamp: ts, type: .accelerometerY,
                                  value: data.acceleration.y, unit: "G"),
                    SensorReading(timestamp: ts, type: .accelerometerZ,
                                  value: data.acceleration.z, unit: "G"),
                ]
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.latestReadings = readings
                    readings.forEach { self.onNewReading?($0) }
                }
            }
        }
    }

    private static func readings(from motion: CMDeviceMotion) -> [SensorReading] {
        let ts = Date()
        return [
            SensorReading(timestamp: ts, type: .accelerometerX,
                          value: motion.userAcceleration.x, unit: "G"),
            SensorReading(timestamp: ts, type: .accelerometerY,
                          value: motion.userAcceleration.y, unit: "G"),
            SensorReading(timestamp: ts, type: .accelerometerZ,
                          value: motion.userAcceleration.z, unit: "G"),
            SensorReading(timestamp: ts, type: .gyroscopeX,
                          value: motion.rotationRate.x, unit: "rad/s"),
            SensorReading(timestamp: ts, type: .gyroscopeY,
                          value: motion.rotationRate.y, unit: "rad/s"),
            SensorReading(timestamp: ts, type: .gyroscopeZ,
                          value: motion.rotationRate.z, unit: "rad/s"),
            SensorReading(timestamp: ts, type: .attitudeRoll,
                          value: motion.attitude.roll, unit: "rad"),
            SensorReading(timestamp: ts, type: .attitudePitch,
                          value: motion.attitude.pitch, unit: "rad"),
            SensorReading(timestamp: ts, type: .attitudeYaw,
                          value: motion.attitude.yaw, unit: "rad"),
            SensorReading(timestamp: ts, type: .gravityX,
                          value: motion.gravity.x, unit: "G"),
            SensorReading(timestamp: ts, type: .gravityY,
                          value: motion.gravity.y, unit: "G"),
            SensorReading(timestamp: ts, type: .gravityZ,
                          value: motion.gravity.z, unit: "G"),
        ]
    }

    // MARK: - HealthKit Heart Rate

    private func startHeartRateQuery() {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { return }

        let query = HKAnchoredObjectQuery(
            type:      hrType,
            predicate: nil,
            anchor:    nil,
            limit:     HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.emit(samples: samples, type: .heartRate,
                       unit: HKUnit(from: "count/min"), unitString: "BPM")
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.emit(samples: samples, type: .heartRate,
                       unit: HKUnit(from: "count/min"), unitString: "BPM")
        }

        heartRateQuery = query
        healthStore.execute(query)
    }

    // MARK: - HealthKit Blood Oxygen

    private func startBloodOxygenQuery() {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let spo2Type = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)
        else { return }

        let query = HKAnchoredObjectQuery(
            type:      spo2Type,
            predicate: nil,
            anchor:    nil,
            limit:     HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.emit(samples: samples, type: .bloodOxygen,
                       unit: HKUnit.percent(), unitString: "%SpO2")
        }

        query.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.emit(samples: samples, type: .bloodOxygen,
                       unit: HKUnit.percent(), unitString: "%SpO2")
        }

        bloodOxygenQuery = query
        healthStore.execute(query)
    }

    private func emit(
        samples: [HKSample]?,
        type: SensorReading.SensorType,
        unit: HKUnit,
        unitString: String
    ) {
        guard let quantitySamples = samples as? [HKQuantitySample] else { return }
        for sample in quantitySamples {
            let reading = SensorReading(
                timestamp: sample.startDate,
                type:      type,
                value:     sample.quantity.doubleValue(for: unit),
                unit:      unitString
            )
            Task { @MainActor [weak self] in
                self?.onNewReading?(reading)
            }
        }
    }
}

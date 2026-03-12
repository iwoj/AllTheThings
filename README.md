# AllTheThings

An Apple Watch app that logs all sensor data for ML training and supports a voice-to-text ground-truth annotation workflow.

## Features

| Feature | Description |
|---------|-------------|
| **Sensor logging** | Records accelerometer (X/Y/Z), gyroscope (X/Y/Z), attitude (roll/pitch/yaw), gravity (X/Y/Z), and heart rate at 20 Hz via CoreMotion and HealthKit. |
| **Voice annotations** | Press **Annotate** to record a spoken label. Speech is transcribed on-device (SFSpeechRecognizer) and saved as a timestamped `GroundTruthEntry` alongside the IDs of sensor readings collected during the recording window. |
| **Local storage** | All data is written to newline-delimited JSON (JSONL) files in the app's Documents directory — one file for sensor readings, one for ground-truth entries. |
| **CloudKit sync** | Toggle **CloudKit Sync** in Settings to mirror data to iCloud. The same CloudKit container (`iCloud.com.allthethings.app`) is used by both training pipelines (bulk reads of `SensorReading` / `GroundTruthEntry` records) and inference services (`StorageManager.fetchRecentSensorReadings`). |

## Architecture

```
AllTheThings Watch App/
├── AllTheThingsApp.swift          # @main entry point; injects environment objects
├── ContentView.swift              # Two-tab root (Record | Settings)
├── Views/
│   ├── RecordingView.swift        # Live sensor indicator, Start/Stop, Annotate button
│   └── SettingsView.swift         # CloudKit toggle, storage stats, permission status
├── Models/
│   ├── SensorReading.swift        # Codable + CloudKit (CKRecord) model
│   └── GroundTruthEntry.swift     # Codable + CloudKit (CKRecord) model
└── Managers/
    ├── SensorManager.swift        # CoreMotion + HealthKit data collection
    ├── SpeechManager.swift        # On-device speech recognition (SFSpeechRecognizer)
    └── StorageManager.swift       # JSONL local persistence + CloudKit batch upload/query
```

## Data format

### `sensor_readings.jsonl`
One JSON object per line:
```json
{"id":"…","timestamp":1710000000,"type":"accelerometerX","value":-0.012,"unit":"G"}
```

### `ground_truth.jsonl`
One JSON object per line:
```json
{"id":"…","timestamp":1710000010,"transcription":"walking up stairs","associatedSensorReadingIDs":["…","…"]}
```

## CloudKit schema

| Record Type | Fields |
|-------------|--------|
| `SensorReading` | `id` (String), `timestamp` (Date), `type` (String), `value` (Double), `unit` (String) |
| `GroundTruthEntry` | `id` (String), `timestamp` (Date), `transcription` (String), `associatedSensorReadingIDs` ([String]) |

## Requirements

- Xcode 15+  
- watchOS 10+  
- An Apple Developer account with iCloud / CloudKit enabled (for cloud sync)

## Permissions required

- **Microphone** — to capture voice annotations  
- **Speech Recognition** — for on-device transcription  
- **HealthKit** — to read heart rate  
- **Motion** — to access accelerometer / gyroscope via CoreMotion  

## Getting started

1. Open `AllTheThings.xcodeproj` in Xcode.  
2. Set your development team in the target's *Signing & Capabilities* tab.  
3. Enable the **HealthKit**, **Speech Recognition**, and **iCloud (CloudKit)** capabilities.  
4. Build and run on a paired Apple Watch (simulator or device).

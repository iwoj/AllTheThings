import SwiftUI

/// Settings view.
///
/// - CloudKit sync toggle (applies to both training ingestion and inference reads).
/// - Storage statistics.
/// - Sensor and speech authorisation status.
struct SettingsView: View {

    @EnvironmentObject private var storageManager: StorageManager
    @EnvironmentObject private var speechManager:  SpeechManager
    @EnvironmentObject private var sensorManager:  SensorManager

    var body: some View {
        List {
            cloudKitSection
            statsSection
            permissionsSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - CloudKit section

    private var cloudKitSection: some View {
        Section {
            Toggle(isOn: $storageManager.isCloudKitEnabled) {
                Label("CloudKit Sync", systemImage: "icloud")
            }

            if storageManager.isCloudKitEnabled {
                HStack {
                    Image(systemName: syncIcon)
                        .foregroundColor(syncColor)
                    Text(syncLabel)
                        .font(.caption2)
                        .foregroundColor(syncColor)
                }

                if let err = storageManager.syncError {
                    Text(err.localizedDescription)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(3)
                }
            }
        } header: {
            Text("Cloud Storage")
        } footer: {
            Text(storageManager.isCloudKitEnabled
                 ? "Data is saved to iCloud and available for ML training and inference."
                 : "Data is saved locally only. Enable CloudKit to share with training and inference pipelines.")
                .font(.caption2)
        }
    }

    // MARK: - Stats section

    private var statsSection: some View {
        Section("Data Collected") {
            LabeledContent("Sensor readings") {
                Text("\(storageManager.sensorCount)")
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Ground truth labels") {
                Text("\(storageManager.truthCount)")
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    // MARK: - Permissions section

    private var permissionsSection: some View {
        Section("Permissions") {
            LabeledContent("Speech") {
                permissionIcon(for: speechManager.authStatus == .authorized)
            }
            LabeledContent("Microphone") {
                permissionIcon(for: speechManager.micAuthStatus == .granted)
            }
            LabeledContent("Motion") {
                // CMMotionManager does not expose a separate auth check,
                // so we infer it from whether data arrives.
                permissionIcon(for: sensorManager.isCollecting ||
                               !sensorManager.latestReadings.isEmpty)
            }
        }
    }

    // MARK: - Helpers

    private var syncIcon: String {
        if storageManager.isSyncing { return "arrow.triangle.2.circlepath.icloud" }
        if storageManager.syncError != nil { return "exclamationmark.icloud" }
        return "checkmark.icloud"
    }

    private var syncColor: Color {
        if storageManager.isSyncing { return .yellow }
        if storageManager.syncError != nil { return .red }
        return .green
    }

    private var syncLabel: String {
        if storageManager.isSyncing { return "Syncing…" }
        if storageManager.syncError != nil { return "Sync error" }
        return "In sync"
    }

    @ViewBuilder
    private func permissionIcon(for granted: Bool) -> some View {
        Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundColor(granted ? .green : .red)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(StorageManager())
            .environmentObject(SpeechManager())
            .environmentObject(SensorManager())
    }
}

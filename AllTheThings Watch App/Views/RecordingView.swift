import SwiftUI

/// Main recording view.
///
/// - Top section: live sensor indicator + session stats.
/// - Middle: **Start / Stop** sensor-data capture.
/// - Bottom: **Hold to Record** voice annotation button.
struct RecordingView: View {

    @EnvironmentObject private var sensorManager:  SensorManager
    @EnvironmentObject private var speechManager:  SpeechManager
    @EnvironmentObject private var storageManager: StorageManager

    // IDs of sensor readings collected since the mic button was first pressed
    @State private var micStartedAt:  Date?
    @State private var recentIDs:     [UUID] = []
    @State private var lastAnnotation = ""
    @State private var speechError:   String?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                sensorStatusSection
                Divider()
                captureButton
                Divider()
                voiceSection
                if !lastAnnotation.isEmpty {
                    annotationBadge
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var sensorStatusSection: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: sensorManager.isCollecting
                      ? "waveform.path.ecg" : "waveform.path.ecg.rectangle")
                    .foregroundColor(sensorManager.isCollecting ? .green : .secondary)
                Text(sensorManager.isCollecting ? "Sensors Active" : "Sensors Idle")
                    .font(.caption2)
                    .foregroundColor(sensorManager.isCollecting ? .green : .secondary)
            }

            if let reading = sensorManager.latestReadings.first {
                Text(String(format: "%.3f %@", reading.value, reading.unit))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                statLabel(value: storageManager.sensorCount, title: "readings")
                statLabel(value: storageManager.truthCount,  title: "labels")
            }
        }
    }

    private var captureButton: some View {
        Button {
            toggleCapture()
        } label: {
            Label(
                sensorManager.isCollecting ? "Stop" : "Start",
                systemImage: sensorManager.isCollecting
                    ? "stop.circle.fill" : "play.circle.fill"
            )
            .font(.title3)
            .foregroundColor(sensorManager.isCollecting ? .red : .accentColor)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(sensorManager.isCollecting ? .red : .accentColor)
    }

    private var voiceSection: some View {
        VStack(spacing: 6) {
            if speechManager.isRecording {
                Text(speechManager.partialTranscription.isEmpty
                     ? "Listening…"
                     : speechManager.partialTranscription)
                    .font(.caption2)
                    .foregroundColor(.yellow)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
            }

            Button {
                handleMicButton()
            } label: {
                Label(
                    speechManager.isRecording ? "Done" : "Annotate",
                    systemImage: speechManager.isRecording
                        ? "checkmark.circle.fill" : "mic.circle.fill"
                )
                .font(.title3)
                .foregroundColor(speechManager.isRecording ? .yellow : .blue)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(speechManager.isRecording ? .yellow : .blue)
            .disabled(!speechManager.isAvailable && !speechManager.isRecording)

            if let err = speechError {
                Text(err)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var annotationBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Last annotation:")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(lastAnnotation)
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func statLabel(value: Int, title: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func toggleCapture() {
        if sensorManager.isCollecting {
            sensorManager.stopCollecting()
            Task { await storageManager.flushSensorBuffer() }
        } else {
            sensorManager.startCollecting { reading in
                Task {
                    await storageManager.save(sensorReading: reading)
                    if micStartedAt != nil {
                        recentIDs.append(reading.id)
                    }
                }
            }
        }
    }

    private func handleMicButton() {
        if speechManager.isRecording {
            // Finish and save ground truth
            let text = speechManager.stopRecording()
            guard !text.isEmpty else { return }

            let entry = GroundTruthEntry(
                timestamp:                  Date(),
                transcription:              text,
                associatedSensorReadingIDs: recentIDs
            )
            lastAnnotation = text
            recentIDs      = []
            micStartedAt   = nil

            Task { await storageManager.save(groundTruthEntry: entry) }
        } else {
            // Start recording
            speechError  = nil
            micStartedAt = Date()
            recentIDs    = []
            do {
                try speechManager.startRecording()
            } catch {
                speechError  = error.localizedDescription
                micStartedAt = nil
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        RecordingView()
            .environmentObject(SensorManager())
            .environmentObject(SpeechManager())
            .environmentObject(StorageManager())
    }
}

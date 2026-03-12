import SwiftUI

/// Root view: two-tab layout for recording and settings.
struct ContentView: View {
    var body: some View {
        TabView {
            NavigationView {
                RecordingView()
            }
            .tabItem {
                Label("Record", systemImage: "record.circle")
            }

            NavigationView {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(SensorManager())
        .environmentObject(SpeechManager())
        .environmentObject(StorageManager())
}

import SwiftUI

@main
struct AllTheThingsApp: App {

    @StateObject private var sensorManager  = SensorManager()
    @StateObject private var speechManager  = SpeechManager()
    @StateObject private var storageManager = StorageManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sensorManager)
                .environmentObject(speechManager)
                .environmentObject(storageManager)
                .task { await requestPermissions() }
        }
    }

    // MARK: - Permissions

    private func requestPermissions() async {
        await sensorManager.requestAuthorisation()
        await speechManager.requestAuthorisation()
    }
}

import SwiftUI

@main
struct SillyTavernServerApp: App {
    @StateObject private var controller = ServerController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .task {
                    await controller.prepare()
                }
                .onChange(of: scenePhase) { phase in
                    controller.scenePhaseChanged(phase)
                }
        }
    }
}

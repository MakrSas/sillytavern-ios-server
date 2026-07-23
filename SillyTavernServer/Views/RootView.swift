import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ServerDashboardView()
                .tabItem {
                    Label("Сервер", systemImage: "server.rack")
                }

            LogsView()
                .tabItem {
                    Label("Логи", systemImage: "text.alignleft")
                }

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape")
                }
        }
    }
}

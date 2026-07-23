import SwiftUI
import UIKit

struct ServerDashboardView: View {
    @EnvironmentObject private var controller: ServerController
    @State private var showBrowser = false
    @State private var confirmSafari = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusCard
                    runtimeCard
                    actions
                    backgroundWarning
                    updateCard
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("SillyTavern Server")
            .sheet(isPresented: $showBrowser) {
                if let url = controller.serverURL {
                    NavigationStack {
                        LocalWebView(url: url)
                            .navigationTitle("Localhost")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Готово") { showBrowser = false }
                                }
                            }
                    }
                }
            }
            .alert("Открыть Safari?", isPresented: $confirmSafari) {
                Button("Отмена", role: .cancel) {}
                Button("Открыть") {
                    guard let url = controller.serverURL else { return }
                    UIApplication.shared.open(url)
                }
            } message: {
                Text("Safari отправит приложение в фон. iOS вправе сразу приостановить Node runtime, поэтому localhost в Safari не гарантируется.")
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: controller.status.symbol)
                    .foregroundStyle(controller.status.color)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.status.rawValue)
                        .font(.headline)
                    Text(controller.activePort.map { "127.0.0.1:\($0)" } ?? "Порт пока не назначен")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.status == .starting || controller.status == .stopping {
                    ProgressView()
                }
            }

            if let error = controller.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .cardStyle()
    }

    private var runtimeCard: some View {
        VStack(spacing: 12) {
            valueRow("Приложение", controller.prototypeVersion)
            Divider()
            valueRow("Node runtime", controller.runtimeVersion)
            Divider()
            valueRow("SillyTavern", controller.bundledSillyTavernVersion)
        }
        .cardStyle()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await controller.start() }
            } label: {
                Label("Запустить", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(controller.status == .running || controller.status == .starting)

            HStack {
                Button {
                    Task { await controller.stop() }
                } label: {
                    Label("Стоп", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.status != .running)

                Button {
                    Task { await controller.restart() }
                } label: {
                    Label("Перезапуск", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.status != .running)
            }

            Button {
                showBrowser = true
            } label: {
                Label("Открыть внутри приложения", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(controller.serverURL == nil)

            Button {
                confirmSafari = true
            } label: {
                Label("Экспериментально открыть в Safari", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(controller.serverURL == nil)
        }
    }

    private var backgroundWarning: some View {
        Label {
            Text("Надёжный режим — встроенное окно. При переходе в Safari хост-приложение становится фоновым, и публичные API iOS не гарантируют работу локального сервера.")
                .font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
        }
        .cardStyle()
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Официальный релиз")
                .font(.headline)
            if let release = controller.availableRelease {
                Text(release.name ?? release.tagName)
                Text("Установка отключена до успешной проверки Node 22 на устройстве.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("Открыть описание релиза", destination: release.htmlURL)
                    .font(.footnote)
            } else {
                Text("Проверяется только официальный GitHub-репозиторий SillyTavern.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await controller.checkForUpdates() }
            } label: {
                if controller.isCheckingRelease {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Проверить обновления", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(controller.isCheckingRelease)
        }
        .cardStyle()
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

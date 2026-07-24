import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var controller: ServerController
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Сервер") {
                    Stepper(
                        "Предпочтительный порт: \(controller.preferredPort)",
                        value: $controller.preferredPort,
                        in: 1_024...65_535
                    )
                    Toggle("Автозапуск при открытии", isOn: $controller.autoStart)
                }

                Section("Логи") {
                    Toggle("Сохранять лог", isOn: $controller.saveLogs)
                    Stepper(
                        "Максимум: \(controller.maximumLogSizeMB) МБ",
                        value: $controller.maximumLogSizeMB,
                        in: 1...100
                    )
                }

                Section("Данные") {
                    Text(controller.directories?.userData.path ?? "Каталог ещё не создан")
                        .font(.caption)
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = controller.directories?.userData.path
                        copied = true
                    } label: {
                        Label(copied ? "Путь скопирован" : "Скопировать путь", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .disabled(controller.directories == nil)
                }

                Section("Ограничения iOS") {
                    Text("SillyTavern 1.18.0 запускается в отдельном Worker внутри NodeMobile. Стоп и перезапуск пересоздают Worker, не перезапуская node_start().")
                    Text("В режиме iOS без JIT недоступен WebAssembly: подсчёт токенов выполняется приблизительно, а серверная обработка WebP и AVIF временно отключена. PNG и JPEG поддерживаются.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Настройки")
        }
    }
}

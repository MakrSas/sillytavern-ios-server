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

                Section("Ограничение прототипа") {
                    Text("Стоп и перезапуск управляют HTTP-сервером внутри одного Node runtime. Повторный запуск node_start() в одном процессе официально не поддержан.")
                    Text("SillyTavern и его node_modules будут добавлены только после успешной сборки и device smoke-test Node 22.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Настройки")
        }
    }
}

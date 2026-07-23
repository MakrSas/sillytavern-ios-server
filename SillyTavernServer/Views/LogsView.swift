import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var controller: ServerController

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if controller.logs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.plaintext")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Лог пуст")
                                    .font(.headline)
                                Text("Здесь появятся stdout и stderr встроенного Node runtime.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 420)
                        } else {
                            ForEach(Array(controller.logs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: controller.logs.count) { count in
                    guard count > 0 else { return }
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            .navigationTitle("Логи")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: controller.logText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(controller.logs.isEmpty)

                    Button {
                        controller.clearLogs()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(controller.logs.isEmpty)
                }
            }
        }
    }
}

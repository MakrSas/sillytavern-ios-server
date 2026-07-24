import Foundation
import SwiftUI
import Combine

@MainActor
final class ServerController: ObservableObject {
    @Published private(set) var status: ServerStatus = .stopped
    @Published private(set) var activePort: Int?
    @Published private(set) var runtimeVersion = "Не запущен"
    @Published private(set) var logs: [String] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var directories: AppDirectories?
    @Published private(set) var availableRelease: GitHubRelease?
    @Published private(set) var isCheckingRelease = false

    @Published var preferredPort: Int {
        didSet {
            preferredPort = min(max(preferredPort, 1024), 65_535)
            defaults.set(preferredPort, forKey: Keys.preferredPort)
        }
    }

    @Published var autoStart: Bool {
        didSet { defaults.set(autoStart, forKey: Keys.autoStart) }
    }

    @Published var saveLogs: Bool {
        didSet { defaults.set(saveLogs, forKey: Keys.saveLogs) }
    }

    @Published var maximumLogSizeMB: Int {
        didSet {
            maximumLogSizeMB = min(max(maximumLogSizeMB, 1), 100)
            defaults.set(maximumLogSizeMB, forKey: Keys.maximumLogSizeMB)
        }
    }

    let prototypeVersion = "0.2.0"
    let bundledSillyTavernVersion = "1.18.0 — Stage 3"

    private enum Keys {
        static let preferredPort = "preferredPort"
        static let autoStart = "autoStart"
        static let saveLogs = "saveLogs"
        static let maximumLogSizeMB = "maximumLogSizeMB"
    }

    private struct ReadyMarker: Decodable {
        let port: Int
        let runtimeVersion: String?
    }

    private struct ErrorMarker: Decodable {
        let message: String
    }

    private let defaults: UserDefaults
    private let bridge = STNodeRuntimeBridge()
    private var controlPort: Int?
    private var partialLine = ""
    private var prepared = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedPort = defaults.integer(forKey: Keys.preferredPort)
        preferredPort = savedPort == 0 ? 8_000 : savedPort
        autoStart = defaults.object(forKey: Keys.autoStart) as? Bool ?? false
        saveLogs = defaults.object(forKey: Keys.saveLogs) as? Bool ?? true
        let savedSize = defaults.integer(forKey: Keys.maximumLogSizeMB)
        maximumLogSizeMB = savedSize == 0 ? 5 : savedSize
    }

    var serverURL: URL? {
        guard status == .running, let activePort else { return nil }
        return URL(string: "http://127.0.0.1:\(activePort)")
    }

    var logText: String {
        logs.joined(separator: "\n")
    }

    func prepare() async {
        guard !prepared else { return }
        prepared = true

        do {
            directories = try AppDirectories.create()
            appendLog("Каталоги приложения подготовлены.")
            if autoStart {
                await start()
            }
        } catch {
            fail("Не удалось подготовить sandbox: \(error.localizedDescription)")
        }
    }

    func start() async {
        errorMessage = nil

        if let controlPort {
            await runCommand("start", using: controlPort)
            return
        }

        guard !bridge.isStarted else {
            fail("Node runtime запущен, но управляющий сервер недоступен.")
            return
        }
        guard let directories else {
            fail("Каталоги приложения ещё не подготовлены.")
            return
        }
        guard let script = Bundle.main
            .url(forResource: "nodejs-project", withExtension: nil)?
            .appendingPathComponent("main.js")
        else {
            fail("В IPA отсутствует Resources/nodejs-project/main.js.")
            return
        }

        status = .starting
        appendLog("Запуск NodeMobile на 127.0.0.1; желаемый порт \(preferredPort)…")

        bridge.startScript(
            atPath: script.path,
            arguments: [
                "--preferred-port", String(preferredPort),
                "--data-directory", directories.userData.path
            ],
            logHandler: { [weak self] chunk in
                self?.consumeRuntimeOutput(chunk)
            },
            completion: { [weak self] exitCode, error in
                guard let self else { return }
                if let error {
                    self.fail(error)
                } else if exitCode != 0 {
                    self.fail("Node runtime завершился с кодом \(exitCode).")
                } else {
                    self.status = .stopped
                    self.appendLog("Node runtime завершён.")
                }
            }
        )
    }

    func stop() async {
        guard let controlPort else {
            status = .stopped
            return
        }
        status = .stopping
        await runCommand("stop", using: controlPort)
    }

    func restart() async {
        guard let controlPort else {
            await start()
            return
        }
        status = .starting
        await runCommand("restart", using: controlPort)
    }

    func refreshHealth() async {
        guard let controlPort else { return }
        do {
            let health = try await ControlClient(port: controlPort).health()
            runtimeVersion = health.runtimeVersion
            activePort = health.serverPort
            status = health.serverRunning ? .running : .stopped
        } catch {
            appendLog("Health check не прошёл: \(error.localizedDescription)")
        }
    }

    func checkForUpdates() async {
        isCheckingRelease = true
        defer { isCheckingRelease = false }

        do {
            let url = URL(string: "https://api.github.com/repos/SillyTavern/SillyTavern/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("SillyTavernServer-iOS/\(prototypeVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            availableRelease = try JSONDecoder().decode(GitHubRelease.self, from: data)
            appendLog("Последний официальный релиз SillyTavern: \(availableRelease?.tagName ?? "неизвестно").")
        } catch {
            fail("Не удалось проверить релиз: \(error.localizedDescription)")
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            Task { await refreshHealth() }
        case .background:
            appendLog("Приложение ушло в фон. iOS может приостановить Node runtime и localhost.")
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func runCommand(_ command: String, using controlPort: Int) async {
        do {
            let result = try await ControlClient(port: controlPort)
                .command(command, preferredPort: preferredPort)
            if result.ok {
                activePort = result.port
                status = result.state == "running" ? .running : .stopped
                appendLog("Команда \(command): \(result.state)\(result.port.map { ", порт \($0)" } ?? "").")
            } else {
                fail(result.error ?? "Управляющий сервер вернул ошибку.")
            }
        } catch {
            fail("Команда \(command) не выполнена: \(error.localizedDescription)")
        }
    }

    private func consumeRuntimeOutput(_ chunk: String) {
        partialLine += chunk
        let parts = partialLine.components(separatedBy: .newlines)
        partialLine = parts.last ?? ""

        for line in parts.dropLast() where !line.isEmpty {
            appendLog(line)
            parseMarker(line)
        }
    }

    private func parseMarker(_ line: String) {
        if let payload = markerPayload("ST_CONTROL_READY", in: line),
           let marker = try? JSONDecoder().decode(ReadyMarker.self, from: Data(payload.utf8)) {
            controlPort = marker.port
            if let version = marker.runtimeVersion {
                runtimeVersion = version
            }
            appendLog("Управляющий канал готов на 127.0.0.1:\(marker.port).")
            return
        }

        if let payload = markerPayload("ST_SERVER_READY", in: line),
           let marker = try? JSONDecoder().decode(ReadyMarker.self, from: Data(payload.utf8)) {
            activePort = marker.port
            if let version = marker.runtimeVersion {
                runtimeVersion = version
            }
            status = .running
            appendLog("HTTP smoke-server отвечает на 127.0.0.1:\(marker.port).")
            return
        }

        if line.hasPrefix("[ST_SERVER_STOPPED]") {
            activePort = nil
            status = .stopped
            return
        }

        for markerName in ["ST_SERVER_ERROR", "ST_RUNTIME_ERROR"] {
            if let payload = markerPayload(markerName, in: line),
               let marker = try? JSONDecoder().decode(ErrorMarker.self, from: Data(payload.utf8)) {
                fail(marker.message)
                return
            }
        }
    }

    private func markerPayload(_ marker: String, in line: String) -> String? {
        let prefix = "[\(marker)] "
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private func appendLog(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date()))  \(message)"
        logs.append(line)
        if logs.count > 2_000 {
            logs.removeFirst(logs.count - 2_000)
        }
        persist(line: line)
    }

    private func persist(line: String) {
        guard saveLogs, let logURL = directories?.logs.appendingPathComponent("runtime.log") else { return }
        let data = Data((line + "\n").utf8)
        do {
            if !FileManager.default.fileExists(atPath: logURL.path) {
                try data.write(to: logURL, options: .atomic)
                return
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: logURL.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            if size + data.count > maximumLogSizeMB * 1_024 * 1_024 {
                try Data().write(to: logURL, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Persistence must not take the server down.
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        status = .failed
        appendLog("ОШИБКА: \(message)")
    }
}

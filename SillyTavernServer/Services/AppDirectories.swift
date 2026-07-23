import Foundation

struct AppDirectories {
    let root: URL
    let runtime: URL
    let userData: URL
    let updates: URL
    let backups: URL
    let logs: URL

    static func create() throws -> AppDirectories {
        let manager = FileManager.default
        let support = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appendingPathComponent("SillyTavernServer", isDirectory: true)
        let directories = AppDirectories(
            root: root,
            runtime: root.appendingPathComponent("Runtime", isDirectory: true),
            userData: root.appendingPathComponent("UserData", isDirectory: true),
            updates: root.appendingPathComponent("Updates", isDirectory: true),
            backups: root.appendingPathComponent("Backups", isDirectory: true),
            logs: root.appendingPathComponent("Logs", isDirectory: true)
        )

        for url in [
            directories.root,
            directories.runtime,
            directories.userData,
            directories.updates,
            directories.backups,
            directories.logs
        ] {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return directories
    }
}

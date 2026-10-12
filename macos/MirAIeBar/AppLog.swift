import Foundation

enum AppLog {
    static let url: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MirAIeBar", isDirectory: true)
        .appendingPathComponent("app.log")

    private static let queue = DispatchQueue(label: "dev.openmiraie.applog")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        queue.async {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}

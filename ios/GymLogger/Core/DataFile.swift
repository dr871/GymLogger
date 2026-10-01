import Foundation

/// Reading and writing the one file that holds everything.
///
/// This lives in Core, with no UIKit or SwiftUI, because it is the part where a
/// mistake costs someone their training history — so it has to be testable
/// without a simulator. `Store` adds the debounce, the notifications and the
/// SwiftUI plumbing on top.
///
/// The live file is the data. The mirror is a copy kept in the app's Documents
/// folder, which iOS shows in the Files app: handy to grab, and a second chance
/// if the live file is ever torn by a crash mid-write.
struct DataFile {
    let url: URL
    /// nil when there is nowhere to keep a visible copy.
    let mirror: URL?

    /// The live file, then the mirror, then the seeded workout. A file that
    /// decodes to nothing counts as no file: an empty app helps nobody.
    func load(now: Date = Date()) -> AppData {
        if let data = Self.read(url, setAsideIfDamaged: true, now: now) { return data }
        if let mirror, let data = Self.read(mirror, setAsideIfDamaged: false, now: now) { return data }
        return .seed()
    }

    /// Writes the live file, then refreshes the mirror. A mirror that can't be
    /// written is not worth failing the save over.
    func save(_ data: AppData) throws {
        let encoded = try data.exportJSON()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)

        if let mirror {
            try? FileManager.default.createDirectory(at: mirror.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? encoded.write(to: mirror, options: .atomic)
        }
    }

    /// nil when the file is missing, unreadable, or holds nothing.
    private static func read(_ url: URL, setAsideIfDamaged: Bool, now: Date) -> AppData? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        do {
            var decoded = try AppData.decoder().decode(AppData.self, from: raw)

            // Written by a newer build — running an older one again is easy
            // when a free-account build is reinstalled every week. Decoding has
            // already dropped whatever this build doesn't know about, and the
            // next save would write that loss straight back over the file, with
            // no error and nothing set aside. Keep the original verbatim first.
            if decoded.version > AppData.schemaVersion, setAsideIfDamaged {
                let kept = url.deletingPathExtension()
                    .appendingPathExtension("v\(decoded.version).json")
                if !FileManager.default.fileExists(atPath: kept.path) {
                    try? raw.write(to: kept, options: .atomic)
                }
            }

            decoded.pruneExpiredTimer(at: now)
            return decoded.exercises.isEmpty && decoded.sessions.isEmpty ? nil : decoded
        } catch {
            // Keep the original beside it rather than overwriting the only copy
            // of someone's history. Only ever the live file: the mirror is a
            // copy, and setting it aside would just litter the Files app.
            if setAsideIfDamaged {
                let aside = url.deletingPathExtension().appendingPathExtension("corrupt.json")
                try? FileManager.default.removeItem(at: aside)
                try? FileManager.default.moveItem(at: url, to: aside)
            }
            return nil
        }
    }
}

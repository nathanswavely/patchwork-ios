// SPDX-License-Identifier: MPL-2.0
import Foundation

/// The last answers a quilt gave, kept on this device so the next launch
/// draws the quilt at once and reads it again behind the drawing, rather than
/// opening on a spinner every time.
///
/// Three reads are kept, all of them ones a reader without an account is
/// served too: the whole tree, the quilt's own description, and its icon.
/// They live in Caches, which the system may clear when space is short; a
/// missing file only means that launch waits on the network the way every
/// launch used to. Forgetting a quilt forgets what was kept of it.
enum QuiltKeep {
    enum Answer: String { case tree, instance, icon }
    static func read(_ answer: Answer, of quilt: Quilt) -> Data? {
        // Preview is fixtures all the way down: nothing kept is read into it.
        guard !previewing else { return nil }
        return try? Data(contentsOf: file(answer, quilt))
    }
    static func write(_ data: Data, as answer: Answer, of quilt: Quilt) {
        guard !previewing else { return }
        let url = file(answer, quilt)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
    static func forget(_ quilt: Quilt) { try? FileManager.default.removeItem(at: folder(quilt)) }

    /// One folder per quilt, named for its address.
    static func folder(_ quilt: Quilt) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let address = (quilt.url.host() ?? quilt.id) + (quilt.url.port.map { "_\($0)" } ?? "")
        let name = String(address.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
        return caches.appendingPathComponent("quilts", isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }
    private static func file(_ answer: Answer, _ quilt: Quilt) -> URL {
        folder(quilt).appendingPathComponent(answer.rawValue)
    }
    private static var previewing: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview")
        #else
        false
        #endif
    }
}

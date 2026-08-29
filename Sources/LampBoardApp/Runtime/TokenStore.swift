import LampBoardCore
import Foundation

/// Keeps the token authorizing `GET /sessions` on disk.
///
/// The file lives at `~/.lampboard/token` with mode `0600`. If the permissions
/// turn out to be wider the token is **regenerated**, not repaired: a secret that
/// has been readable by others must be considered compromised, and silently
/// fixing the permissions would leave a value in circulation that has already
/// been seen.
struct TokenStore {
    private let url: URL
    private let fileManager: FileManager

    init(url: URL = AppConfig.tokenURL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    var path: String { url.path }

    /// Reads the existing token or creates a new one.
    /// - Returns: the token, or `nil` when the disk won't cooperate — in which
    ///   case the read endpoint stays closed rather than opening up undefended.
    func loadOrCreate() -> String? {
        if let existing = read() { return existing }
        return create()
    }

    /// Reads the token, if it exists and is stored correctly.
    func read() -> String? {
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8)?.trimmed,
              AccessToken.isWellFormed(raw),
              hasPrivatePermissions
        else {
            return nil
        }
        return raw
    }

    // MARK: - Internal

    private var hasPrivatePermissions: Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            return false
        }
        // No bits for group or others.
        return permissions.int16Value & 0o077 == 0
    }

    private func create() -> String? {
        let token = AccessToken.generate()
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // The file is created with the right permissions from the start:
            // writing it and then tightening them would leave a window in which
            // the secret is readable.
            try? fileManager.removeItem(at: url)
            guard fileManager.createFile(
                atPath: url.path,
                contents: Data(token.utf8),
                attributes: [.posixPermissions: 0o600]
            ) else {
                return nil
            }
            return token
        } catch {
            Diagnostics.log("token not writable: \(error.localizedDescription)")
            return nil
        }
    }
}

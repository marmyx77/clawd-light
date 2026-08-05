import Foundation

/// Builds the deep link that opens a session's Claude **tab**, not just the
/// window containing it.
///
/// The VS Code extension registers a URI handler for the `/open` path and reads
/// its `session` and `prompt` parameters, forwarding them to the internal command
/// `claude-vscode.primaryEditor.open`. Verified by reading `extension.js` of
/// version 2.1.220:
///
/// ```js
/// case "/open": {
///   let w = x.get("session"), E = x.get("prompt");
///   executeCommand("claude-vscode.primaryEditor.open", w, E);
/// }
/// ```
///
/// This is an extension's internal contract, not a public API: it can change
/// without warning. That is why opening the tab is a bonus layered on top of
/// activating the window, never a replacement — if it stops working, the click
/// still takes you to the right window.
public enum SessionDeepLink {

    /// Extension identifier, in the `publisher.name` form the `vscode://` scheme
    /// requires.
    public static let extensionIdentifier = "Anthropic.claude-code"

    /// URL that opens the tab of the given session.
    ///
    /// - Returns: `nil` when the session id is empty or not representable in a URL.
    public static func url(forSessionId sessionId: String) -> URL? {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "vscode"
        components.host = extensionIdentifier
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "session", value: trimmed)]
        return components.url
    }

    /// URL that opens a **new** conversation in the focused window.
    ///
    /// Same path without the `session` parameter: the internal command receives
    /// `undefined` and opens an empty tab instead of reattaching to an existing
    /// session.
    public static var newConversationURL: URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = extensionIdentifier
        components.path = "/open"
        return components.url
    }
}

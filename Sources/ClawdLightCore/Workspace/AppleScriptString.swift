import Foundation

/// Makes a piece of text safe inside an AppleScript string literal.
///
/// Needed ever since the window is raised **by title** instead of by index. The
/// change fixed a real defect — the window order shifts between reading it and
/// raising it, so an index points somewhere else — but it brought text the user
/// controls into the script source: VS Code's title contains the name of the
/// open file.
///
/// A file called `say "hello".txt` would close the string halfway through, and the
/// rest of the name would be interpreted as code. This is not a theoretical
/// scenario: one file downloaded from somebody else is enough for the name to stop
/// being something you decide.
public enum AppleScriptString {

    /// The text with backslashes and quotes escaped.
    ///
    /// The order matters: backslashes first, then quotes. Reverse it and the
    /// backslash added to escape a quote would itself get escaped, giving the
    /// wrong result.
    public static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

import LampBoardCore
import Foundation

/// Finds the Codex sessions running on this machine, without being told.
///
/// Codex inside the ChatGPT app registers our hooks, marks them trusted, runs a
/// full session, writes every event to its rollout, and sends no signal at all.
/// Measured, not assumed: eight events configured with trusted hashes, a rollout
/// updated at the second a message was answered, and not one line in the log.
/// Anything built on hooks alone is blind to it.
///
/// So the evidence runs the other way. A live `codex` process holds its rollout
/// open; the file says which session and which folder; the binary says which
/// surface. Nothing has to be sent to us, and nothing unauthenticated is believed.
final class CodexProcessScanner {

    /// The first record of a rollout never changes, so it is read once per file.
    private var metaByPath: [String: CodexSessionMeta] = [:]

    /// The tail is re-read only when the file has grown. A poll every five
    /// seconds across a handful of rollouts would otherwise read a megabyte a
    /// minute to learn nothing.
    private var tailByPath: [String: (size: UInt64, moment: Date)] = [:]

    /// Paths already complained about, so a poll every five seconds does not
    /// write the same line twelve times a minute.
    private var unreadable: Set<String> = []

    /// One pass. Cheap enough for a poll: one process enumeration and one `lsof`,
    /// both bounded.
    func scan(
        sessionsRoot: URL = AppConfig.codexSessionsDirectory,
        deadline: TimeInterval = AppConfig.focusProbeTimeout
    ) -> CodexScanResult {
        let pids = ProcessTree.pids(named: "codex")
        guard !pids.isEmpty else { return .observed([]) }

        guard let lsof = ["/usr/sbin/lsof", "/usr/bin/lsof"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return .unavailable("lsof is not on this machine") }

        let result: Command.Result
        do {
            result = try Command.run(
                lsof,
                // Field output, and only the pids we already found. Asking `lsof`
                // for everything is what makes it stat a network mount and pause.
                ["-nP", "-F", "pcftn", "-p", pids.map(String.init).joined(separator: ",")],
                deadline: deadline,
                capturingStandardError: false
            )
        } catch {
            return .unavailable((error as? Command.Failure)?.explanation ?? "\(error)")
        }

        // `lsof` exits 1 when some of the pids are gone, which is normal here: a
        // session can end between enumerating and asking. What it printed is still
        // good, so the status is not a failure by itself.
        // Both spellings, because `lsof` reports the real path and the root may be
        // reached through a link. `/var` is a link to `/private/var` on every Mac,
        // and Foundation's own `resolvingSymlinksInPath` leaves `/var/folders`
        // untouched by design, so this asks `realpath` and keeps the answer
        // alongside the original.
        //
        // The failure it prevents is the quiet kind: the scan succeeds, matches
        // nothing, and reports no sessions.
        let open = LsofOpenFiles.under(
            Self.spellings(of: sessionsRoot.path), in: LsofOpenFiles.parse(result.output)
        )
        guard !open.isEmpty else {
            return result.output.isEmpty && !result.succeeded
                ? .unavailable("lsof said nothing and exited \(result.status)")
                : .observed([])
        }

        return .observed(open.compactMap { file in
            guard file.path.hasSuffix(".jsonl"), let meta = meta(atPath: file.path) else { return nil }
            // A subagent's rollout is not a conversation. It is held open by the
            // same process as its parent and it carries the **parent's**
            // `session_id`, so read as a session it becomes a second evidence
            // for a row that already exists — and if it arrives first it becomes
            // that row's transcript, which is then the wrong thread back to the
            // window and the wrong source for its context and its clock.
            //
            // Measured here on 30 August: 26 rollouts, 3 of them subagents, two
            // of those naming the same parent. The parent's own rollout is open
            // beside them, so nothing is lost by refusing these.
            guard !meta.isSubagent else { return nil }
            let executable = ProcessTree.path(of: file.pid)
            return CodexEvidence(
                meta: meta,
                rolloutPath: file.path,
                pid: file.pid,
                executable: executable,
                surface: CodexSurface.of(executable: executable),
                lastActivity: lastActivity(atPath: file.path)
            )
        })
    }

    /// A path as written, and as the filesystem really spells it.
    private static func spellings(of path: String) -> [String] {
        guard let resolved = realpath(path, nil) else { return [path] }
        defer { free(resolved) }
        let real = String(cString: resolved)
        return real == path ? [path] : [path, real]
    }

    // MARK: - Reading the file

    private func meta(atPath path: String) -> CodexSessionMeta? {
        if let cached = metaByPath[path] { return cached }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: CodexSessionMetaReader.headLimit),
              let meta = CodexSessionMetaReader.read(head: String(decoding: data, as: UTF8.self))
        else {
            // A file a live process is holding open, in Codex's own sessions
            // directory, whose first record we cannot read. Failing closed is
            // right and failing **silently** is not: the symptom is a session that
            // never appears, which from the outside is indistinguishable from the
            // scanner being switched off. Codex calls this format unstable, so
            // this line is what will say so the day it moves.
            if unreadable.insert(path).inserted {
                Diagnostics.log("codex: cannot read session_meta from \(path)")
            }
            return nil
        }
        metaByPath[path] = meta
        return meta
    }

    /// When the conversation last said something, from the last record that
    /// carries a timestamp.
    ///
    /// The file's modification date is not that, and this project has already
    /// been bitten by assuming it was: three Claude projects untouched for days
    /// read as active within the hour because tooling had appended records with
    /// no timestamp at all. A rollout is written by a different program and the
    /// same rule applies, for the same reason.
    private func lastActivity(atPath path: String) -> Date {
        guard let handle = FileHandle(forReadingAtPath: path) else { return .distantPast }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return .distantPast }

        if let cached = tailByPath[path], cached.size == size { return cached.moment }

        let slice = UInt64(TranscriptActivity.tailLimit)
        let wholeFile = slice >= size
        guard (try? handle.seek(toOffset: wholeFile ? 0 : size - slice)) != nil,
              let data = try? handle.readToEnd(),
              let moment = TranscriptActivity.lastTimestamp(
                  inTailChunk: String(decoding: data, as: UTF8.self), isWholeFile: wholeFile
              )
        else { return tailByPath[path]?.moment ?? .distantPast }

        tailByPath[path] = (size, moment)
        return moment
    }
}

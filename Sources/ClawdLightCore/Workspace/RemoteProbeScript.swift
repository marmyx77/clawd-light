import Foundation

/// The script that runs **on** the remote machine.
///
/// It lives in Core, and in one piece, for the same reason the hook script does:
/// it is a promise made to another machine, and a promise you cannot read in one
/// place is a promise nobody checks. It is also under test — the shape it emits is
/// what `RemoteSessionsDecoder` parses, and the two must not drift apart.
///
/// **Why the work happens there and not here.** Two of the three facts a row needs
/// are only true where the processes are: whether the pid is alive, and when the
/// transcript last changed. Shipping the files here and deciding locally would
/// answer both questions about the wrong machine.
///
/// Nothing is installed on the node and nothing is left behind: the script is
/// piped to `python3` over the ssh connection and dies with it.
public enum RemoteProbeScript {

    /// `python3` because it is the one interpreter present on every machine that
    /// runs Claude Code, and because the encoding rule below has to match
    /// `TranscriptLocator` exactly — expressing it in shell would mean two
    /// dialects of the same rule.
    public static let script = """
    import json, os, glob, re, sys

    def encoded(cwd):
        return "-" + re.sub(r"[^a-zA-Z0-9]", "-", cwd.lstrip("/"))

    def alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            # The process exists and belongs to somebody else. Still alive.
            return True
        except Exception:
            return False

    out = []
    for path in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
        try:
            record = json.load(open(path))
            pid = int(os.path.basename(path).split(".")[0])
        except Exception:
            continue
        if not alive(pid):
            continue
        cwd = record.get("cwd") or ""
        # The session file is written once at startup and never touched again, so
        # on its own it reports how long the session has been open, not when it
        # last did anything. The transcript is the real signal.
        try:
            activity = os.path.getmtime(path)
        except OSError:
            continue
        folder = os.path.expanduser("~/.claude/projects/") + encoded(cwd)
        for transcript in glob.glob(folder + "/*.jsonl"):
            try:
                activity = max(activity, os.path.getmtime(transcript))
            except OSError:
                pass
        out.append({
            "pid": pid,
            "sessionId": record.get("sessionId"),
            "cwd": cwd,
            "entrypoint": record.get("entrypoint"),
            "name": record.get("name"),
            "kind": record.get("kind"),
            "activityEpoch": int(activity),
        })

    json.dump(out, sys.stdout)
    """
}

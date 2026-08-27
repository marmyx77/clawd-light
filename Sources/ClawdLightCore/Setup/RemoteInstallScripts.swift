import Foundation

/// The two scripts that run **on** another machine to install or remove the hooks.
///
/// In Core, in one piece and under test, for the reason the probe is: a promise
/// made to another machine has to be readable in one place. Nothing else is
/// installed there — `python3 -` reads each script from stdin and the process
/// dies with the connection.
///
/// **No shell touches the data.** The merged settings and the hook script travel
/// *inside* the Python source as one base64 literal: no quoting rule of any shell
/// is involved, so no content of `settings.json` — however hostile — can change
/// what the script does.
public enum RemoteInstallScripts {

    /// Reports what the machine has: its home, Claude Code's settings (`null` if
    /// unreadable, `{}` if absent), the Python version and whether `curl` exists
    /// — the hook script needs it.
    public static let inspect = """
    import json, os, platform, shutil, sys

    home = os.path.expanduser("~")
    settings_path = os.path.join(home, "\(AppConfig.remoteClaudeSettingsRelativePath)")
    settings, error = None, None
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except FileNotFoundError:
        settings = {}
    except Exception as e:
        error = str(e)

    json.dump({
        "home": home,
        "settings": settings,
        "python": platform.python_version(),
        "curl": shutil.which("curl") is not None,
        "error": error,
    }, sys.stdout)
    """

    /// Writes the hook script and the merged settings, atomically and with a dated
    /// backup of the settings, or removes the script when asked.
    ///
    /// - Parameter payloadBase64: a JSON object with `scriptRelativePath`,
    ///   `settingsRelativePath`, `settings` (the whole merged file), and either
    ///   `hookScript` (install) or `removeScript: true` (uninstall).
    public static func apply(payloadBase64: String) -> String {
        """
        import base64, json, os, sys, time

        payload = json.loads(base64.b64decode("\(payloadBase64)").decode("utf-8"))
        home = os.path.expanduser("~")
        script_path = os.path.join(home, payload["scriptRelativePath"])
        settings_path = os.path.join(home, payload["settingsRelativePath"])

        if payload.get("hookScript") is not None:
            os.makedirs(os.path.dirname(script_path), exist_ok=True)
            with open(script_path, "w") as f:
                f.write(payload["hookScript"])
            os.chmod(script_path, 0o755)
        elif payload.get("removeScript") and os.path.exists(script_path):
            os.remove(script_path)

        backup = None
        if os.path.exists(settings_path):
            backup = settings_path + ".bak-clawd-" + time.strftime("%Y%m%d-%H%M%S")
            with open(settings_path) as src, open(backup, "w") as dst:
                dst.write(src.read())
        os.makedirs(os.path.dirname(settings_path), exist_ok=True)
        tmp = settings_path + ".tmp-clawd"
        with open(tmp, "w") as f:
            json.dump(payload["settings"], f, indent=2, sort_keys=True)
            f.write("\\n")
        os.replace(tmp, settings_path)

        json.dump({"ok": True, "backup": backup, "scriptPath": script_path}, sys.stdout)
        """
    }

    /// Whether the tunnel reaches this machine: asked *from* the node, because
    /// that is the only place the question means anything.
    public static let checkTunnel = """
    import sys, urllib.request, urllib.error

    try:
        urllib.request.urlopen("http://127.0.0.1:\(AppConfig.listenPort)\(AppConfig.signalPath)", timeout=3)
        print("200")
    except urllib.error.HTTPError as e:
        print(e.code)
    except Exception as e:
        print("unreachable: %s" % e)
    """
}

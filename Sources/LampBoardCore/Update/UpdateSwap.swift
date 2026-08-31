import Foundation

/// The script that finishes an update after the application has quit.
///
/// It is here, as text, for two reasons.
///
/// **It has to be testable.** The swap is the one part of updating that cannot
/// be exercised from inside the running application: it starts by waiting for
/// that application to die. A test can run this exact text against two fake
/// bundles, which is what caught the defect below.
///
/// **And it must not be a file.** The first version wrote `swap.sh` into the
/// same temporary directory as the staged application, and `install()` deleted
/// that directory the moment it returned — while the script was still in its
/// wait loop. By the time it reached the move, what it was moving had been
/// erased: the application quit, the swap rolled back, and nothing changed.
/// Deterministic, and shipped.
///
/// Passing the body through `bash -c` removes the class of problem rather than
/// the instance. There is no script on disk to be deleted, and no question about
/// whether bash had finished reading it, so the workspace can be cleaned by the
/// script itself as its last act.
public enum UpdateSwap {

    /// `bash -c <body> swap <new> <old> <pid> <workspace>`.
    ///
    /// The order of operations is the whole of it. The old application is moved
    /// aside rather than deleted, so a failure leaves a Mac with an application
    /// rather than with nothing; the backup only goes once the new one is in
    /// place; and the workspace goes last, whichever way it ended.
    public static let body = """
        set -u
        NEW="$1"; OLD="$2"; PID="$3"; WORKSPACE="$4"

        # The application is quitting on its own; this waits for it rather than
        # killing it, so anything it saves on the way out gets saved.
        for _ in $(seq 1 100); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.1
        done

        BACKUP="$OLD.replaced"
        rm -rf "$BACKUP"
        if ! mv "$OLD" "$BACKUP"; then
            rm -rf "$WORKSPACE"
            exit 1
        fi

        if mv "$NEW" "$OLD"; then
            rm -rf "$BACKUP"
        else
            mv "$BACKUP" "$OLD"
            rm -rf "$WORKSPACE"
            exit 1
        fi

        rm -rf "$WORKSPACE"

        # Best effort, and deliberately not part of the verdict. The exit status
        # of this script answers one question — was the application replaced —
        # and it used to answer `open`'s question instead, so a swap that had
        # worked reported failure when the relaunch did not.
        #
        # The launcher is a variable for one reason, the same one `LAMPBOARD_HOME`
        # exists for: without it the only way to test the swap is to let it raise
        # a window on whoever is running the suite.
        "${LAMPBOARD_UPDATE_OPEN:-/usr/bin/open}" "$OLD" || true
        """
}

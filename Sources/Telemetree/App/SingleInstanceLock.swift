import AppKit

/// Prevents two Telemetree processes from running at once — found the hard
/// way this session: a leftover Homebrew-installed instance and a locally
/// built dev instance running side by side made every test unreliable
/// (clicks/keystrokes landing on whichever window happened to be frontmost,
/// not the one actually being scripted against).
///
/// Adapted from GhostBar's SingleInstanceLock — same flock()-based approach
/// (atomic, kernel-enforced, can't race the way an NSWorkspace
/// list-running-apps check can when two instances launch close together).
/// Telemetree has a real window though, so unlike GhostBar's menu-bar
/// accessory app, the second instance activates the first instead of just
/// silently quitting.
enum SingleInstanceLock {
    private static var lockFileDescriptor: Int32 = -1

    /// Call once, as early as possible in startup, before any UI setup.
    /// If another instance already holds the lock, brings it to the front
    /// and terminates this one.
    static func acquireOrActivateExisting() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Telemetree")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockPath = dir.appendingPathComponent("instance.lock").path

        let fd = open(lockPath, O_CREAT | O_WRONLY, 0o644)
        guard fd != -1 else { return } // can't create the lock file — fail open rather than blocking launch

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            activateExistingInstance()
            exit(0)
        }

        lockFileDescriptor = fd
    }

    /// No bundle identifier to filter by for a bare dev binary (only a
    /// real .app has one) — process name is the one thing every build
    /// variant (swift run, this dev binary, the packaged .app) shares.
    private static func activateExistingInstance() {
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == "Telemetree" && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        others.first?.activate()
    }
}

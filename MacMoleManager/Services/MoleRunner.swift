//
//  MoleRunner.swift
//  MacStorageManager
//
//  Thin async/await wrapper around the `mole` CLI binary. Every subcommand
//  here mirrors an exact invocation already proven out in
//  MacStorageCheckBeta.sh (WKU-Fleet-and-MDM repo) — ported as-is, just
//  without the swiftDialog/root/runAsUser plumbing around it:
//
//    mole --version
//    mole status --json
//    mole analyze --json <path>
//    mole clean --dry-run
//    mole clean                 (Mole prompts "Proceed? [y/N]" on stdin)
//    mole uninstall --list
//    mole uninstall <appName>   (no --dry-run flag; feed /dev/null on stdin
//                                 for a safe preview, pipe "y\n" to execute)
//
//  Casey: if mole's actual `--json` output shape differs from the loose
//  models in MoleModels.swift, run e.g. `mole status --json | pbcopy` in
//  Terminal, paste the real payload, and adjust the Decodable structs —
//  the runner itself doesn't need to change.
//

import Foundation

enum MoleError: LocalizedError {
    case binaryNotFound
    case homebrewNotFound
    case processFailed(exitCode: Int32, output: String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Couldn't find the mole binary. Checked /usr/local/bin/mole and $PATH."
        case .homebrewNotFound:
            return "Mole was installed via Homebrew, but the brew binary itself couldn't be found. Run `brew upgrade mole` manually in Terminal."
        case .processFailed(let code, let output):
            return "mole exited with code \(code):\n\(output)"
        case .decodingFailed(let raw):
            return "Couldn't parse mole's JSON output:\n\(raw.prefix(500))"
        }
    }
}

/// Which install path put the resolved `mole` binary on disk. Matters only
/// for updates — see `MoleRunner.updateViaHomebrew()`.
enum MoleInstallSource {
    case directDownload
    case homebrew
}

actor MoleRunner {

    static let shared = MoleRunner()

    /// The install script Mole itself documents (https://mole.fit → tw93/mole).
    /// Running this instead of vendoring a binary keeps the app on Mole's own
    /// release cadence — `mo update` later moves it forward the same way.
    ///
    /// Not `private`: AppViewModel.performElevatedInstall() reuses this exact
    /// command inside a pty session when the plain `install()` below fails —
    /// see that method's doc comment for why a second, differently-plumbed
    /// attempt is sometimes needed.
    static let installScriptCommand =
        "curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash"

    /// Resolved once and cached — mirrors discoverMoleBin() from the shell script,
    /// minus the console-user complications (this process already runs as the user).
    private var cachedBinaryPath: String?

    private let candidatePaths = [
        "/usr/local/bin/mole",          // direct-download install (primary, per the shell script)
        "/opt/homebrew/bin/mole",       // Apple Silicon Homebrew
        "/usr/local/homebrew/bin/mole", // Intel Homebrew, some setups
    ]

    // MARK: - Binary discovery

    func resolveBinaryPath() throws -> String {
        if let cached = cachedBinaryPath { return cached }

        let fm = FileManager.default
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            cachedBinaryPath = path
            return path
        }

        // Fall back to PATH lookup, same spirit as the shell script's later fallback.
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/mole"
                if fm.isExecutableFile(atPath: candidate) {
                    cachedBinaryPath = candidate
                    return candidate
                }
            }
        }

        throw MoleError.binaryNotFound
    }

    func isBinaryAvailable() -> Bool {
        (try? resolveBinaryPath()) != nil
    }

    /// Homebrew always symlinks a formula's binaries into `<prefix>/bin`
    /// from a `Cellar` (or `Caskroom`) tree — checking the *resolved* real
    /// path is more reliable than just matching the /opt/homebrew or
    /// /usr/local/homebrew candidate strings above, since a direct-download
    /// install could in principle land in a similar-looking /usr/local/bin.
    func installSource() -> MoleInstallSource {
        guard let path = try? resolveBinaryPath() else { return .directDownload }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return (resolved.contains("/Cellar/") || resolved.contains("/Caskroom/")) ? .homebrew : .directDownload
    }

    /// Path to the `brew` binary matching whichever prefix mole itself was
    /// installed under — Apple Silicon and Intel Homebrew keep separate
    /// prefixes, each with their own `brew`.
    private func resolveHomebrewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func version() async throws -> String {
        let output = try await run(arguments: ["--version"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `mo update` — updates to the latest stable release. No stdin prompt
    /// (unlike clean/uninstall), so no confirmation text needs to be piped in.
    ///
    /// Mole internally checks `sudo -n true` before doing anything that needs
    /// admin rights, and only falls back to its own /dev/tty-based password
    /// prompt if that's not already cached. Launched from inside a GUI app
    /// there is no controlling terminal, so that fallback prompt always fails
    /// with "/dev/tty: Device not configured" and mole aborts. If that
    /// happens, call `update(withAdminPassword:)` instead.
    func update() async throws -> String {
        try await run(arguments: ["update"])
    }

    /// Runs `sudo -S mole update`, authenticating with the given password over
    /// stdin (no controlling terminal needed for `-S`). This runs mole itself
    /// as root, rather than trying to pre-warm sudo's timestamp cache in a
    /// separate process and hoping mole's own `sudo -n true` check picks it
    /// up afterwards — with `tty_tickets` enabled (macOS's default), sudo
    /// credential caching is scoped per session/tty, so a ticket earned in
    /// one `Process` invocation isn't reliably visible to mole's own
    /// subprocess. Running mole itself as root sidesteps that: sudo never
    /// prompts a process that's already root, so mole's internal check
    /// passes immediately and its broken tty prompt is never reached.
    func update(withAdminPassword password: String) async throws -> String {
        let binary = try resolveBinaryPath()
        return try await runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/sudo"),
            arguments: ["-S", "-p", "", binary, "update"],
            stdinText: password + "\n"
        )
    }

    /// `brew upgrade mole` — used instead of `mole update`/`mo update`
    /// whenever `installSource()` reports `.homebrew`. This deliberately
    /// never goes through mole's own `update` subcommand for a Homebrew
    /// install, and never through `update(withAdminPassword:)` either.
    ///
    /// Mole's own internal updater already detects a Homebrew install and
    /// shells out to `brew upgrade` itself — but run that under
    /// `sudo mole update` (the admin-password fallback above) and it fails
    /// two different ways: sudo's restricted `secure_path` doesn't include
    /// Homebrew's bin directory, so `brew` isn't found at all ("Can't exec
    /// 'brew': No such file or directory"); and even with PATH fixed,
    /// Homebrew refuses outright to run as root ("Running Homebrew as root
    /// is extremely dangerous and no longer supported") — a deliberate
    /// Homebrew security policy, not a bug to route around. There is no
    /// sudo-based path that ever makes `brew upgrade` succeed. Running it
    /// ourselves, unprivileged, as the already-logged-in user — exactly how
    /// Homebrew expects to be invoked — sidesteps both failures at once
    /// instead of fighting a combination Homebrew blocks on purpose.
    func updateViaHomebrew() async throws -> String {
        guard let brewPath = resolveHomebrewPath() else {
            throw MoleError.homebrewNotFound
        }
        return try await runProcess(
            executableURL: URL(fileURLWithPath: brewPath),
            arguments: ["upgrade", "mole"]
        )
    }

    // MARK: - Install

    /// Runs Mole's own installer end to end via a plain Process/Pipe child —
    /// no controlling terminal, so this only works when install.sh never
    /// needs to elevate (i.e. `/usr/local/bin` already exists and is
    /// user-writable, the common case on a Mac that's had Homebrew or Xcode's
    /// Command Line Tools installed before). On success, forgets any cached
    /// (missing) binary path so the next call re-discovers the freshly
    /// installed one instead of continuing to report "not found."
    ///
    /// Confirmed live: on a genuinely fresh Mac, install.sh decides it needs
    /// sudo (its own `needs_sudo()`, when `/usr/local/bin` doesn't exist yet
    /// or isn't writable) and its lock-reauthentication step reads/writes
    /// `/dev/tty` directly — which a Pipe-backed child has none of, so it
    /// fails outright with "/dev/tty: Device not configured" rather than a
    /// permission error. If that happens, AppViewModel.installMole() catches
    /// it and retries through performElevatedInstall() instead.
    func install() async throws -> String {
        let output = try await runProcess(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", Self.installScriptCommand]
        )
        cachedBinaryPath = nil
        _ = try resolveBinaryPath() // surfaces binaryNotFound if the install didn't actually land a usable binary
        return output
    }

    /// Forgets any cached (missing) binary path and re-resolves it — call
    /// after installing Mole through a path other than `install()` itself
    /// (see AppViewModel.performElevatedInstall()), so the next lookup finds
    /// the freshly installed binary instead of continuing to report "not
    /// found."
    func refreshBinaryPathAfterExternalInstall() throws {
        cachedBinaryPath = nil
        _ = try resolveBinaryPath()
    }

    // MARK: - Status

    func status() async throws -> MoleStatus {
        let raw = try await run(arguments: ["status", "--json"])
        return try decode(MoleStatus.self, from: raw)
    }

    // MARK: - Analyze (Disk Usage)

    func analyze(path: String) async throws -> MoleAnalysis {
        let raw = try await run(arguments: ["analyze", "--json", path])
        return try decode(MoleAnalysis.self, from: raw)
    }

    // MARK: - History

    /// `mole history --json` — a log of past sessions (clean/optimize/
    /// uninstall/…) plus a separate list of individual file deletions,
    /// confirmed against a real sample from Casey's Mac. Read-only, so no
    /// dry-run/execute split like Clean or Optimize.
    func history() async throws -> MoleHistory {
        let raw = try await run(arguments: ["history", "--json"])
        return try decode(MoleHistory.self, from: raw)
    }

    // MARK: - Clean

    /// `liveOutput`, if given, is fed the same stdout chunks as they arrive
    /// — see ProcessOutputBuffer's doc comment — so a caller can show
    /// progress on a scan that can genuinely take several minutes instead of
    /// a plain spinner for the whole duration.
    func cleanDryRun(liveOutput: ProcessOutputBuffer? = nil) async throws -> String {
        try await run(arguments: ["clean", "--dry-run"], liveOutput: liveOutput)
    }

    /// Executes the real clean. Mole prompts "Proceed? [y/N]" on stdin,
    /// so we pipe "y\n" the same way the shell script did with `printf 'y\n' | mole clean`.
    func cleanExecute() async throws -> String {
        try await run(arguments: ["clean"], stdinText: "y\n")
    }

    // MARK: - Optimize

    /// `mole optimize --dry-run` — previews the memory/launch-agent/login-item
    /// cleanup Mole's "optimize" pass would perform, same shape as Clean.
    ///
    /// Confirmed live: this exits 1 even on a completely normal preview run
    /// (e.g. one step needing sudo that isn't cached, or optimize simply
    /// using its exit code as an informational flag rather than a pure
    /// success/failure signal — same spirit as uninstallPreview's EOF-exit-1
    /// case above). Nothing is modified in dry-run mode regardless, so the
    /// output mole already printed is shown either way instead of the user
    /// seeing a scary "mole exited with code 1" error banner for a preview
    /// that actually worked.
    /// `liveOutput`, if given, is fed the same stdout chunks as they arrive
    /// — see ProcessOutputBuffer's doc comment on `cleanDryRun(liveOutput:)`.
    func optimizeDryRun(liveOutput: ProcessOutputBuffer? = nil) async throws -> String {
        try await runTolerantOfNonzeroExit(arguments: ["optimize", "--dry-run"], liveOutput: liveOutput)
    }

    /// Executes the real optimize pass. Mirrors `cleanExecute()` by piping
    /// "y\n" in case optimize prompts for confirmation the same way clean
    /// does — harmless if this particular subcommand doesn't read stdin.
    func optimizeExecute() async throws -> String {
        try await run(arguments: ["optimize"], stdinText: "y\n")
    }

    // MARK: - Purge

    /// `mole purge --dry-run` — previews Mole's deeper cache/log/derived-data
    /// purge pass. Tolerant of a nonzero exit for the same reason
    /// `optimizeDryRun()` is — see its doc comment.
    func purgeDryRun() async throws -> String {
        try await runTolerantOfNonzeroExit(arguments: ["purge", "--dry-run"])
    }

    func purgeExecute() async throws -> String {
        try await run(arguments: ["purge"], stdinText: "y\n")
    }

    // Installer cleanup deliberately does NOT wrap a mole subcommand — see
    // InstallerScanner.swift. `mole installer --dry-run` turned out to be a
    // genuine interactive raw-terminal UI (arrow keys/space/enter to select
    // items, confirmed live), not a plain-text preview like clean/optimize/
    // purge. `Process`+`Pipe` gives it no real terminal to draw into, so it
    // just hangs forever — not a stdin or exit-code problem, so no amount of
    // massaging this runner's plumbing fixes it. Rather than embed a full
    // terminal emulator for one screen, MacMoleManager scans the common
    // installer drop spots itself and handles deletion natively.

    // MARK: - Uninstall

    func uninstallList() async throws -> [MoleAppEntry] {
        let raw = try await run(arguments: ["uninstall", "--list"])
        return try decode([MoleAppEntry].self, from: raw)
    }

    // Preview and removal deliberately do NOT go through `mole uninstall`
    // (nor its `--dry-run` flag, which does exist despite this file's
    // earlier comment claiming otherwise) — see AppLeftoverScanner.swift.
    // Confirmed live: mole's own uninstall preview only ever prints a
    // one-line "Matched N app(s): ... | Last: Nd ago" summary, with no flag
    // to list the individual files it would remove. Getting the AppCleaner-
    // style per-file checklist Casey asked for means finding those files
    // ourselves via FileManager instead, matched by bundle ID/app name
    // across the standard leftover locations, with deletion going straight
    // to FileManager.trashItem — same pattern as InstallerScanner.

    // MARK: - Process plumbing

    @discardableResult
    private func run(
        arguments: [String],
        stdinText: String? = nil,
        stdinFromDevNull: Bool = false,
        liveOutput: ProcessOutputBuffer? = nil
    ) async throws -> String {
        let binary = try resolveBinaryPath()
        return try await runProcess(
            executableURL: URL(fileURLWithPath: binary),
            arguments: arguments,
            stdinText: stdinText,
            stdinFromDevNull: stdinFromDevNull,
            liveOutput: liveOutput
        )
    }

    /// Like `run(arguments:)`, but a nonzero exit still returns whatever
    /// mole printed instead of throwing — for read-only preview commands
    /// where mole's exit code can't be trusted as a plain success/failure
    /// signal. See the doc comment on `optimizeDryRun()`.
    private func runTolerantOfNonzeroExit(arguments: [String], liveOutput: ProcessOutputBuffer? = nil) async throws -> String {
        do {
            return try await run(arguments: arguments, liveOutput: liveOutput)
        } catch let MoleError.processFailed(_, output) {
            return output
        }
    }

    @discardableResult
    private func runProcess(
        executableURL: URL,
        arguments: [String],
        stdinText: String? = nil,
        stdinFromDevNull: Bool = false,
        liveOutput: ProcessOutputBuffer? = nil
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            if let stdinText, let data = stdinText.data(using: .utf8) {
                let inPipe = Pipe()
                process.standardInput = inPipe
                inPipe.fileHandleForWriting.write(data)
                inPipe.fileHandleForWriting.closeFile()
            } else if stdinFromDevNull {
                process.standardInput = FileHandle.nullDevice
            }

            // Drain stdout/stderr continuously as data arrives, rather than
            // only reading once the process has already exited.
            //
            // macOS pipe buffers are ~64KB. `installer --dry-run` walks the
            // whole disk looking for leftover .pkg/.dmg files and can print
            // well past that before it's done. With nothing reading from the
            // pipe until `terminationHandler` fires, the child blocks inside
            // its own write() once the buffer fills, this process is blocked
            // waiting for the child to terminate, and the two deadlock
            // forever — exactly the "Scanning…" spinner that never
            // completed. Reading via `readabilityHandler` keeps the pipe
            // drained the whole time so the child can always finish and exit.
            let outBuffer = ProcessOutputBuffer()
            let errBuffer = ProcessOutputBuffer()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    outBuffer.append(chunk)
                    // Mirror the same chunk into the caller's own buffer, if
                    // it wants to watch progress live — see the doc comment
                    // on ProcessOutputBuffer. `liveOutput` is itself thread-
                    // safe (same NSLock pattern as outBuffer), so appending
                    // to it from this background queue is safe.
                    liveOutput?.append(chunk)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { errBuffer.append(chunk) }
            }

            process.terminationHandler = { proc in
                // Handlers stop firing once removed; readDataToEndOfFile()
                // here just mops up any last bytes that arrived between the
                // final handler callback and process exit.
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let tailOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let tailErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !tailOut.isEmpty { outBuffer.append(tailOut) }
                if !tailErr.isEmpty { errBuffer.append(tailErr) }

                // Mole always emits ANSI color/cursor codes, even when stdout
                // isn't a real terminal, so they show up as literal garbage
                // in a SwiftUI Text unless stripped here. Confirmed the
                // --json commands never contain them, so this is safe across
                // every caller.
                let out = (String(data: outBuffer.data, encoding: .utf8) ?? "").strippingANSIEscapeCodes
                let err = (String(data: errBuffer.data, encoding: .utf8) ?? "").strippingANSIEscapeCodes

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing: MoleError.processFailed(
                        exitCode: proc.terminationStatus,
                        output: err.isEmpty ? out : err
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        guard let data = raw.data(using: .utf8) else {
            throw MoleError.decodingFailed(raw)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MoleError.decodingFailed("\(error)\n---\n\(raw)")
        }
    }
}

/// Thread-safe append-only byte buffer for collecting `Pipe` output from a
/// `readabilityHandler`, which fires on a background dispatch queue rather
/// than wherever `runProcess` itself was called from.
///
/// Not `private`: callers that want to watch a long-running command's output
/// live (e.g. Clean's dry-run scan, which can take minutes) create one of
/// these themselves and pass it in as `liveOutput` — see `cleanDryRun(liveOutput:)`
/// — then poll its `text` from a Task while the call is in flight. It's
/// exactly the same append-as-chunks-arrive buffer `runProcess` already uses
/// internally, just exposed so a second copy can mirror the same chunks out
/// to a caller that needs to observe progress instead of only the final result.
final class ProcessOutputBuffer: @unchecked Sendable {
    // `nonisolated(unsafe)`, not just `nonisolated`: marking `append`/`data`
    // below `nonisolated` doesn't change the isolation of this stored
    // property itself — it still defaults to @MainActor, so mutating or
    // reading it from those now-nonisolated methods was flagged as invalid
    // ("Main actor-isolated property 'storage' can not be mutated/referenced
    // from a nonisolated context"). `(unsafe)` is the correct escape hatch
    // here specifically because `storage` isn't safe on its own (`Data`
    // mutation isn't thread-safe) — the `NSLock` below is what actually
    // makes concurrent access safe, so this just tells the compiler to
    // trust the manual synchronization instead of enforcing actor isolation.
    private nonisolated(unsafe) var storage = Data()
    private let lock = NSLock()

    // Explicit + `nonisolated` for the same reason `decodeWaitStatus` in
    // PTYRunner.swift needed it: this project defaults new declarations to
    // @MainActor isolation, but `append`/`data` are called from
    // `readabilityHandler`/`terminationHandler` closures that Process/Pipe
    // fire on an arbitrary background queue, not the main actor. Without
    // `nonisolated`, the compiler infers this whole class as MainActor and
    // flags every one of those synchronous background calls as invalid.
    nonisolated init() {}

    nonisolated func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(chunk)
    }

    nonisolated var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// `data`, decoded and ANSI-stripped — the same cleanup `runProcess`
    /// applies to its own final result, so a live-polling caller sees text
    /// that looks like the finished output, not raw escape codes.
    nonisolated var text: String {
        (String(data: data, encoding: .utf8) ?? "").strippingANSIEscapeCodes
    }
}

extension String {
    /// Strips ANSI escape sequences (SGR color/style codes, cursor moves,
    /// screen clears) — e.g. "\u{1B}[1;35m", "\u{1B}[2J", "\u{1B}[0m".
    /// `nonisolated` because this runs from `Process.terminationHandler`,
    /// which fires on an arbitrary thread, not the main actor this file
    /// otherwise defaults to. Shared with PTYRunner.swift, which needs the
    /// same cleanup on output captured from a real pty.
    nonisolated var strippingANSIEscapeCodes: String {
        guard let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-Za-z]") else { return self }
        return regex.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: "")
    }
}

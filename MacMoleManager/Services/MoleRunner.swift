//
//  MoleRunner.swift
//  MacStorageManager
//
//  Async/await wrapper around the `mole` CLI binary.
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

/// Which install path put the resolved `mole` binary on disk — determines which update path to use.
enum MoleInstallSource {
    case directDownload
    case homebrew
}

actor MoleRunner {

    static let shared = MoleRunner()

    /// Mole's own documented installer (https://mole.fit → tw93/mole).
    /// Not `private`: reused by AppViewModel.performElevatedInstall() when a plain `install()` fails.
    static let installScriptCommand =
        "curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash"

    private var cachedBinaryPath: String?

    private let candidatePaths = [
        "/usr/local/bin/mole",
        "/opt/homebrew/bin/mole",
        "/usr/local/homebrew/bin/mole",
    ]

    // MARK: - Binary discovery

    func resolveBinaryPath() throws -> String {
        if let cached = cachedBinaryPath { return cached }

        let fm = FileManager.default
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            cachedBinaryPath = path
            return path
        }

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

    /// Checks the resolved binary's real path for a Cellar/Caskroom segment, since a
    /// direct-download install could otherwise land under a similar-looking path.
    func installSource() -> MoleInstallSource {
        guard let path = try? resolveBinaryPath() else { return .directDownload }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return (resolved.contains("/Cellar/") || resolved.contains("/Caskroom/")) ? .homebrew : .directDownload
    }

    /// Apple Silicon and Intel Homebrew use separate prefixes, each with their own `brew`.
    private func resolveHomebrewPath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func version() async throws -> String {
        let output = try await run(arguments: ["--version"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `mo update`. Mole falls back to a /dev/tty password prompt when sudo isn't already
    /// cached, which fails with no controlling terminal — call `update(withAdminPassword:)` instead if this throws.
    func update() async throws -> String {
        try await run(arguments: ["update"])
    }

    /// Runs `sudo -S mole update` with mole itself as root, so its internal `sudo -n true`
    /// check passes immediately instead of hitting the tty prompt `update()` can't satisfy.
    func update(withAdminPassword password: String) async throws -> String {
        let binary = try resolveBinaryPath()
        return try await runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/sudo"),
            arguments: ["-S", "-p", "", binary, "update"],
            stdinText: password + "\n"
        )
    }

    /// `brew upgrade mole`, run unprivileged. Homebrew refuses to run as root, and sudo's
    /// restricted PATH doesn't include Homebrew's bin dir either, so this can't go through
    /// `update(withAdminPassword:)`.
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

    /// Runs install.sh via a plain Process/Pipe child — only works when it doesn't need to
    /// elevate. If install.sh decides it needs sudo, it reads/writes /dev/tty directly, which
    /// a Pipe-backed child doesn't have, and fails with "/dev/tty: Device not configured";
    /// AppViewModel.installMole() catches that and retries via performElevatedInstall().
    func install() async throws -> String {
        let output = try await runProcess(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", Self.installScriptCommand]
        )
        cachedBinaryPath = nil
        _ = try resolveBinaryPath() // surfaces binaryNotFound if the install didn't land a usable binary
        return output
    }

    /// Call after installing Mole through a path other than `install()` itself, so the next
    /// lookup finds the freshly installed binary instead of the cached "not found".
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

    func history() async throws -> MoleHistory {
        let raw = try await run(arguments: ["history", "--json"])
        return try decode(MoleHistory.self, from: raw)
    }

    // MARK: - Clean

    /// `liveOutput`, if given, receives the same stdout chunks as they arrive — see
    /// ProcessOutputBuffer — so a caller can show progress during a multi-minute scan.
    func cleanDryRun(liveOutput: ProcessOutputBuffer? = nil) async throws -> String {
        try await run(arguments: ["clean", "--dry-run"], liveOutput: liveOutput)
    }

    /// Mole prompts "Proceed? [y/N]" on stdin, hence the piped "y\n".
    func cleanExecute() async throws -> String {
        try await run(arguments: ["clean"], stdinText: "y\n")
    }

    // MARK: - Optimize

    /// `mole optimize --dry-run`. Exits 1 even on a normal preview run, so this is tolerant
    /// of a nonzero exit rather than throwing — see `runTolerantOfNonzeroExit`.
    func optimizeDryRun(liveOutput: ProcessOutputBuffer? = nil) async throws -> String {
        try await runTolerantOfNonzeroExit(arguments: ["optimize", "--dry-run"], liveOutput: liveOutput)
    }

    func optimizeExecute() async throws -> String {
        try await run(arguments: ["optimize"], stdinText: "y\n")
    }

    // MARK: - Purge

    func purgeDryRun() async throws -> String {
        try await runTolerantOfNonzeroExit(arguments: ["purge", "--dry-run"])
    }

    func purgeExecute() async throws -> String {
        try await run(arguments: ["purge"], stdinText: "y\n")
    }

    // `mole installer --dry-run` is an interactive raw-terminal UI, not a plain-text preview,
    // and hangs under Process+Pipe with no real terminal to draw into. MacMoleManager scans
    // installer drop spots itself instead — see InstallerScanner.swift.

    // MARK: - Uninstall

    func uninstallList() async throws -> [MoleAppEntry] {
        let raw = try await run(arguments: ["uninstall", "--list"])
        return try decode([MoleAppEntry].self, from: raw)
    }

    // Preview/removal deliberately skip `mole uninstall`, which only prints a one-line
    // summary with no per-file listing. See AppLeftoverScanner.swift for the FileManager-based
    // equivalent, matched by bundle ID/app name and deleted via FileManager.trashItem.

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

    /// Like `run(arguments:)`, but returns mole's output on a nonzero exit instead of
    /// throwing, for preview commands whose exit code isn't a reliable success signal.
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

            // Drain continuously via readabilityHandler rather than reading at exit — pipe
            // buffers are ~64KB, and a long-running scan can fill one and deadlock waiting
            // for a reader that only shows up in terminationHandler.
            let outBuffer = ProcessOutputBuffer()
            let errBuffer = ProcessOutputBuffer()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    outBuffer.append(chunk)
                    liveOutput?.append(chunk)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { errBuffer.append(chunk) }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let tailOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let tailErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !tailOut.isEmpty { outBuffer.append(tailOut) }
                if !tailErr.isEmpty { errBuffer.append(tailErr) }

                // Mole emits ANSI codes even when stdout isn't a real terminal.
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

/// Thread-safe append-only byte buffer for `Pipe` output collected from a `readabilityHandler`,
/// which fires on a background queue. Exposed (not `private`) so callers can poll `.text` for
/// live progress on a long-running command via `liveOutput:`.
final class ProcessOutputBuffer: @unchecked Sendable {
    // nonisolated(unsafe): this file defaults to @MainActor, but append/data run from
    // Process's background callbacks. The NSLock below provides the actual thread safety.
    private nonisolated(unsafe) var storage = Data()
    private let lock = NSLock()

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

    nonisolated var text: String {
        (String(data: data, encoding: .utf8) ?? "").strippingANSIEscapeCodes
    }
}

extension String {
    /// Strips ANSI escape sequences (SGR color/style codes, cursor moves, screen clears).
    /// Shared with PTYRunner.swift, which needs the same cleanup on real pty output.
    nonisolated var strippingANSIEscapeCodes: String {
        guard let regex = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-Za-z]") else { return self }
        return regex.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: "")
    }
}

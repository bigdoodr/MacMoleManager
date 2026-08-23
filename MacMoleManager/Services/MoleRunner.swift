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
    case processFailed(exitCode: Int32, output: String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Couldn't find the mole binary. Checked /usr/local/bin/mole and $PATH."
        case .processFailed(let code, let output):
            return "mole exited with code \(code):\n\(output)"
        case .decodingFailed(let raw):
            return "Couldn't parse mole's JSON output:\n\(raw.prefix(500))"
        }
    }
}

actor MoleRunner {

    static let shared = MoleRunner()

    /// The install script Mole itself documents (https://mole.fit → tw93/mole).
    /// Running this instead of vendoring a binary keeps the app on Mole's own
    /// release cadence — `mo update` later moves it forward the same way.
    private static let installScriptCommand =
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

    func version() async throws -> String {
        let output = try await run(arguments: ["--version"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `mo update` — updates to the latest stable release. No stdin prompt
    /// (unlike clean/uninstall), so no confirmation text needs to be piped in.
    func update() async throws -> String {
        try await run(arguments: ["update"])
    }

    // MARK: - Install

    /// Runs Mole's own installer end to end. On success, forgets any cached
    /// (missing) binary path so the next call re-discovers the freshly
    /// installed one instead of continuing to report "not found."
    func install() async throws -> String {
        let output = try await runProcess(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", Self.installScriptCommand]
        )
        cachedBinaryPath = nil
        _ = try resolveBinaryPath() // surfaces binaryNotFound if the install didn't actually land a usable binary
        return output
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

    // MARK: - Clean

    func cleanDryRun() async throws -> String {
        try await run(arguments: ["clean", "--dry-run"])
    }

    /// Executes the real clean. Mole prompts "Proceed? [y/N]" on stdin,
    /// so we pipe "y\n" the same way the shell script did with `printf 'y\n' | mole clean`.
    func cleanExecute() async throws -> String {
        try await run(arguments: ["clean"], stdinText: "y\n")
    }

    // MARK: - Uninstall

    func uninstallList() async throws -> [MoleAppEntry] {
        let raw = try await run(arguments: ["uninstall", "--list"])
        return try decode([MoleAppEntry].self, from: raw)
    }

    /// Preview pass — feeds /dev/null on stdin (mole has no --dry-run for uninstall,
    /// this mirrors the shell script's workaround) so nothing is actually removed.
    func uninstallPreview(appName: String) async throws -> String {
        try await run(arguments: ["uninstall", appName], stdinFromDevNull: true)
    }

    /// Real removal — pipes "y\n" to confirm, matching the shell script's execute step.
    func uninstallExecute(appName: String) async throws -> String {
        try await run(arguments: ["uninstall", appName], stdinText: "y\n")
    }

    // MARK: - Process plumbing

    @discardableResult
    private func run(
        arguments: [String],
        stdinText: String? = nil,
        stdinFromDevNull: Bool = false
    ) async throws -> String {
        let binary = try resolveBinaryPath()
        return try await runProcess(
            executableURL: URL(fileURLWithPath: binary),
            arguments: arguments,
            stdinText: stdinText,
            stdinFromDevNull: stdinFromDevNull
        )
    }

    @discardableResult
    private func runProcess(
        executableURL: URL,
        arguments: [String],
        stdinText: String? = nil,
        stdinFromDevNull: Bool = false
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

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""

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

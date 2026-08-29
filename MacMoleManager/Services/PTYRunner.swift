//
//  PTYRunner.swift
//  MacStorageManager
//
//  One-shot PTY-backed command runner, built on SwiftTerm's `LocalProcess`
//  (https://github.com/migueldeicaza/SwiftTerm, MIT licensed — fine to
//  depend on from this GPLv3 app, permissive-into-copyleft has no
//  conflict). Unlike MoleRunner's Process/Pipe-based `run(arguments:)`,
//  LocalProcess gives the child a REAL controlling terminal via
//  openpty/login_tty. That's what makes it possible for `sudo -A -v`
//  (askpass-driven credential validation) and any of Mole's own internal
//  sudo calls that follow it *in the same shell session* to share one
//  sudo ticket — a Pipe has no tty at all, which is the root cause behind
//  the old admin-password-sheet workaround in AppViewModel/MoleRunner
//  (see the doc comments there): Mole's own /dev/tty-based password
//  prompt has nothing to read from and aborts immediately.
//
//  This mirrors the exact pattern MoleUI (github.com/Zhili1004/MoleUI, a
//  Rust/Tauri GUI for the same `mole` CLI) uses via `portable_pty` +
//  `SUDO_ASKPASS` — see AskPassHelper.swift for the other half.
//
//  One instance handles exactly one command. Create a new PTYRunner per
//  call rather than reusing one across commands.
//

import Foundation
import Darwin
import SwiftTerm

enum PTYError: LocalizedError {
    case failedToStart
    case processFailed(exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Couldn't start the pseudo-terminal session."
        case .processFailed(let code, let output):
            return "Command exited with code \(code):\n\(output)"
        }
    }
}

final class PTYRunner: LocalProcessDelegate {

    private var outputBuffer: [UInt8] = []
    private var continuation: CheckedContinuation<String, Error>?

    // `self` as delegate is safe here: LocalProcess is created lazily, so
    // this only runs after `init` has completed.
    private lazy var process = LocalProcess(delegate: self, dispatchQueue: .main)

    /// Runs `command` inside `/bin/bash -lc` under a real pty (a login
    /// shell, so PATH/profile setup matches what a user would get in
    /// Terminal.app), resolving with combined stdout+stderr on a zero
    /// exit code.
    func run(command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            process.startProcess(executable: "/bin/bash", args: ["-lc", command])
            // startProcess's forkpty path is synchronous — by the time it
            // returns, `running` already reflects whether fork/exec actually
            // succeeded. If it silently failed, there is no delegate
            // callback to resolve this continuation, so check explicitly
            // rather than hanging forever.
            if !process.running {
                self.continuation = nil
                continuation.resume(throwing: PTYError.failedToStart)
            }
        }
    }

    // MARK: - LocalProcessDelegate

    func dataReceived(slice: ArraySlice<UInt8>) {
        outputBuffer.append(contentsOf: slice)
    }

    func getWindowSize() -> winsize {
        // No visible terminal view backs this session — a generous fixed
        // size just avoids mole's own progress output line-wrapping oddly.
        winsize(ws_row: 40, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        guard let continuation else { return }
        self.continuation = nil
        let raw = String(decoding: outputBuffer, as: UTF8.self).strippingANSIEscapeCodes
        // LocalProcess hands back the raw `waitpid` status word, not a plain
        // exit code — e.g. a real exit code of 1 arrives here as 256 (1 << 8).
        // Decode it the way the WIFEXITED/WEXITSTATUS C macros would (Swift
        // can't call those directly, they're macros, not functions).
        let realExitCode = exitCode.map(Self.decodeWaitStatus)
        if let realExitCode, realExitCode != 0 {
            continuation.resume(throwing: PTYError.processFailed(exitCode: realExitCode, output: raw))
        } else {
            continuation.resume(returning: raw)
        }
    }

    /// Mirrors the WIFEXITED/WEXITSTATUS/WIFSIGNALED C macros from
    /// <sys/wait.h> — a normal exit packs the real code into bits 8-15 with
    /// the low 7 bits zero; a signal death packs the signal number into the
    /// low 7 bits instead. Returns a negative number for the signal case so
    /// callers can still tell "exited nonzero" from "killed by a signal"
    /// apart from a glance at the sign, without needing a third case.
    ///
    /// `nonisolated` because this is called from `processTerminated(_:exitCode:)`,
    /// a `LocalProcessDelegate` requirement — that protocol isn't `@MainActor`,
    /// so its witness here is nonisolated regardless of which queue SwiftTerm
    /// actually fires it on. Without this, a project with default actor
    /// isolation set to MainActor infers this bare static func as
    /// main-actor-isolated, which a nonisolated caller can't invoke
    /// synchronously. Same reasoning as `strippingANSIEscapeCodes` in
    /// MoleRunner.swift.
    private nonisolated static func decodeWaitStatus(_ status: Int32) -> Int32 {
        let low7 = status & 0x7F
        if low7 == 0 {
            return (status >> 8) & 0xFF
        } else {
            return -low7
        }
    }
}

extension String {
    /// Wraps in single quotes for safe interpolation into a `bash -lc`
    /// command string built by string concatenation.
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

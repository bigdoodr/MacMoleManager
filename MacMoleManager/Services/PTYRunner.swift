//
//  PTYRunner.swift
//  MacStorageManager
//
//  One-shot PTY-backed command runner, built on SwiftTerm's `LocalProcess`.
//  Unlike MoleRunner's Process/Pipe-based `run(arguments:)`, LocalProcess
//  gives the child a real controlling terminal via openpty/login_tty, so
//  `sudo -A -v` and any of Mole's own internal sudo calls that follow in the
//  same shell session can share one sudo ticket — a Pipe has no tty, so
//  Mole's own /dev/tty-based password prompt has nothing to read from and
//  aborts immediately. See AskPassHelper.swift for the other half.
//
//  One instance handles exactly one command. Create a new PTYRunner per call.
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

    /// Runs `command` inside `/bin/bash -lc` under a real pty (a login shell,
    /// so PATH/profile setup matches Terminal.app), resolving with combined
    /// stdout+stderr on a zero exit code.
    func run(command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            process.startProcess(executable: "/bin/bash", args: ["-lc", command])
            // startProcess's forkpty path is synchronous, so `running` already
            // reflects a fork/exec failure here — check explicitly rather than
            // waiting on a delegate callback that will never come.
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
        // No visible terminal view backs this session — a generous fixed size
        // just avoids mole's own progress output line-wrapping oddly.
        winsize(ws_row: 40, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        guard let continuation else { return }
        self.continuation = nil
        let raw = String(decoding: outputBuffer, as: UTF8.self).strippingANSIEscapeCodes
        // LocalProcess hands back the raw waitpid status word, not a plain exit
        // code (e.g. real code 1 arrives as 256) — decode it via decodeWaitStatus.
        let realExitCode = exitCode.map(Self.decodeWaitStatus)
        if let realExitCode, realExitCode != 0 {
            continuation.resume(throwing: PTYError.processFailed(exitCode: realExitCode, output: raw))
        } else {
            continuation.resume(returning: raw)
        }
    }

    /// Mirrors the WIFEXITED/WEXITSTATUS/WIFSIGNALED C macros from <sys/wait.h>:
    /// a normal exit packs the real code into bits 8-15 with the low 7 bits
    /// zero; a signal death packs the signal number into the low 7 bits instead,
    /// returned here as a negative number.
    ///
    /// `nonisolated` because `LocalProcessDelegate` isn't @MainActor, so this
    /// witness must stay callable from whatever queue SwiftTerm fires it on.
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

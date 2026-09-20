//
//  AdminAccess.swift
//  MacMoleManager
//
//  The raw sudo failure ("Sorry, user X may not run sudo on Y") means "this
//  account has no admin rights on this Mac at all," not "wrong password" —
//  a different situation that needs different UI (see NeedsAdminAccessView.swift).
//
//  When Privileges (github.com/SAP/macOS-enterprise-privileges) is installed,
//  MacMoleManager can grant temporary admin rights directly via its bundled
//  CLI instead of just pointing the user at a separate app.
//

import AppKit
import Foundation

enum AdminAccess {

    /// Checked directly against the local directory service (no shell-out,
    /// no sudo attempt) so callers can reason about admin status without
    /// touching `sudo` at all. Fails "open" (returns true) if the group
    /// lookup itself is unavailable, so this never blocks a flow purely
    /// because the check couldn't run.
    static func isCurrentUserAdmin() -> Bool {
        guard let pw = getpwuid(getuid()) else { return true }
        guard let gr = getgrnam("admin") else { return true }
        if pw.pointee.pw_gid == gr.pointee.gr_gid { return true }
        let username = String(cString: pw.pointee.pw_name)
        guard var member = gr.pointee.gr_mem else { return false }
        while let namePtr = member.pointee {
            if String(cString: namePtr) == username { return true }
            member = member.advanced(by: 1)
        }
        return false
    }

    /// Matches `AppViewModel.friendlyAdminError`'s sudoers check so both code
    /// paths agree on whether an elevation failure means "no admin rights"
    /// rather than "wrong password" or some other transient failure.
    static func describesMissingAdminRights(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("may not run sudo")
            || message.localizedCaseInsensitiveContains("is not in the sudoers file")
    }

    // MARK: - Privileges (github.com/SAP/macOS-enterprise-privileges)

    private static let privilegesAppPath = "/Applications/Privileges.app"
    private static let privilegesCLIPath = "/Applications/Privileges.app/Contents/MacOS/PrivilegesCLI"

    static var isPrivilegesInstalled: Bool {
        FileManager.default.fileExists(atPath: privilegesAppPath)
    }

    private static var hasPrivilegesCLI: Bool {
        FileManager.default.fileExists(atPath: privilegesCLIPath)
    }

    static func openPrivilegesApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: privilegesAppPath))
    }

    enum PrivilegesError: LocalizedError {
        case notInstalled
        case cliMissing
        case cliFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Privileges isn't installed on this Mac."
            case .cliMissing:
                return "Privileges is installed, but PrivilegesCLI wasn't found inside it — try opening Privileges directly instead."
            case .cliFailed(let output):
                return "Privileges couldn't grant admin rights:\n\(output)"
            }
        }
    }

    /// Requests temporary admin rights via Privileges' own CLI, which talks
    /// to its installed launchd daemon and handles Touch ID/password
    /// authorization itself — nothing here touches `sudo`.
    static func requestTemporaryAdmin(reason: String) async throws {
        guard isPrivilegesInstalled else { throw PrivilegesError.notInstalled }
        guard hasPrivilegesCLI else { throw PrivilegesError.cliMissing }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: privilegesCLIPath)
        process.arguments = ["--add", "--reason", reason]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PrivilegesError.cliFailed(output))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

//
//  FullDiskAccess.swift
//  MacStorageManager
//
//  There's no public API to directly query Full Disk Access state. The
//  standard technique (used by AppCleaner-style tools) is to attempt a read
//  of a TCC-protected location and treat failure as "not granted."
//  ~/Library/Mail is a reliable probe on any Mac that's opened Mail once,
//  falling back to another protected path if absent.
//

import Foundation
import AppKit

enum FullDiskAccess {

    static func isGranted() -> Bool {
        let probePaths = [
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Safari",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        for path in probePaths {
            if FileManager.default.fileExists(atPath: path) {
                return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
                    || FileManager.default.isReadableFile(atPath: path)
            }
        }
        // None of the probes exist — can't tell either way; don't block the user.
        return true
    }

    /// Opens System Settings straight to the Full Disk Access pane.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

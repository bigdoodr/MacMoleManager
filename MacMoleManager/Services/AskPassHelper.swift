//
//  AskPassHelper.swift
//  MacStorageManager
//
//  Writes a one-time-use "askpass" helper script that pops a native macOS
//  password dialog via `osascript` — the same technique MoleUI
//  (github.com/Zhili1004/MoleUI, another GUI for the `mole` CLI) uses for
//  its own admin-elevation flow (`ensure_askpass` in its Rust backend).
//
//  `sudo -A` invokes whatever script `SUDO_ASKPASS` points to instead of
//  trying — and, with no controlling terminal, failing — to read a
//  password from `/dev/tty` itself. If the Mac has Touch ID configured for
//  sudo (`pam_tid.so` in /etc/pam.d/sudo or sudo_local), PAM tries that
//  first and this script's dialog is only shown as the fallback.
//

import Foundation

enum AskPassHelper {

    /// Writes a fresh helper script to a private temp location and returns
    /// its path. Each call gets its own file (rather than one shared,
    /// reused script) so nothing has to reason about concurrent elevated
    /// operations sharing state — callers are responsible for deleting the
    /// file once the command it's used for has finished.
    static func write() throws -> String {
        let script = """
        #!/bin/bash
        osascript -e 'text returned of (display dialog "MacMoleManager needs administrator access to update Mole.\n\nEnter your Mac account password below." with title "MacMoleManager" default answer "" with hidden answer buttons {"Cancel","OK"} default button 2 with icon caution)' 2>/dev/null
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macmolemanager-askpass-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }
}

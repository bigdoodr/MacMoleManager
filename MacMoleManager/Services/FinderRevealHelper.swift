//
//  FinderRevealHelper.swift
//  MacMoleManager
//
//  `NSWorkspace.activateFileViewerSelecting` sends Finder an Apple Event
//  under the hood, which triggers a system Automation/TCC prompt the first
//  time any reveal-in-Finder button is used. This wraps every such call so
//  MacMoleManager explains that prompt once, right before it appears,
//  instead of it showing up unexplained.
//

import AppKit
import Foundation

enum FinderRevealHelper {
    private static let hasPrimedKey = "FinderRevealHelper.hasPrimedAutomationPrompt"

    static func reveal(_ url: URL) {
        reveal([url])
    }

    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        primeIfNeeded {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    private static func primeIfNeeded(then action: @escaping () -> Void) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hasPrimedKey) else {
            action()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Allow MacMoleManager to Control Finder?"
        alert.informativeText = "Revealing a file works by asking Finder to select it directly, so macOS is about to show its own permission prompt for MacMoleManager to control Finder. This explanation only shows once — click Continue, then Allow on the system prompt that follows."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        defaults.set(true, forKey: hasPrimedKey)
        action()
    }
}

//
//  MacStorageManagerApp.swift
//  MacStorageManager
//
//  Native SwiftUI replacement for MacStorageCheckBeta.sh.
//  Wraps the `mole` CLI directly — no swiftDialog, no temp-file handoff
//  between processes, no runAsUser (the app already runs as the logged-in
//  user, since it's launched from Applications/Self-Service by that user
//  rather than as root via a Mosyle Custom Command).
//

import AppKit
import SwiftUI

@main
struct MacStorageManagerApp: App {
    @StateObject private var appViewModel = AppViewModel()
    @Environment(\.openWindow) private var openWindow

    init() {
        // AppKit adds a tab bar + "+" control to resizable windows automatically.
        // This app shares one AppViewModel across every window, so a second tab
        // just mirrors the first window's sidebar selection instead of being
        // independent — disable tabbing outright rather than leave a control
        // that looks like it should work but doesn't.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
                // minWidth/minHeight are the resize floor; without an ideal
                // size the window launches AT that floor, which is too tight
                // for the Uninstall tab's toolbar row (Sort picker + direction
                // toggle + Refresh) to lay out cleanly until manually widened.
                .frame(minWidth: 820, idealWidth: 1040, minHeight: 560, idealHeight: 700)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { } // single-window utility, no "New Window"

            // Custom About panel instead of the default one, so there's room
            // for an Acknowledgments section crediting Mole, MoleUI, and the
            // WKU tooling this app grew out of. `Window` (not WindowGroup) so
            // repeated menu clicks bring the same window forward instead of
            // spawning duplicates.
            CommandGroup(replacing: .appInfo) {
                Button("About MacMoleManager") {
                    openWindow(id: "about")
                }
            }

            // The default Help menu item just says "Help isn't available"
            // since there's no CFBundleHelpBookName registered — this swaps
            // it for a plain in-app help window instead of setting one up.
            CommandGroup(replacing: .help) {
                Button("MacMoleManager Help") {
                    openWindow(id: "help")
                }
            }
        }

        Window("About MacMoleManager", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("MacMoleManager Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }
}

//
//  MacStorageManagerApp.swift
//  MacStorageManager
//
//  Native SwiftUI wrapper around the `mole` CLI.
//

import AppKit
import SwiftUI

@main
struct MacStorageManagerApp: App {
    @StateObject private var appViewModel = AppViewModel()
    @Environment(\.openWindow) private var openWindow

    init() {
        // An installer/MDM script running as root can launch this app as the
        // console user while leaving HOME=/var/root in the environment; every
        // child process (mole, its installer, brew) would inherit it and fail
        // writing ~/.config. The passwd entry is the source of truth.
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let realHome = String(cString: dir)
            if ProcessInfo.processInfo.environment["HOME"] != realHome {
                setenv("HOME", realHome, 1)
            }
        }

        // Every window shares one AppViewModel, so a second tab would just mirror
        // the first window's sidebar selection instead of being independent.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
                // Without an ideal size the window launches at the resize floor,
                // too tight for the Uninstall tab's toolbar row to lay out cleanly.
                .frame(minWidth: 820, idealWidth: 1040, minHeight: 560, idealHeight: 700)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { } // single-window utility, no "New Window"

            // `Window` (not WindowGroup) so repeated menu clicks bring the same
            // window forward instead of spawning duplicates.
            CommandGroup(replacing: .appInfo) {
                Button("About MacMoleManager") {
                    openWindow(id: "about")
                }
            }

            // No CFBundleHelpBookName registered, so swap the default "Help isn't
            // available" item for a plain in-app help window.
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

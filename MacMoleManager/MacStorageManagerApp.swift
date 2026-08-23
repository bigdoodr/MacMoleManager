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

import SwiftUI

@main
struct MacStorageManagerApp: App {
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { } // single-window utility, no "New Window"
        }
    }
}

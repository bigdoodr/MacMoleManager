//
//  OnboardingView.swift
//  MacMoleManager
//
//  Explains what Mole is and what installing it will do. Shown automatically
//  the first time the app notices Mole is missing (see
//  AppViewModel.showMoleOnboarding), and reopenable from the banner's
//  "What Is This?" button.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let's Set Up Mole")
                        .font(.title2).bold()
                    Text("Mole isn't installed on this Mac yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Text("MacMoleManager is a native interface for Mole, an open-source command-line tool that does the actual disk cleaning, analysis, and uninstalling. Every feature here needs it, so let's get it installed first.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                OnboardingStep(number: 1, text: "MacMoleManager runs Mole's own official installer — the same one at mole.fit.")
                OnboardingStep(number: 2, text: "If this Mac has never had a /usr/local/bin (no prior Homebrew or Xcode Command Line Tools), macOS may ask for administrator access partway through.")
                OnboardingStep(number: 3, text: "Once Mole is installed, MacMoleManager will separately ask for Full Disk Access, so scans can see the whole disk.")
            }

            if vm.isInstallingMole {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing Mole…")
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = vm.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Not Now") { vm.dismissMoleOnboarding() }
                    .disabled(vm.isInstallingMole)
                Spacer()
                Button("Set Up Mole") {
                    Task {
                        await vm.installMole()
                        if vm.moleInstalled {
                            vm.dismissMoleOnboarding()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isInstallingMole)
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled(vm.isInstallingMole)
    }
}

private struct OnboardingStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption).bold()
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

//
//  NeedsAdminAccessView.swift
//  MacMoleManager
//
//  Replaces the raw sudo error whenever AppViewModel detects it means "this
//  account has no admin rights at all" (see AdminAccess.describesMissingAdminRights)
//  rather than some other failure — no amount of retrying the password fixes
//  that. When Privileges is installed, its CLI is offered as the fix and
//  MacMoleManager retries the original action automatically once it succeeds.
//  Otherwise the fallback points at Users & Groups.
//

import AppKit
import SwiftUI

struct NeedsAdminAccessView: View {
    @EnvironmentObject var vm: AppViewModel
    let action: AppViewModel.PendingElevatedAction

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Administrator Access Needed", systemImage: "lock.shield")
                .font(.title2).bold()

            Text("Your account doesn't have administrator rights on this Mac, which \(action.verb) needs. Re-entering a password won't fix this — the account itself needs admin rights, from an administrator or a tool like Privileges.")
                .fixedSize(horizontal: false, vertical: true)

            if AdminAccess.isPrivilegesInstalled {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Privileges is installed on this Mac. Request temporary admin rights through it, and MacMoleManager will retry automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let error = vm.privilegesRequestError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Button {
                            Task { await vm.requestAdminViaPrivileges() }
                        } label: {
                            if vm.isRequestingPrivilegesAccess {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Request Admin Access via Privileges")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.isRequestingPrivilegesAccess)

                        Button("Open Privileges Instead") {
                            AdminAccess.openPrivilegesApp()
                        }
                        .disabled(vm.isRequestingPrivilegesAccess)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ask a Mac administrator to grant your account admin rights, or to \(action.verb) for you. If this is your own personal Mac, check your account type in Users & Groups.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Users & Groups") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.users") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { vm.dismissPendingElevatedAction() }
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

extension AppViewModel.PendingElevatedAction {
    var verb: String {
        switch self {
        case .install: return "installing Mole"
        case .update: return "updating Mole"
        }
    }
}

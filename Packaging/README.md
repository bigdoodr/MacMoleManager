# Packaging MacMoleManager as a PKG

Switching from a bare `.app` download to a signed `.pkg` gives a `postinstall`
hook, so more of the setup can land before first launch instead of happening
entirely inside the app.

**What a postinstall script can and can't do:**

- It runs as **root**, once, during install — enough privilege to pre-stage
  Mole itself, so the in-app "Install Mole" flow isn't needed for most users.
- It **cannot** grant Full Disk Access or Automation/Apple-Events control of
  Finder to the app. Those are TCC grants, and the only way to hand them out
  without a user click is a **PPPC configuration profile pushed by an MDM** —
  a local script has no API for it. See `PPPC-template.mobileconfig` below.
- It also can't hand out admin rights — that's what Privileges is for (see
  `AdminAccess.swift` and `NeedsAdminAccessView.swift` in the app itself).

So the PKG's job is: land the app, land Mole, and get the two TCC prompts
opened to the right place for whoever isn't covered by a pushed profile yet.
The in-app onboarding/priming flows (`OnboardingView`, `FinderRevealHelper`)
still handle that case.

## Layout

```
Packaging/
  build-pkg.sh                  — run this locally (needs Xcode + a Developer ID Installer cert)
  scripts/postinstall           — runs as root during `installer`/Self Service
  PPPC-template.mobileconfig    — starter PPPC profile for an MDM, grants FDA + Finder Automation
```

## Building

Two ways to run this, both ending at `./Packaging/build-pkg.sh`:

**Using Xcode's Organizer (recommended)** — archive and notarize through
Xcode's own "Direct Distribution" flow: Product ▸ Archive, then Distribute
App ▸ Direct Distribution, and export to a folder. That signs, notarizes,
and staples the *app* using whatever Developer ID identity and notarization
credentials Xcode already has on file. Then point the script at the export:

```sh
PREBUILT_APP_PATH=/path/to/exported/MacMoleManager.app INSTALLER_SIGNING_IDENTITY="Developer ID Installer: Your Name (TEAMID1234)" NOTARY_PROFILE="your-notarytool-profile" ./Packaging/build-pkg.sh
```

**Letting the script do everything** — leave `PREBUILT_APP_PATH` unset and it
runs `xcodebuild archive` / `-exportArchive` itself with method
`developer-id`, notarizing/stapling the app automatically as long as Xcode
has notarization credentials configured (Xcode ▸ Settings ▸ Accounts, or a
`xcrun notarytool store-credentials` profile).

Either way, find your installer identity with `security find-identity -v -p
basic` — it's a separate certificate from the "Developer ID Application" one
used to sign the app itself.

**The `.pkg` needs its own notarization**, separate from the app inside it.
Set `NOTARY_PROFILE` to a `notarytool` keychain profile (one-time setup:
`xcrun notarytool store-credentials "<name>" --apple-id you@example.com
--team-id TEAMID1234 --password <app-specific-password>`) and the script
submits and staples it for you. Skip `INSTALLER_SIGNING_IDENTITY` and/or
`NOTARY_PROFILE` for local testing — an unsigned/un-notarized `.pkg` still
installs on your own Mac (right-click → Open, or `sudo installer -pkg ...
-target /`), it just won't pass Gatekeeper for anyone else until both are set.

## Deploying the PPPC profile (managed fleets only)

`PPPC-template.mobileconfig` grants `rocks.scruggsfam.MacMoleManager`:

- **SystemPolicyAllFiles** (Full Disk Access) — `Allow`
- **AppleEvents** targeting `com.apple.finder` — `Allow`

Push it the same way as any other MDM custom profile. Once it's on a Mac,
both `FullDiskAccess.swift`'s in-app prompt and `FinderRevealHelper`'s
priming dialog become no-ops there, since they only fire when the underlying
permission isn't already granted. **Do not deploy this profile to
personal/unmanaged Macs** — it assumes an MDM relationship; an individual
user installing this app should just click through the two in-app prompts
once instead.

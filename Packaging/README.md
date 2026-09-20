# Packaging MacMoleManager as a PKG

Casey's own note-to-self (from the coworker-feedback session): switching
from a bare `.app` download to a signed `.pkg` gives us a `postinstall`
hook, which is what makes items 1–3 of that feedback actually land for
people who install this way — without it, everything still has to happen
inside the app on first launch.

**What a postinstall script can and can't do**, since this tripped me up
while planning it:

- It runs as **root**, once, during install — plenty of privilege to drop
  files on disk. So it's the right place to pre-stage Mole itself: no
  reason to make anyone sit through the in-app "Install Mole" flow if the
  installer can just put `mole` in place for them.
- It **cannot** grant Full Disk Access or Automation/Apple-Events control
  of Finder to the app. Those are TCC grants, and the only way to hand
  them out without a user click is a **PPPC configuration profile pushed
  by an MDM** (Mosyle, in WKU's case) — a local script, even running as
  root, has no API for it. See `PPPC-template.mobileconfig` below.
- It also can't hand out admin rights — that's what Privileges is for
  (see `AdminAccess.swift` and `NeedsAdminAccessView.swift` in the app
  itself).

So the PKG's job is: land the app, land Mole, and get the two TCC prompts
opened to the right place for whoever isn't covered by a pushed profile
yet. The in-app onboarding/priming flows (`OnboardingView`,
`FinderRevealHelper`) still do the explaining for that case — the PKG
just removes as much of the friction as a plain script legally can.

## Layout

```
Packaging/
  build-pkg.sh                  — run this locally (needs Xcode + a Developer ID Installer cert)
  scripts/postinstall           — runs as root during `installer`/Self Service
  PPPC-template.mobileconfig    — starter PPPC profile for Mosyle, grants FDA + Finder Automation
```

## Building

Two ways to run this, both ending at `./Packaging/build-pkg.sh`:

**Using Xcode's Organizer (recommended)** — if you already archive and
notarize through Xcode's own "Direct Distribution" flow, keep doing that:
Product ▸ Archive, then Distribute App ▸ Direct Distribution, and export
the result to a folder. That single flow signs, notarizes, and staples
the *app* using whatever Developer ID identity and notarization
credentials Xcode already has on file — no extra setup. Then just point
the script at what Xcode exported:

```sh
PREBUILT_APP_PATH=/path/to/exported/MacMoleManager.app INSTALLER_SIGNING_IDENTITY="Developer ID Installer: Casey Scruggs (TEAMID1234)" NOTARY_PROFILE="your-notarytool-profile" ./Packaging/build-pkg.sh
```

**Letting the script do everything** — leave `PREBUILT_APP_PATH` unset and
it runs `xcodebuild archive` / `-exportArchive` itself with method
`developer-id`, which also notarizes/staples the app automatically as
long as Xcode has notarization credentials configured (Xcode ▸ Settings ▸
Accounts, or a `xcrun notarytool store-credentials` profile).

Either way, find your installer identity with `security find-identity -v
-p basic` — it's a separate certificate from the "Developer ID
Application" one used to sign the app itself.

**The `.pkg` needs its own notarization**, separate from the app inside
it — Apple notarizes packages independently. Set `NOTARY_PROFILE` to a
`notarytool` keychain profile (one-time setup:
`xcrun notarytool store-credentials "<name>" --apple-id you@example.com
--team-id TEAMID1234 --password <app-specific-password>`) and the script
submits and staples it for you. Skip `INSTALLER_SIGNING_IDENTITY` and/or
`NOTARY_PROFILE` entirely for local testing — an unsigned/un-notarized
`.pkg` still installs fine on your own Mac (right-click → Open, or `sudo
installer -pkg ... -target /`), it just won't pass Gatekeeper for anyone
else until both are set.

## Deploying the PPPC profile (managed fleets only)

`PPPC-template.mobileconfig` grants `rocks.scruggsfam.MacMoleManager`:

- **SystemPolicyAllFiles** (Full Disk Access) — `Allow`
- **AppleEvents** targeting `com.apple.finder` — `Allow`

Push it the same way as any other Mosyle custom profile. Once it's on a
Mac, both `FullDiskAccess.swift`'s in-app prompt and `FinderRevealHelper`'s
priming dialog become no-ops for that Mac — they only ever fire when the
underlying permission isn't already granted, which a pushed profile
guarantees. **Do not deploy this profile as-is to personal/unmanaged
Macs** — it assumes an MDM relationship and isn't something an individual
GitHub user installing this app should be pushing to their own machine
(they'll just click through the two in-app prompts once instead, which is
the whole reason those prompts exist).

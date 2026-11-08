# Plex Reborn

Plex Reborn is an add-on for the Plex 8.45 iPhone app that makes it work natively on iPhone Duo. It keeps the older Plex interface and adds full-screen video on both screens, correct status bar handling, and a split layout when the Duo is half folded like a laptop.

Plex Reborn does not include the Plex app. You download Plex 8.45 with your own Apple ID, decrypt it on your own Mac, and the patch script adds Plex Reborn to it.

## What works

Tested on iPhone Duo (iOS 27.2) and the iPhone Duo simulator.

| Feature | Folded | Unfolded | Half open, book | Half open, desk |
|---|---|---|---|---|
| App launches, signs in, finds servers | Works | Works | Works | Works |
| Video fills the screen | Works | Works | Works | Top half, by design |
| One tap shows the player controls | Works | Works | Works | Works |
| Status bar hides with the controls | Works | Works | Works | Works |
| Controls on the lower half | n/a | n/a | n/a | Works |
| Tabs in the Duo's vertical bar | Works | Works in landscape | n/a | n/a |
| Live TV controls fit | Works | Works | not tested | not tested |
| Mini player and sheets use the full width | Works | Works in landscape | not tested | not tested |
| Installs beside App Store Plex | Works | | | |

## Known problems

- In desk posture the Home screen's poster rows run across the crease.
- The email sign-in form is shifted left, and the launch logo is oversized.

## How it works

| Part | File | What it does |
|---|---|---|
| Scene support | `src/PlexDuoShim.m` | Scene delegate that hosts Plex's old app-delegate windows; required for apps built against the iOS 27 SDK |
| Screen handling | `src/PlexDuoScreens.m` | Hides the Duo's second panel from Plex so it does not treat it as an external TV |
| Player | `src/PlexDuoVideo.m` | Full-screen video, status bar and home indicator hiding, tap fix, desk-posture split |
| Tab bar | `src/PlexDuoTabBar.m` | Tabs as a rail in the Duo's vertical bar; same-size tab icons |
| Mini player | `src/PlexDuoMiniPlayer.m` | Uses the full width and centers its row when the vertical bar shows |
| Sheets | `src/PlexDuoSheets.m` | Plex's own sheets reach the screen edge beside the vertical bar |
| Debugging | `src/PlexViewDump.m` | Writes the view tree on request; left out of release builds |
| Simulator only | `src/PlexSim*.m`, `src/PlexSim*.c` | Lets the patched app run in the Duo simulator; compile to nothing on devices |

## Install

You need a Mac with Apple silicon, an Apple developer account (a free Apple ID works but installs last 7 days), Xcode 27.1 or later, [uv](https://docs.astral.sh/uv/), [ipatool](https://github.com/majd/ipatool) and [UnfairPlay](https://github.com/DrWhax/unfairplay).

1. Download Plex 8.45 (external version ID 871812101):
   `ipatool download -b com.plexapp.plex --external-version-id 871812101 --purchase -o Plex-8.45.ipa`
2. Decrypt it with UnfairPlay, after its one-time setup (see its README):
   `unfairplay decrypt --input Plex-8.45.ipa --output Plex-8.45-decrypted.ipa --strip-account-data`
3. Patch it with the release's `PlexDuoShim.dylib`:
   `./patch-ipa.sh Plex-8.45-decrypted.ipa PlexDuoShim.dylib PlexReborn.ipa --bundle-id com.yourname.plexreborn --team-id YOURTEAMID`
   `--team-id` must be the team that signs the app, or Plex cannot save your sign-in.
4. Install `PlexReborn.ipa` with Sideloadly using the same bundle ID and Apple ID.

## Development

Copy `config.example.sh` to `config.local.sh` and fill it in first. Put the decrypted IPA at `ipa/Plex-8.45-decrypted.ipa`.

| Script | What it does |
|---|---|
| `scripts/make-device-app.sh` | Builds the add-on and patches the IPA into `work/device` |
| `scripts/make-signing-profile.sh` | Once per bundle ID: has Xcode create a signing profile |
| `scripts/build-device.sh` | Rebuilds the add-on into the device app, signs and installs it on the phone |
| `scripts/make-simulator-app.sh` | Converts the device app for the simulator, then runs `build-sim.sh` |
| `scripts/build-sim.sh` | Rebuilds the add-on for the simulator, installs and launches it |
| `scripts/view-dump.sh` | Saves the running simulator app's screens, windows and views to `logs/` |
| `scripts/package-release.sh` | Builds `dist/PlexReborn-<version>.zip`; `--publish` also creates a draft GitHub release |
| `scripts/deploy.sh` | Signs any unpacked app with the Xcode profile and installs it |

### Releases

1. Update `VERSION` and add a section for it at the top of `CHANGELOG.md`.
2. `scripts/package-release.sh` and test the zip's dylib with `patch-ipa.sh` on a clean decrypted IPA.
3. `scripts/package-release.sh --publish` creates a draft release tagged `v<version>` with the changelog section as notes. Review and publish it on GitHub.

## Legal

Plex Reborn is an unofficial project, not affiliated with or endorsed by Plex Inc. It contains no Plex code or assets. You need your own copy of the Plex app, downloaded with your own Apple ID.

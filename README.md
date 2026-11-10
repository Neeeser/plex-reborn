# Plex-Reborn
![GitHub Release](https://img.shields.io/github/v/release/Neeeser/plex-reborn)

iOS tweak that keeps the classic [Plex](https://www.plex.tv/) 8.45 app alive on current iPhones, with Liquid Glass, streaming fixes, a cleaner Home, your own tabs and full iPhone Duo support.

> [!NOTE]
> Plex-Reborn is unofficial and not affiliated with Plex Inc. Releases include a patched copy of Plex 8.45, an app Plex distributed for free. If Plex asks for it to be taken down, releases will switch to the add-on and patch script only.

## Install

Download `PlexReborn-<version>.ipa` from the [latest release](https://github.com/Neeeser/plex-reborn/releases/latest) and install it with [Sideloadly](#sideloadly), AltStore or SideStore.

## Features

Settings are under Settings > Plex Reborn.

- Plex 8.45's classic interface with iOS 26 Liquid Glass

### Playback Fixes

- No more pauses and reloads over Plex's relay
- Seeking in transcoded streams lands where you aim
- A stream that cuts off early resumes instead of ending the episode

### New Features

- **Hide Plex's online content**: Movies & Shows, Rentals, Discover and Plex's Live TV channels, each on its own switch
- **Your own tabs**: up to 5, in the tab bar or the Duo's vertical bar
- **Library menu**: Recommended, Library and Categories in one button; each library reopens on the tab you last used
- **Floating mini player**: a glass capsule above the tab bar
- **Glass player controls**: glass in place of Plex's gray bars

### iPhone Duo Specific Features

- Full-screen video folded and unfolded, with the controls clear of the camera
- Half open, video plays on top with the controls below over its reflection
- Tabs and top bar buttons in the vertical bar
- A clear title bar that hides while scrolling
- Posters, the Live TV guide and Plex's sheets reach the screen edge
- The mini player becomes a glass card beside the vertical bar
- The second panel is no longer mistaken for an external TV
- Scroll bars are hidden, since they landed in odd places beside the vertical bar

## Known Issues

- Staying signed in is tested with one Apple ID; open an issue if Plex asks you to sign in on every launch
- Search can still show Plex's online titles when they're hidden
- With your own tabs, the tab bar doesn't always follow screens opened from the side menu
- In desk posture, Home's poster rows cross the crease
- The email sign-in form sits off-center, and the launch logo is oversized

## Sideloadly

Recommended configuration:

- **Use automatic bundle ID**: unchecked. Enter your own bundle ID, the same one every time
- **Signing Mode**: Apple ID Sideload
- **Inject dylibs/frameworks**: unchecked. The release IPA already contains Plex-Reborn

If iOS says the developer is untrusted, open **Settings > General > VPN & Device Management** and trust your Apple ID.

## Patching your own IPA

To build the app from your own copy of Plex instead of the release IPA, you need a Mac with Apple silicon, Xcode 27.1 or later, [uv](https://docs.astral.sh/uv/), [ipatool](https://github.com/majd/ipatool) and [UnfairPlay](https://github.com/DrWhax/unfairplay).

1. Download Plex 8.45 (external version ID 871812101):
   `ipatool download -b com.plexapp.plex --external-version-id 871812101 --purchase -o Plex-8.45.ipa`
2. Decrypt it with UnfairPlay, after its one-time setup (see its README):
   `unfairplay decrypt --input Plex-8.45.ipa --output Plex-8.45-decrypted.ipa --strip-account-data`
3. Patch it with the release's `PlexDuoShim-<version>.dylib`:
   `./scripts/patch-ipa.sh Plex-8.45-decrypted.ipa PlexDuoShim-<version>.dylib PlexReborn.ipa --release`
4. Install `PlexReborn.ipa` as described under [Install](#install).

`patch-ipa.sh` strips the App Store files, stamps the app for the iOS 27 SDK and adds the add-on. For your own signing setup, pass `--bundle-id` and `--team-id` instead of `--release`.

## Build

**Requirements:** a Mac with Apple silicon, Xcode 27.1 or later, and the iPhone Duo simulator runtime for simulator testing.

Copy `config.example.sh` to `config.local.sh` and fill it in, and put the decrypted IPA at `ipa/Plex-8.45-decrypted.ipa`.

| Script | What it does |
|---|---|
| `scripts/make-device-app.sh` | Builds the add-on and patches the IPA into `work/device` |
| `scripts/make-signing-profile.sh` | Once per bundle ID: has Xcode create a signing profile |
| `scripts/build-device.sh` | Rebuilds the add-on into the device app, signs it and installs it on your phone |
| `scripts/make-simulator-app.sh` | Converts the device app and its shaders for the simulator, then runs `build-sim.sh` |
| `scripts/shaders-for-simulator.py` | Rebuilds an app's Metal shaders for the simulator, which refuses shaders built for iPhones. Needs Apple's Metal toolchain (`xcodebuild -downloadComponent MetalToolchain`) |
| `scripts/build-sim.sh` | Rebuilds the add-on for the simulator, installs and launches it |
| `scripts/view-dump.sh` | Saves the running simulator app's screens, windows and views to `logs/` |
| `scripts/engine.sh` | Sends a playback command (seek, skip, pause, resume, a fake early end, status) to the simulator app's current video |
| `scripts/seek-test.sh` | Seeks the simulator app's video by each given offset and prints where playback actually resumed |
| `scripts/package-release.sh` | Builds the release IPA and add-on into `dist/`; `--publish "<summary>"` creates a draft GitHub release |
| `scripts/deploy.sh` | Signs any unpacked app with the Xcode profile and installs it |

The add-on's source is in `src/`:

| Part | File | What it does |
|---|---|---|
| Scene support | `src/PlexDuoShim.m` | Scene delegate that hosts Plex's app-delegate windows; required for apps built against the iOS 27 SDK |
| Screen handling | `src/PlexDuoScreens.m` | Hides the Duo's second panel from Plex so it does not treat it as an external TV |
| Player | `src/PlexDuoVideo.m` | Full-screen video, status bar and home indicator hiding, tap fix, desk-posture split and reflection |
| Glass controls | `src/PlexGlassPlayer.m` | Glass behind the player's top buttons and bottom controls in place of Plex's gray bars; removes the empty band Plex leaves under the bottom controls |
| Tab bar | `src/PlexDuoTabBar.m` | Plex's tabs in the system tab bar or the Duo's vertical bar; your own tabs; library tabs as a menu; remembered library tab |
| Top bar buttons | `src/PlexDuoBarButtons.m` | Moves Plex's side menu, cast, search and more buttons into the vertical bar |
| Title bar | `src/PlexDuoTitleBar.m` | Clear title bar that hides while scrolling; no title on each tab's first screen |
| Posters under the bar | `src/PlexDuoContentUnderBar.m` | Poster rows scroll under the vertical bar; scroll bars hidden beside it |
| Live TV guide | `src/PlexDuoLiveTV.m` | The guide runs under the vertical bar to the screen edge |
| Mini player | `src/PlexDuoMiniPlayer.m` | Floating glass capsule above the tab bar or card beside the vertical bar, full-width bar, or Plex's bar |
| Online content | `src/PlexHideOnlineContent.m` | Hides Plex's online sources from the side menu and Home |
| Local artwork | `src/PlexLocalImages.m` | Loads artwork from local-network addresses (such as an IPTV tool's channel logos) directly, which Plex Media Server will not resize |
| Stream keep-alive | `src/PlexStreamKeepAlive.m` | Retries a failed transcode keep-alive check on a fresh connection before Plex restarts the stream |
| Transcoded seeking | `src/PlexTranscodeSeek.m` | Seeks in a transcoded stream by restarting it at the target, and restarts a stream that ends early instead of finishing the episode |
| Keychain | `src/PlexKeychainPrefix.m` | Uses the signing team's keychain group, so release IPAs keep their sign-in |
| Settings | `src/PlexRebornSettings.m` | The Plex Reborn page in Plex's Settings |
| Sheets | `src/PlexDuoSheets.m` | Plex's own sheets reach the screen edge beside the vertical bar |
| Debugging | `src/PlexViewDump.m` | Writes the view tree on request; left out of release builds |
| Simulator only | `src/PlexSim*.m`, `src/PlexSim*.c` | Lets the patched app run in the Duo simulator; compile to nothing on devices |

## Releases

1. Update `VERSION` and add a `## [v<version>] - <date>` section at the top of `CHANGELOG.md`.
2. Run `scripts/package-release.sh` and test the IPA on a device.
3. Run `scripts/package-release.sh --publish "<summary>"`. It creates a draft release tagged `v8.45_<version>` and titled `v<version> - <summary>`, with the changelog section as its notes and the IPA and add-on attached. Review the draft and publish it on GitHub.

## License

Plex-Reborn's own code is licensed under the [GNU General Public License v3.0](LICENSE).

## Legal

Plex-Reborn is an unofficial project, not affiliated with or endorsed by Plex Inc. The add-on contains no Plex code or assets. Release IPAs contain Plex 8.45 as distributed for free by Plex, patched with the add-on.

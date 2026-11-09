# Plex-Reborn
![GitHub Release](https://img.shields.io/github/v/release/Neeeser/plex-reborn)

iOS tweak for the [Plex](https://www.plex.tv/) app that keeps the classic Plex 8.45 interface alive on current iPhones. It brings Liquid Glass bars, fixes for streaming bugs, a cleaner Home without Plex's online content, your own choice of tabs, and full support for iPhone Duo.

> [!NOTE]
> Plex-Reborn is unofficial and not affiliated with Plex Inc. Releases include a patched copy of Plex 8.45, an app Plex distributed for free. If Plex asks for it to be taken down, releases will switch to the add-on and patch script only.

## Install

Download `PlexReborn-<version>.ipa` from the [latest release](https://github.com/Neeeser/plex-reborn/releases/latest) and install it with [Sideloadly](#sideloadly), AltStore or SideStore.

## Features

### General

- Plex 8.45's classic interface with iOS 26 Liquid Glass bars, buttons and tab bar
- Scroll bars are hidden throughout the app

### Playback Fixes

- Streams over Plex's relay no longer pause and reload every few minutes when a keep-alive check drops
- Seeking in a converted (transcoded) stream lands where you aim instead of up to two minutes off
- A converted stream that cuts off early resumes where it stopped instead of ending the episode

### New Features

- **Hide Plex's online content**: Hide Movies & Shows, Rentals, Discover and Plex's free Live TV channels, each on its own switch or all at once, so you only see your own libraries, the ones shared with you, your Watchlist and your server's Live TV. Hidden content leaves the side menu, the More page, Home and the Live TV guide (Settings > Plex Reborn > Plex Online Content)
- **Your own tabs**: Pick up to 5 tabs from Home's tabs and the side menu, such as Home, TV Shows, Movies and Live TV. They show in the tab bar at the bottom, or in the vertical bar on iPhone Duo (Settings > Plex Reborn > Tabs)
- **Library tabs menu**: A library's Recommended, Library and Categories become one button with a menu instead of a second tab bar (Settings > Plex Reborn > Tabs > Library tabs)
- **Remembered library view**: Each library opens on the tab you last picked, such as Library instead of Recommended
- **Floating mini player**: The mini player is a glass capsule floating above the tab bar instead of Plex's flat bar, and pages scroll clear of both (Settings > Plex Reborn > Interface > Mini Player)
- **Glass player controls**: The player's buttons sit on glass over the video instead of Plex's gray bars, with the bottom controls in one panel sized to the controls. Every control stays where it was (Settings > Plex Reborn > Player > Glass controls)

### iPhone Duo Specific Features

- Video fills the screen on the folded and unfolded screens, with the status bar and home indicator hidden during playback and the controls clear of the camera
- Half open like a laptop, video plays on the top half with the controls on the bottom half, which shows the video reflected behind them (Settings > Plex Reborn > Player)
- Plex's tabs, top bar buttons and library tabs move into the Duo's vertical bar
- The title bar is clear, hides while scrolling, and the first screen of each tab starts at the top of the screen without a title
- Poster rows and the Live TV guide run under the vertical bar to the screen edge (Settings > Plex Reborn > Interface)
- The floating mini player becomes a glass card beside the vertical bar's tabs (Settings > Plex Reborn > Interface > Mini Player)
- Plex's own sheets, such as the server picker, reach the screen edge
- The Duo's second panel is no longer mistaken for an external TV

## Known Issues

- Staying signed in has only been tested with one Apple ID so far. If Plex asks you to sign in again after every launch, open an issue
- Hiding Plex's online content covers the side menu, the More page, Home and the Live TV guide; search results can still include Plex's online titles
- With your own tabs, the tab bar's selection does not always follow screens opened from the side menu
- In desk posture, Home's poster rows run across the crease
- The email sign-in form is shifted left, and the launch logo is oversized

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

`patch-ipa.sh` removes the App Store purchase files and app extensions, sets the name, stamps the app for the iOS 27 SDK (which gives it Liquid Glass and the iPhone Duo's layouts), adds the scene setup iOS 27 requires, and adds the add-on. Pass `--bundle-id` and `--team-id` instead of `--release` to build for your own signing setup.

## Build

**Requirements:** a Mac with Apple silicon, Xcode 27.1 or later, and the iPhone Duo simulator runtime for simulator testing.

Copy `config.example.sh` to `config.local.sh` and fill it in, and put the decrypted IPA at `ipa/Plex-8.45-decrypted.ipa`.

| Script | What it does |
|---|---|
| `scripts/make-device-app.sh` | Builds the add-on and patches the IPA into `work/device` |
| `scripts/make-signing-profile.sh` | Once per bundle ID: has Xcode create a signing profile |
| `scripts/build-device.sh` | Rebuilds the add-on into the device app, signs it and installs it on your phone |
| `scripts/make-simulator-app.sh` | Converts the device app for the simulator, then runs `build-sim.sh` |
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
| Posters under the bar | `src/PlexDuoContentUnderBar.m` | Poster rows scroll under the vertical bar; scroll bars hidden |
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

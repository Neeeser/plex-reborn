# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [v0.1.0] - 2026-11-08

### Features

- Run **Plex 8.45 on current iPhones** with iOS 26 Liquid Glass bars, by stamping the app for the iOS 27 SDK and adding the scene setup iOS 27 requires
- Add **Hide Plex's online content**, which removes Movies & Shows, Rentals and Discover from the side menu and Home while keeping your libraries, Watchlist and Live TV
  - Off by default, under Settings → Plex Reborn → Content; turning it on or off takes effect right away
- Add **your own tabs**: pick up to 5 tabs from Home's tabs and the side menu
  - They show in the tab bar at the bottom, or in the vertical bar on iPhone Duo (Settings → Plex Reborn → Choose my own tabs)
- Show a library's **Recommended, Library and Categories** as one menu button instead of a second tab bar, and open each library on the tab you last picked
- Ship a **ready-to-sign IPA** with each release, which adopts the signing Apple ID's keychain group so Plex can keep your sign-in
- Hide **scroll bars** throughout the app
- Add a **Plex Reborn page** to Plex's Settings, there when Settings opens

### iPhone Duo

- Fill the screen with **video** on the folded and unfolded screens, and hide the Duo's vertical status bar and the home indicator during playback
- Run the player's progress bar and top bar to the screen edge where the camera allows, and keep the bottom row of controls clear of it
- Play video on the top half in **desk posture** (half open, crease across), with the controls on the bottom half over a reflection of the video
- Move Plex's **tabs**, its **top bar buttons** (side menu, cast, search, more) and a library's tabs into the Duo's vertical bar; detail pages get a back button there
- Make the **title bar** clear and hide it while scrolling, and start the first screen of each tab at the top of the screen without a title
- Run **poster rows** and the **Live TV guide** under the vertical bar to the screen edge
- Turn the **mini player** into a floating glass card beside the vertical bar's tabs, or a full-width bar
- Let Plex's own **sheets**, such as the server picker, reach the screen edge
- Stop Plex treating the Duo's **second panel** as an external TV, which fixes taps and the status bar unfolded

### Fixes

- Fix the **More page's Back button** spilling out of its circle in the vertical bar; it is now a plain back chevron
- Keep the **floating mini player** when Plex replaces its view after a relaunch, instead of falling back to Plex's flat bar
- Fix **title bar flicker** while scrolling an episode's page, and Plex's gray title bar flashing while a page slides in
- Make **one tap** show the player controls on the first try
- Stop **Live TV controls** overlapping on the folded screen

[v0.1.0]: https://github.com/Neeeser/plex-reborn/releases/tag/v8.45_0.1.0

# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [v1.0.0] - 2026-11-08

### Features

- Run **Plex 8.45 on current iPhones** with iOS 26 Liquid Glass bars, by stamping the app for the iOS 27 SDK and adding the scene setup iOS 27 requires
- Add **Plex Online Content** settings to hide Movies & Shows, Rentals, Discover and Plex's free Live TV channels, each on its own switch or all at once, so you see only your libraries, the ones shared with you, your Watchlist and your server's Live TV
  - Hidden content leaves the side menu, the More page and Home, and Plex's channels leave the Live TV guide; changes take effect right away
  - Off by default, under Settings → Plex Reborn → Plex Online Content
- Add **your own tabs**: pick up to 5 tabs from Home's tabs and the side menu
  - They show in the tab bar at the bottom, or in the vertical bar on iPhone Duo (Settings → Plex Reborn → Tabs)
- Show a library's **Recommended, Library and Categories** as one menu button instead of a second tab bar, and open each library on the tab you last picked
- Ship a **ready-to-sign IPA** with each release, which adopts the signing Apple ID's keychain group so Plex can keep your sign-in
- Add a **floating mini player**: a glass capsule above the tab bar in place of Plex's flat bar, on by default, under Settings → Plex Reborn → Interface → Mini Player
- Add **glass player controls**: the top buttons sit on glass circles and capsules and the bottom controls on one glass panel just above the home indicator, with a progress bar with round ends, in place of Plex's gray bars; on by default, under Settings → Plex Reborn → Player
- Add a **Plex Reborn page** to Plex's Settings, there when Settings opens, with pages for Tabs, Plex Online Content, Interface and Player

### iPhone Duo

- Hide **scroll bars**, which landed in odd places beside the vertical bar
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
- Show **channel logos and show art** from Live TV & DVR sources that serve artwork on the local network, such as ErsatzTV; Plex Media Server refuses to resize those images, so they were blank
- Remove the **empty band under the player's bottom controls**, which came from Plex counting the bottom safe area twice
- Keep the player's **top buttons clear of the status bar** on the unfolded screen in portrait
- Keep the **end of long pages** clear of the tab bar on iPhones without the Duo's vertical bar; the last row stayed behind it
- Mark tabs Plex **can't show right now** (such as Live TV on an account without it) in the Tabs setting, and line up rows without an icon
- Stop the **library tabs button repeating** in the title bar's menu on iPhones without the Duo's vertical bar
- Remove a **gray line across the player** at the progress bar, shown before the video starts, with glass controls on
- Keep the player's **close button clear of the clock** in folded landscape on iPhone Duo
- Make **seeking land where you aim** in a transcoded stream, as when watching over Plex's relay away from home; skipping back used to resume 15 seconds to 2 minutes past the target. Each seek now restarts the stream at the target
- Stop a transcoded stream that **ends early** from finishing the episode and rewinding to the start; it now restarts where it stopped
- Stop **streams restarting** when one of Plex's 30-second keep-alive checks fails, which over Plex's relay happened every few minutes and showed as a pause, a reload and a reset zoom; a failed check is now retried on a fresh connection, and the stream restarts only if the server has really ended it
- Keep **your own tabs** when Plex's Home has a single tab, which happens when Plex's online media sources are turned off for the account

[v1.0.0]: https://github.com/Neeeser/plex-reborn/releases/tag/v8.45_1.0.0

# Contributing

Issues and pull requests are welcome. [Build](README.md#build) in the README covers setting up the scripts and the simulator.

## Issues

Use the bug report form. Say which iPhone you use, and for an iPhone Duo whether it was folded, unfolded or half open, since most layout bugs only show in one of those.

## Pull requests

- One change per pull request. For a new feature, open an issue first so we can agree on it before you build it.
- Say what you changed and why, and link the issue.
- Say what you tested on. A layout change needs a standard iPhone (the iPhone 18 Pro simulator works) and, if it can affect the iPhone Duo, the iPhone Duo simulator folded and unfolded. Add a screenshot for anything visible.
- Make sure `scripts/package-release.sh` still builds.
- Leave `CHANGELOG.md` alone; release notes are written at release time.
- Never commit Plex IPAs, decrypted apps, signing files, logs, or your own device or account IDs. `config.local.sh` holds those and is ignored.

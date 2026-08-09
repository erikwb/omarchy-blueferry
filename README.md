# BlueFerry for Omarchy Quattro

This is the native Omarchy panel for
[BlueFerry](https://github.com/erikwb/blueferry). It shows connection health
and recent conversations in the bar popup, and opens the full client for
messages, pairing, and preferences.

Install it through Omarchy:

```bash
omarchy plugin add https://github.com/erikwb/omarchy-iphone.git
```

Omarchy adds third-party plugins disabled. Review it, then enable BlueFerry
from **Setup › Plugins** and place it on the bar.

The widget expects `blueferry-backend` and `blueferry-quickshell`. If they are
missing, clicking it opens a terminal with the source-build commands; it does
not run them for you. Once they are installed, the same click opens BlueFerry
and its normal pairing flow.

Licensed under [GPL version 2 only](LICENSE).

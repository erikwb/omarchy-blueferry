# BlueFerry for Omarchy Quattro

This is the native Omarchy panel for
[BlueFerry](https://github.com/erikwb/blueferry). It allows you to send and
receive iMessages over Bluetooth while paired to your iPhone with no special
software running on your phone, no proxies, and no cloud tricks. 

This widget shows connection health and recent conversations in the bar popup, 
and opens the full client for messages, pairing, and preferences.

![BlueFerry for Omarchy Quattro](preview.png)

Install it through Omarchy:

```bash
omarchy plugin add https://github.com/erikwb/omarchy-blueferry.git
```

Omarchy adds third-party plugins disabled. Review it, then enable BlueFerry
from **Setup › Plugins** and place it on the bar.

Remove it with:

```bash
omarchy plugin remove io.weirdware.blueferry
```

The widget expects `blueferry-backend` and `blueferry-quickshell`. If they are
missing, clicking it opens a terminal with the source-build commands; it does
not run them for you. Once they are installed, the same click opens BlueFerry
and its normal pairing flow.

Licensed under [GPL version 2 only](LICENSE).

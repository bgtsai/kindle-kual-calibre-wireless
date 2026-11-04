[切換中文](README.zh-TW.md)

# kindle-kual-calibre-wireless

A KUAL extension for jailbroken Kindles. In desktop calibre, **Connect/share → Start wireless device connection** then finds your Kindle over Wi-Fi, and you send and delete books just like with a USB cable — no KOReader needed, books open in the Kindle's own reader.

- Kindle home-screen cover thumbnails, written the same way calibre's USB driver does
- One folder per book: `documents/<title>/<title> - <authors>.<ext>`, so the Kindle's `.sdr` folders stay inside it; deleting a book in calibre removes its folder too
- Chinese file names: calibre always transliterates file names to pinyin; this extension saves books as `<title> - <authors>` in Traditional Chinese, Simplified Chinese, or exactly as in calibre (your choice)
- Airplane mode handled for you: Wi-Fi turns on when you connect and back off when the session ends
- Ends by itself: 5 minutes after connecting if no book arrives, 3 minutes after the last book, or immediately when you eject in calibre
- The Kindle doesn't fall asleep while connected; if it does anyway, it reconnects after waking

> **Status:** v0.5.0. The protocol, timers and file naming are tested against calibre 7.6 in the cloud; **not yet tested on a real Kindle.** Built for Kindle Oasis 2, firmware 5.13.5. Other models may need adjustments — see [Customizing for your Kindle with AI](#customizing-for-your-kindle-with-ai).

## Requirements

- A **jailbroken** Kindle with **KUAL**
- For the book button: the **Universal Hotfix** with shell-script integration (if KOReader shows up as a book in your library, you have it). The KUAL menu works without it.
- calibre on a computer in the same Wi-Fi network
- If you use [kindle-kual-firewall](https://github.com/bgtsai/kindle-kual-firewall): version **1.9 or later** (it allows calibre's discovery broadcast)

## Installation

1. Go to [Releases](../../releases/latest) and download **`calibre-wireless.zip`** (not GitHub's green "Code → Download ZIP", which is the source code).
2. Unzip it. Inside are two folders: `extensions` and `documents`.
3. Connect the Kindle with USB and copy **both** folders to the **root** of the Kindle drive. Let your computer **merge** them with the existing folders — your books and other extensions stay untouched.
4. Eject the Kindle. Open KUAL: you should see **Calibre Wireless**. In your library there is a new "book" called **Calibre 連線**.

Updating: copy the new zip's contents over the old ones the same way. Note that this resets the file-name setting to Traditional Chinese (it lives in `calibre-wireless.conf`, which is part of the zip).

## Usage

1. In calibre: **Connect/share → Start wireless device connection** (once; calibre remembers it).
2. On the Kindle: tap **Calibre 連線** in the library, or KUAL ▸ Calibre Wireless ▸ **連線到 calibre** (Connect).
3. Status messages appear at the top of the screen: `turning on Wi-Fi…`, `searching for calibre…`, `connected`, `received 1/3`…
4. In calibre the Kindle appears as **Wireless device: Kindle**. Send books, delete books, as usual.
5. To end: eject it in calibre, tap the book button / menu item again, or just wait (see the timers above). The Kindle goes back to airplane mode and rescans the library.

## Menu

KUAL ▸ **Calibre Wireless**:

| Item | What it does |
| --- | --- |
| 連線到 calibre / 斷開 calibre 連線 | Connect / disconnect (the label shows the current state) |
| 檔名：繁體 / 簡體 / 原樣 | File names of newly received books: Traditional / Simplified / as in calibre. Tap to cycle. Books already on the Kindle are not renamed. |
| Diagnose | Writes `diagnose.txt` and records events for 2 minutes (see below) |

## Files it creates

| File | What |
| --- | --- |
| `extensions/calibre-wireless/calibre-wireless.log` | Log of every session (English, with Chinese lines) |
| `extensions/calibre-wireless/calibre-wireless.conf` | Settings (`filename_chinese=traditional/simplified/original`) |
| `documents/.calibre-wireless.json` | What calibre sent, so calibre's "On device" column survives reconnects |
| `system/thumbnails/thumbnail_*_portrait.jpg` | Home-screen covers; backup copies in `amazon-cover-bug/` |

## Known limitations

- Not tested on a real Kindle yet. These commands are untested on firmware 5.13.5 and are checked with Diagnose: preventing sleep (`com.lab126.powerd preventScreenSaver`) and rescanning the library (`com.lab126.scanner doFullScan`).
- The on-screen messages are English: the Kindle's `eips` tool only draws ASCII.
- KFX files: no home-screen thumbnail yet.
- Right after boot the Kindle may have no network route for a few minutes; discovery then falls back to the subnet broadcast address (e.g. `192.168.1.255`).

## Uninstall

Delete `extensions/calibre-wireless/` and `documents/Calibre 連線.sh`. Optionally `documents/.calibre-wireless.json`.

## Customizing for your Kindle with AI

### Step 1 — Collect information

1. KUAL ▸ Calibre Wireless ▸ **Diagnose**.
2. Within 2 minutes: press the power button to put the Kindle to sleep, wake it, then turn Wi-Fi off and on.
3. After the 2 minutes, copy out over USB: `extensions/calibre-wireless/diagnose.txt` and `diagnose_events.txt`. They contain no account data, but look through them before sharing.

### Step 2 — Send these to the AI

Start a new conversation, attach `calibre-wireless.zip`, `diagnose.txt` and `diagnose_events.txt`, and paste:

```
I'm using the KUAL extension "kindle-kual-calibre-wireless" (https://github.com/bgtsai/kindle-kual-calibre-wireless) on my jailbroken Kindle. Attached are the extension zip and diagnose.txt / diagnose_events.txt from my Kindle.

Please read CLAUDE.md in the repo first (the "Model-specific parts" table), then check my files:
- "powerd properties": does preventScreenSaver exist? If not, what prevents sleep on my Kindle?
- "scanner properties": does doFullScan exist?
- diagnose_events.txt: what are the sleep / wake events of com.lab126.powerd and the Wi-Fi events?
- "tools": are eips, mkfifo, iptables present?
- "calibre-wireless.log": did the last session find calibre and receive books?

Tell me what needs to change and why before changing anything. Then give me a new calibre-wireless.zip with the same structure and a bumped version in config.xml.

My problem: <describe what happens>
```

## Building from source

```
cd src && GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o ../kindle/extensions/calibre-wireless/bin/calibre-wireless .
```

Then zip the contents of `kindle/`. GitHub Actions does exactly this on every push that changes the version in `config.xml`.

## References

- [UNCaGED](https://github.com/shermp/UNCaGED) — Go implementation of calibre's Smart Device App protocol (vendored in `src/third_party/UNCaGED` with two small patches, marked in the code)
- calibre `src/calibre/devices/smart_device_app/driver.py` (protocol) and `devices/kindle/driver.py` (thumbnail names)
- KOReader `platform/kindle/koreader.sh` (opening the firewall for calibre's reply)

## License

GPL-3.0 (UNCaGED is GPL-3.0).

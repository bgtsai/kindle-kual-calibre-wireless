[切換中文](README.zh-TW.md)

# kindle-kual-calibre-wireless

A KUAL extension for jailbroken Kindles. In desktop calibre, **Connect/share → Start wireless device connection** then finds your Kindle over Wi-Fi, and you send and delete books just like with a USB cable — no KOReader needed, books open in the Kindle's own reader.

- **Home-screen covers**, written the same way calibre's USB driver does
- **One folder per book**: `documents/<title>/<title> - <authors>.<ext>`, so the `.sdr` folders the Kindle creates stay inside it. Deleting a book in calibre removes its folder too.
- **Chinese file names**: calibre always turns file names into pinyin; this extension names books `<title> - <authors>` in Traditional Chinese, Simplified Chinese, or exactly as in calibre (your choice)
- **Airplane mode handled for you**: Wi-Fi turns on when you connect and back off when the session ends
- **Ends by itself**: 5 minutes after connecting if no book arrives, 3 minutes after the last book, or immediately when you eject in calibre
- **No sleep while connected**; if the Kindle sleeps anyway, it reconnects after waking
- **Books sent over USB show up too**: calibre's device view lists them (from the `metadata.calibre` file calibre's USB driver keeps on the Kindle), and deleting one over Wi-Fi also removes it from that file
- **Two ways to start**: a KUAL menu item, or a "book" in your library you tap (needs the Universal Hotfix, see [Requirements](#requirements))

> **Tested on:** Kindle Oasis 2, firmware 5.13.5 (kernel 4.1.15), with calibre 7.6 — connecting from KUAL and from the library book button, receiving and deleting books (including books sent over USB), on-screen messages, and clock sync. Other models may need adjustments — see [Customizing for your Kindle with AI](#customizing-for-your-kindle-with-ai).

## Requirements

- A **jailbroken** Kindle with **KUAL**
- calibre on a computer in the **same Wi-Fi network** (not a guest network, and not a router with "AP / client isolation" — those block the discovery broadcast)
- For the library book button only: the [KindleModding Universal Hotfix](https://github.com/KindleModding/Hotfix) (its *sh_integration* turns `.sh` files in `documents/` into books). If your library shows a **Run Hotfix** book, you have it. The KUAL menu works without it. Installing it: see [Installing the Universal Hotfix](#installing-the-universal-hotfix).
- If you use [kindle-kual-firewall](https://github.com/bgtsai/kindle-kual-firewall): version **1.9 or later** (it allows calibre's discovery broadcast); **1.16 or later** for the clock sync

## Installation

1. Download **[calibre-wireless.zip](../../releases/latest/download/calibre-wireless.zip)** (latest release).
   (Do not use GitHub's green "Code → Download ZIP" button — that is the source code, with a different folder layout.)
2. Unzip it. Inside are **two folders**: `extensions` and `documents`.
3. Connect the Kindle with USB. Copy **both** folders to the **root** of the Kindle drive (where the existing `documents` folder is). Let your computer **merge** them — your books and other extensions stay untouched.
4. Eject the Kindle. Open KUAL: you should see **Calibre Wireless**. With the Universal Hotfix, your library also shows a book called **Calibre 連線**.

No reboot needed.

**Updating:** copy the new zip's contents over the old ones the same way. If kindle-kual-firewall was updated too, press its **Enable Firewall** again. This resets the file-name setting to Traditional Chinese (it lives in `calibre-wireless.conf`, which is part of the zip).

### The structure on the Kindle must look exactly like this

```
Kindle drive (root)
├── documents/
│   └── Calibre 連線.sh            ← the library book button
└── extensions/
    └── calibre-wireless/          ← this folder name must stay "calibre-wireless"
        ├── config.xml
        ├── menu.json
        ├── calibre-wireless.conf
        └── bin/
            ├── calibre-wireless   ← the program
            ├── common.sh
            ├── toggle.sh
            ├── session.sh
            ├── filename_toggle.sh
            └── diagnose.sh
```

Common mistakes:

| Wrong | Why it fails |
| --- | --- |
| `calibre-wireless/extensions/calibre-wireless/...` on the Kindle | Your unzip tool created an extra folder named after the zip. Copy what is **inside** it to the Kindle root. |
| `extensions/calibre-wireless/calibre-wireless/config.xml` | One folder level too deep — KUAL won't find it. |
| `Calibre 連線.sh` at the drive root | It must be inside `documents/`, otherwise it never shows up as a book. |

## Usage

1. In calibre: **Connect/share → Start wireless device connection**. Leave the password **empty** (the extension doesn't send one) and keep the default port. Do this once; calibre remembers it.
2. On the Kindle: tap **Calibre 連線** in the library, or KUAL ▸ Calibre Wireless ▸ **連線到 calibre** (Connect).
3. Status messages appear at the **bottom** of the screen: `turning on Wi-Fi…`, `searching for calibre…`, `connected`, `received 1/3`… You can tap connect first and start calibre afterwards — the Kindle keeps looking for up to 5 minutes.
4. In calibre the Kindle appears as **Wireless device: Kindle**. Send and delete books as usual.
5. To end: eject it in calibre, tap the book / menu item again, or just wait (see the timers above). The Kindle goes back to airplane mode and rescans the library.

### If calibre doesn't find the Kindle (`calibre not found on network`)

- **Computer firewall**: calibre must receive UDP on ports 54982, 48123, 39001, 44044, 59678 and TCP 9090. On Windows, allow calibre for **private** networks (Windows Security → Firewall → Allow an app through firewall) and make sure your network profile is "Private", not "Public".
- **Same network**: computer and Kindle on the same router; no guest Wi-Fi, no client isolation.
- Then send `extensions/calibre-wireless/calibre-wireless.log` along with a problem report.

## Menu

Everything is under one entry in KUAL:

```
Calibre Wireless ▸
    連線到 calibre  /  斷開 calibre 連線
    檔名（繁體／簡體／原樣）：繁體
    置頂 Calibre 連線（開／關）：開
    KUAL 放最後（開／關）：開
    Diagnose (write diagnose.txt)
    錄連線事件（120 秒，查 VoiceView）
    測試：只開 Wi-Fi（不動飛航模式）
```

| Item (the part in brackets lists the choices, after the colon is the current one) | What it does |
| --- | --- |
| **連線到 calibre / 斷開 calibre 連線** | Connect / disconnect. The label shows the current state. Same as tapping the **Calibre 連線** book. |
| **檔名（繁體／簡體／原樣）：…** | File and folder names of newly received books: Traditional Chinese / Simplified Chinese / exactly as in calibre. Tap to cycle. Books already on the Kindle are not renamed. Changing it while connected takes effect from the next connection. |
| **置頂 Calibre 連線（開／關）：…** | Keeps the **Calibre 連線** book first in the library's "Recent" sort. When a connection ends, its last-opened time is set to now + `pin_days` days (default 365, in `calibre-wireless.conf`), so books you open in the meantime stay below it; each connection renews it. Turning it on applies it at once. Turning it off only stops the change (the old time isn't restored). |
| **KUAL 放最後（開／關）：…** | When a connection ends, sets KUAL's last-opened time to 2000-01-01 so it sorts last in "Recent". KUAL moves itself to the top again whenever it is opened, so it goes back to the bottom at the next connection end. |
| **Diagnose** | Writes system information to `diagnose.txt` (read-only, changes nothing). Then, for 2 minutes in the background, records power and Wi-Fi events to `diagnose_events.txt` — put the Kindle to sleep and wake it once, then turn Wi-Fi off and on during that time. It also appends a read-only query of the library database (`/var/local/cc.db`, queried on a copy in `/tmp`) to `diagnose_ccdb.txt`, lists the system fonts and which message font is usable, and copies the library service's scripts (`/usr/lib/ccat/*.lua`) to `diagnose_ccat/` (the session token is only reported as present/absent, never copied). Used for troubleshooting and for adapting the extension to another model. |
| **錄連線事件（120 秒，查 VoiceView）** | Read-only. For 120 seconds, records the Kindle's Bluetooth / Wi-Fi / UI service events (lipc) and, every second, the airplane / Wi-Fi / Bluetooth state, with times, to `diagnose_connect_events.txt`. During that time: turn airplane mode off and on by hand, then tap **Calibre 連線**. Used to find which connection step makes the VoiceView dialog appear. |
| **測試：只開 Wi-Fi（不動飛航模式）** | Test (about 1 minute). Turns on only the Wi-Fi service (`com.lab126.wifid enable 1`) while airplane mode stays on, records every second whether Wi-Fi connects and whether airplane mode or Bluetooth change, then turns Wi-Fi off again. Result: `diagnose_wifi_only.txt`. Keep a Bluetooth device connected and watch whether it drops. |

## What happens during a session

1. Airplane mode off; waits up to **60 s** for Wi-Fi to connect (otherwise gives up and goes back to airplane mode).
2. Sets the Kindle's clock from `pool.ntp.org` (public volunteer time servers, not Amazon; same method as KOReader's time-sync plugin) — a Kindle that is always in airplane mode never syncs and its clock stops, which also breaks the "Recent" sort order. A failure is only logged.
3. Opens the Kindle's own firewall (`iptables INPUT`) for calibre's reply — UDP coming **from** calibre's 5 broadcast ports only — for as long as the session runs.
4. Blocks sleep (`com.lab126.powerd preventScreenSaver`).
5. Broadcasts to find calibre, again every few seconds for up to **5 minutes** (falls back to your subnet's broadcast address, e.g. `192.168.1.255`, if `255.255.255.255` fails right after boot), then talks to it over TCP.
6. If the connection drops (usually because the Kindle slept), waits for Wi-Fi to come back and reconnects — up to 3 times.
- The bottom line of the screen shows the current step the whole time (turning on Wi-Fi, setting the clock, searching, connected, receiving n/N, received, idle…) and is redrawn right after the Kindle repaints the screen (library or another app coming to the front, dialogs) and every 3 s as a fallback; the last message stays 6 s.
7. At the end, whatever the reason: sleep allowed again, firewall rule removed, airplane mode on, "Recent" order adjusted (the two menu items above, through the Kindle's own library service on `127.0.0.1:9101`), library rescan. The last message stays for 4 seconds, then the message lines are wiped.

### How long each step waits

Whenever a session ends — for any reason in this table — the Kindle goes back to airplane mode.

| Step | Time | When it runs out |
| --- | --- | --- |
| Waiting for Wi-Fi to connect | **60 s** | Gives up: `Wi-Fi not connected, gave up` |
| Setting the clock | **20 s** | Skips it (logged), the session continues |
| Looking for calibre | **5 min** (retried every few seconds) | Gives up: `calibre not found on network` |
| Connected, but no book arrives | **5 min** | Disconnects |
| After the last book (or a delete) | **3 min** idle | Disconnects. Every new book or delete starts the 3 minutes again. |
| You eject the Kindle in calibre | immediately | Disconnects |
| Connection lost (e.g. the Kindle slept) | up to **3** reconnects, each waiting 60 s for Wi-Fi | Gives up: `connection lost, gave up` |

Waiting times count only while the Kindle is awake: time spent asleep doesn't use them up. Two more limits come from the UNCaGED library and normally never matter: calibre silent for 60 s counts as a lost connection, and a book gets 2 s per 100 KB to arrive. The 5- and 3-minute values (and the search time) are start options of the program (`-search-timeout`, `-no-book-timeout`, `-idle-timeout`); there is no menu item for them.

## Files it creates

| File | Where (on the USB drive) | Purpose |
| --- | --- | --- |
| `calibre-wireless.log` | `extensions/calibre-wireless/` | One entry per step of every session. Trimmed automatically past about 200 KB. |
| `calibre-wireless.conf` | `extensions/calibre-wireless/` | Settings (`filename_chinese=traditional/simplified/original`, `pin_calibre_book=on/off`, `pin_days=365`, `kual_last=on/off`). Comes in the zip; the menu rewrites it. |
| `metadata.calibre` | drive root | Not created by this extension — calibre's USB driver writes it. Read to list books sent over USB; the entry of a book you delete over Wi-Fi is removed. Books copied to the Kindle without calibre are in neither list and don't show up. |
| `.calibre-wireless.json` | `documents/` | Which books calibre sent and their file names, so calibre's "On device" column survives reconnects. Hidden file. |
| `thumbnail_*_portrait.jpg` | `system/thumbnails/` | Home-screen covers. Backup copies in `amazon-cover-bug/` are put back on every connect if the Kindle deleted them. |
| `diagnose.txt`, `diagnose_events.txt`, `diagnose_ccdb.txt`, `diagnose_ccat/` | `extensions/calibre-wireless/` | Output of **Diagnose**. |

### Checking that it works

After a session, open `extensions/calibre-wireless/calibre-wireless.log`. You should see lines like:

```
2026-11-04 23:15:24  Session start
                     Chinese | 開始連線
2026-11-04 23:15:24  Wi-Fi connected
                     Chinese | Wi-Fi 已連上
2026-11-04 23:15:24  preventScreenSaver=1 ok
                     Chinese | 防休眠設定 1 成功
2026/11/04 23:15:25 found 1 calibre instance(s), using MyPC at 192.168.1.20
2026/11/04 23:15:26 connected to calibre
2026/11/04 23:15:26 book 1/2 received
2026/11/04 23:15:26 book 2/2 received
2026/11/04 23:18:26 auto-disconnect: idle after last book for 3m0s
2026-11-04 23:18:26  Session ended, airplane mode on
                     Chinese | 連線結束，已回到飛行模式
```

Lines with `-` in the date come from the shell scripts and are written twice: English, then an indented `Chinese |` line with the same message. Lines with `/` come from the program itself (English only). `WARN:` lines tell you which step failed (for example `preventScreenSaver=1 failed`).

## Known limitations

- **On-screen messages**: drawn directly on the screen with FBInk's TrueType support in the Kindle's own fonts — `STHeitiTC.ttf`, then `STHeitiMedium.ttf` (both Chinese), then `Amazon-Ember-Regular.ttf` (English only). If none works (or there is no Universal Hotfix), FBInk's blocky built-in font or `eips` draws them in English.
- **Wiped messages leave a blank line until the Kindle redraws**: the messages replace screen pixels the Kindle's own interface doesn't know about. They are wiped at the end, but whatever the interface showed in those lines (e.g. the reading progress line) only comes back when it redraws (turning a page, opening a book). No command was found that makes the interface redraw without switching screens. Messages are drawn with FBInk (comes with the Universal Hotfix); if FBInk is missing or fails, `eips` draws them near the bottom instead (its row height is estimated, so the exact position may differ), or at the top if that row is rejected. An FBInk failure is written to the log once (`WARN: fbink failed`).
- **Clock sync needs Wi-Fi internet access** to `pool.ntp.org` (UDP 123; kindle-kual-firewall ≥ 1.16 allows it). Right after boot the Kindle may have no DNS for a few minutes, so the first session after boot may skip the sync — the log shows `clock sync failed`.
- **KFX files**: no home-screen thumbnail yet.
- **Settings reset on update**: copying a new zip overwrites `calibre-wireless.conf`.
- **No password**: a calibre wireless password is not supported; leave it empty.

## Installing the Universal Hotfix

Only needed for the library book button. The official guide is [KindleModding – Setting up a Hotfix](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/setting-up-a-hotfix/); this is what worked on the tested Kindle:

1. Download [Update_hotfix_universal.bin](https://github.com/KindleModding/Hotfix/releases/latest/download/Update_hotfix_universal.bin).
2. **Remove the `.bin` extension on your computer first**, copy the file to the Kindle root, then rename it back to `Update_hotfix_universal.bin` **on the Kindle drive**. If you copy it with the extension, the Kindle may grab the file while it is still being copied (the USB connection keeps dropping and the file is renamed to `update-18446744073709551615-<id>.bin`), and the update then fails with an error screen.
3. If you block OTA updates with a `update.bin.tmp.partial` folder or KUAL's *Rename OTA Binaries*, undo that first (rename the folder / press **Restore**), and block again afterwards.
4. Eject, then Settings ▸ ⋮ ▸ **Update Your Kindle**. After it finishes, tap **Run Hotfix** in your library.

Do **not** install it with MRPI (KUAL ▸ Install MR Packages): Hotfix 2.x always fails there on a Kindle that never had it (`/var/local/kmc/armel/bin/fbink: not found`, return code 127). Nothing is changed when that happens.

## Uninstall

Delete `extensions/calibre-wireless/` and `documents/Calibre 連線.sh` over USB. Optionally also `documents/.calibre-wireless.json`. Books you received stay where they are.

## Customizing for your Kindle with AI

Some commands depend on the Kindle model and firmware. You can have an AI assistant (Claude, ChatGPT, etc.) adapt them, even if you can't code.

### Step 1 — Collect information from your Kindle

1. Try one session (calibre → start wireless connection, then connect from the Kindle).
2. KUAL ▸ Calibre Wireless ▸ **Diagnose**. Within 2 minutes: press the power button to put the Kindle to sleep, wake it, then turn Wi-Fi off and on.
3. After the 2 minutes, copy out over USB: `extensions/calibre-wireless/diagnose.txt`, `diagnose_events.txt` and `calibre-wireless.log`.

They contain no account data, but look through them before sharing.

### Step 2 — Send these to the AI

Start a **new** conversation, attach `calibre-wireless.zip` (the release file) and the three files, and paste this message (edit the last part):

```
I'm using the KUAL extension "kindle-kual-calibre-wireless" (https://github.com/bgtsai/kindle-kual-calibre-wireless) on my jailbroken Kindle. Attached are the extension zip and diagnose.txt / diagnose_events.txt / calibre-wireless.log from my Kindle.

Please read CLAUDE.md in the repo first (the "Model-specific parts" table), then check my files:
- "powerd properties": does preventScreenSaver exist? Does the log show "preventScreenSaver=1 ok"?
- "scanner properties": does doFullScan exist? Did new books appear on the home screen?
- diagnose_events.txt: what are the sleep / wake events of com.lab126.powerd and the Wi-Fi events?
- "tools": are eips, mkfifo, iptables present?
- "calibre-wireless.log": did the last session find calibre and receive books? Any WARN lines?

Tell me what needs to change and why before changing anything. Then give me a new calibre-wireless.zip with the same structure (extensions/calibre-wireless/... and documents/...) and a bumped version in config.xml.

My problem: <describe what happens>
```

### Step 3 — Install the result

Copy the new zip's contents over the old ones (see [Installation](#installation)) and try a session again.

## Notes for AI

See [CLAUDE.md](CLAUDE.md) — it lists the model-specific parts, how to test in the cloud without a Kindle, and the decisions agreed with the author.

## Building from source

```
cd src && GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o ../kindle/extensions/calibre-wireless/bin/calibre-wireless .
```

Then zip the contents of `kindle/`. GitHub Actions does exactly this when the version in `config.xml` changes.

## References

- [UNCaGED](https://github.com/shermp/UNCaGED) — Go implementation of calibre's Smart Device App protocol (vendored in `src/third_party/UNCaGED` with two small patches, marked in the code)
- calibre [`smart_device_app/driver.py`](https://github.com/kovidgoyal/calibre/blob/master/src/calibre/devices/smart_device_app/driver.py) (protocol, broadcast ports) and [`kindle/driver.py`](https://github.com/kovidgoyal/calibre/blob/master/src/calibre/devices/kindle/driver.py) (thumbnail names, cover size)
- KOReader [`platform/kindle/koreader.sh`](https://github.com/koreader/koreader/blob/master/platform/kindle/koreader.sh) (opening the Kindle's firewall for calibre's reply)
- [KindleModding – Scriptlets](https://kindlemodding.org/kindle-dev/scriptlets.html) (`documents/*.sh` books) and [KindleModding/Hotfix](https://github.com/KindleModding/Hotfix)
- [OpenCC](https://github.com/BYVoid/OpenCC) dictionaries (Traditional / Simplified conversion of file names)

## License

GPL-3.0, see [LICENSE](LICENSE). The program includes UNCaGED (GPL-3.0), pyfmt (BSD-3-Clause) and the OpenCC dictionaries (Apache-2.0); details and license texts in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [licenses/](licenses/). The Release zip contains the same files in `extensions/calibre-wireless/`.

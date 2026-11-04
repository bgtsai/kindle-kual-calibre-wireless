# CLAUDE.md — notes for AI assistants

KUAL extension (work in progress) that lets desktop calibre's **Connect/share → Start wireless device connection** see a jailbroken Kindle and send/delete books like a USB connection, without KOReader. Client side of calibre's Smart Device App protocol, built on [UNCaGED](https://github.com/shermp/UNCaGED) (GPL-3.0 → this repo is GPL-3.0).

## Status

- v0.3.0 (`src/main.go`, `src/thumb.go`, `src/naming.go`): discovers calibre by UDP broadcast, receives books into `-dir`, keeps calibre's "On device" list in `<dir>/.calibre-wireless.json`, supports delete, exits when calibre ejects. Writes Kindle home thumbnails like calibre's USB KINDLE2 driver (`system/thumbnails/thumbnail_{EXTH113}_{EXTH501}_portrait.jpg`, cover height 500 = calibre's Oasis 2 value), keeps copies in `amazon-cover-bug/` and restores ones the firmware deleted on every connect, removes them on delete. Device shows as "Wireless device: Kindle".
- Chinese file names: calibre always transliterates lpaths with `ascii_filename` (USB too, no option). The client keeps calibre's lpath as the key but stores the file as `<title> - <authors>.<ext>` converted per `filename_chinese` in `kindle/extensions/calibre-wireless/calibre-wireless.conf` (`traditional` = OpenCC s2tw, `simplified` = tw2s, `original`); mapping lpath → file in the state file's `files`. s2tw/tw2s on purpose (characters only, no vocabulary swaps like s2twp). FAT32/Windows-unsafe characters → `_`, 120-rune limit, collisions get ` (2)`. Books from v0.2.0 (no mapping) keep working. Setting only affects newly received books.
- The opencc package registers a global `-dir` flag in init(); main uses its own FlagSet.
- All of the above verified in the cloud against calibre 7.6 (apt) with `test/calibre_server.py`; not yet run on a Kindle.
- Not done yet: KUAL wrapper (single top-level item with submenu: connect/disconnect, filename setting toggle that rewrites the .conf, diagnose) + scriptlet book button `documents/*.sh` (connect/disconnect only, status via on-screen messages), library rescan after receiving, KFX thumbnails, airplane mode on/off, sleep prevention, wake reconnect, auto-disconnect timers, README.

## Build

```
cd src && GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o ../build/calibre-wireless .
```

## Test (cloud, no Kindle)

```
apt-get install -y calibre
calibre-debug test/calibre_server.py -- book1.azw3 book2.azw3 &   # headless calibre side; add --delete to delete the first device book
./calibre-wireless -dir /tmp/k/documents -thumbs /tmp/k/system/thumbnails -cover-cache /tmp/k/amazon-cover-bug
# put <book>.jpg next to a book to send a full-size cover (the GUI uses the library cover)
```

## Decisions (agreed with the user, don't change without asking)

- KUAL: one top-level item, everything in its submenu (connect/disconnect, `檔名：繁體/簡體/原樣` toggle, diagnose). Settings live only in `calibre-wireless.conf`; the menu just shows/rewrites it.
- Scriptlet book button in `documents/` (needs the Universal Hotfix sh_integration, which the user has — KOReader shows up as a book): connect/disconnect only; its title can't change, so status is shown as on-screen messages.
- Connect: leave airplane mode, wait for Wi-Fi, give up after 60 s. Disconnect (any reason) → back to airplane mode.
- Auto-disconnect: 5 min after connecting with no book; 3 min idle after the last book (`totalBooks`); calibre eject ends immediately.
- Prevent sleep while connected; if it sleeps anyway, reconnect after wake. Cover thumbnails are required.
- Works with bgtsai/kindle-kual-firewall ≥ v1.9 (allows UDP to 255.255.255.255 on calibre's 5 broadcast ports). The INPUT-side UDP reply port is opened by this extension only while connected (like KOReader's `koreader.sh`).
- Known risk: right after boot the Kindle may have no default route for minutes (knowledge base 32 §8); broadcast to 255.255.255.255 may fail → fall back to the wlan0 subnet broadcast address.

## Next step — handoff (2026-11-04)

Go client (v0.3.0) is done and tested in the cloud. Next: the Kindle-side wrapper. **Ask the user before starting each part** (they approve changes per round). Before writing Kindle shell code, read knowledge base file 32 (`python3 _tools/read_kb.py 32` in bgtsai/claude-knowledge-base) — §7/§8 have the tested lipc events, airplane-mode command, busybox `timeout -t`, and the late-DNS/route behaviour after boot.

To build (layout like bgtsai/kindle-kual-firewall: `kindle/` mirrors the Kindle drive root, a Release zip = its contents):

1. `kindle/extensions/calibre-wireless/` — `config.xml` (`<information>` + `<menus><menu type="json" dynamic="true">`, `<id>` = folder name), `menu.json` with ONE top-level item; submenu: connect/disconnect (label follows state), `檔名：繁體/簡體/原樣` (tap cycles, rewrites `calibre-wireless.conf`, label shows the current value), Diagnose. `bin/calibre-wireless` = ARM build of `src/` (GOARM=7, static). Add a GitHub Actions release like the firewall repo.
2. Scriptlet book button `kindle/documents/Calibre 連線.sh` (`# Name:`, `# Author:`, `# Icon:` header; `# DontUseFBInk` and show our own messages with `eips`/fbink) — calls the same toggle script as the KUAL item. Don't let it appear in calibre's book list (the client only lists books calibre sent, so fine) .
3. One `bin/toggle.sh` doing the session: single instance (pid file); airplane mode off `lipc-set-prop -i com.lab126.cmd wirelessEnable 1`; wait for `cmStateChange` → CONNECTED (not `cmConnected`, it repeats every ~30 s), give up after 60 s; open INPUT UDP for calibre's broadcast reply while connected (`iptables -I INPUT -i wlan0 -p udp -j ACCEPT` scoped as narrowly as possible, removed on exit — like KOReader `platform/kindle/koreader.sh` lines 207/423); run the client; prevent sleep while connected (`lipc-set-prop com.lab126.powerd preventScreenSaver 1` — **unverified on 5.13.5**); on wake from sleep reconnect (find the powerd wake event via a diagnose recording, KB 32 §7 shows how); after disconnect (any reason) → `preventScreenSaver 0`, close INPUT rule, airplane mode back on (`wirelessEnable 0`), trigger a library rescan (`lipc-set-prop com.lab126.scanner doFullScan 1` — **unverified**); on-screen status messages (connecting / received n/N / disconnected).
4. Auto-disconnect timers in the Go client (it knows `thisBook/totalBooks`): 5 min after connecting with no book; 3 min idle after the last book; calibre eject ends immediately. Use the uc exit channel (`SetExitChannel`).
5. Broadcast fallback: UNCaGED hard-codes `255.255.255.255`; right after boot there may be no default route (KB 32 §8) → if the send fails, use the wlan0 subnet broadcast. Needs a small patch/fork of `calibre/calibre.go` discovery (or vendor it).
6. Diagnose button → `diagnose.txt` in the extension folder: firmware/version.txt, tools present (lipc-*, eips, fbink, iptables), powerd/scanner property values, a 2-minute `lipc-wait-event -m` recording of powerd + wifid while the user sleeps/wakes the device and toggles Wi-Fi, iptables -L for INPUT/OUTPUT, the last client log.
7. README (zh-TW + en, same template as the firewall repo), CLAUDE.md model-specific table.

User's device: Kindle Oasis 2, firmware 5.13.5, kernel 4.1.15-lab126, jailbroken, KUAL + Universal Hotfix (KOReader scriptlet shows in library), bgtsai/kindle-kual-firewall v1.15 installed (airplane mode on boot/shutdown, allows calibre broadcast UDP out).

Pending notes for archiving: bgtsai/claude-knowledge-base `_pending/20261104-1330_kindle-calibre-wireless.md` (archive into KB 32 when the user says 歸檔).

Separate future project (do NOT start here): Bluetooth page turner for the native reader on the Oasis 2 — kindle-hid-passthrough + kindle-button-mapper-rs, new repo and new thread.

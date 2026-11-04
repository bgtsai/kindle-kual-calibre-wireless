# CLAUDE.md — notes for AI assistants

KUAL extension (work in progress) that lets desktop calibre's **Connect/share → Start wireless device connection** see a jailbroken Kindle and send/delete books like a USB connection, without KOReader. Client side of calibre's Smart Device App protocol, built on [UNCaGED](https://github.com/shermp/UNCaGED) (GPL-3.0 → this repo is GPL-3.0).

## Status

- v0.2.0 (`src/main.go`, `src/thumb.go`): discovers calibre by UDP broadcast, receives books into `-dir`, keeps calibre's "On device" list in `<dir>/.calibre-wireless.json`, supports delete, exits when calibre ejects. Writes Kindle home thumbnails like calibre's USB KINDLE2 driver (`system/thumbnails/thumbnail_{EXTH113}_{EXTH501}_portrait.jpg`, cover height 500 = calibre's Oasis 2 value), keeps copies in `amazon-cover-bug/` and restores ones the firmware deleted on every connect, removes them on delete. Device shows as "Wireless device: Kindle". Verified in the cloud against calibre 7.6 (apt) with `test/calibre_server.py` (thumbnail names match calibre's own `MetadataHeader` result); not yet run on a Kindle.
- Not done yet: library rescan after receiving (planned in the KUAL wrapper), Chinese file names (calibre always transliterates lpaths with `ascii_filename`, USB too; the client could store under a Chinese name and map lpath → file — not decided), KFX thumbnails, airplane mode on/off, sleep prevention, wake reconnect, auto-disconnect timers, KUAL menu/scripts, diagnose button, README.

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

- Single toggle KUAL item ("Calibre 連線" / disconnect while connected).
- Connect: leave airplane mode, wait for Wi-Fi, give up after 60 s. Disconnect (any reason) → back to airplane mode.
- Auto-disconnect: 5 min after connecting with no book; 3 min idle after the last book (`totalBooks`); calibre eject ends immediately.
- Prevent sleep while connected; if it sleeps anyway, reconnect after wake. Cover thumbnails are required.
- Works with bgtsai/kindle-kual-firewall ≥ v1.9 (allows UDP to 255.255.255.255 on calibre's 5 broadcast ports). The INPUT-side UDP reply port is opened by this extension only while connected (like KOReader's `koreader.sh`).
- Known risk: right after boot the Kindle may have no default route for minutes (knowledge base 32 §8); broadcast to 255.255.255.255 may fail → fall back to the wlan0 subnet broadcast address.

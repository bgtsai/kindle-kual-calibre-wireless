# Headless calibre smart-device server for testing a wireless client.
# Usage: calibre-debug server.py -- <book files...>
# Waits for a client, lists device books, uploads given files (totalBooks=N), lists again, ejects.
import sys, time
from calibre.customize.ui import device_plugins
from calibre.devices.smart_device_app.driver import SMART_DEVICE_APP

delete = '--delete' in sys.argv
files = [a for a in sys.argv[1:] if a != '--delete']
d = [p for p in device_plugins() if isinstance(p, SMART_DEVICE_APP)][0]
d.report_progress = lambda *a, **k: None
d.startup()
msg = d.start_plugin()
print('start_plugin:', msg, 'port', getattr(d, 'port', None), flush=True)
dev = None
for _ in range(120):
    dev = d.detect_managed_devices([])
    if dev:
        break
    time.sleep(0.5)
if not dev:
    print('NO CLIENT'); d.stop_plugin(); sys.exit(1)
d.open(None, 'test-lib-uuid')
print('CONNECTED:', d.get_gui_name(), flush=True)
bl = d.books()
print('BOOKS BEFORE:', [(b.title, b.lpath) for b in bl], flush=True)
from calibre.ebooks.metadata.meta import get_metadata
import os
mds = []
names = []
for f in files:
    with open(f, 'rb') as s:
        mi = get_metadata(s, os.path.splitext(f)[1][1:])
    mi.uuid = 'uuid-' + os.path.basename(f)
    # The GUI fills mi.thumbnail from the library cover; emulate it from the file's embedded cover.
    # Prefer a full-size sidecar cover (<book>.jpg) like the GUI's library cover; the
    # cover embedded in an azw3 may be only the small EXTH thumbnail.
    cover = open(f + '.jpg', 'rb').read() if os.path.exists(f + '.jpg') else (mi.cover_data[1] if mi.cover_data else None)
    if cover:
        from calibre.utils.img import scale_image
        # scale_image's width defaults to 60; make height the only limit (as the GUI does)
        w, h, data = scale_image(cover, width=10000, height=d.THUMBNAIL_HEIGHT)
        mi.thumbnail = (w, h, data)
    mds.append(mi); names.append(os.path.basename(f))
locs = d.upload_books(files, names, metadata=mds) if files else []
print('UPLOADED:', locs, flush=True)
d.add_books_to_metadata(locs, mds, [bl, None, None])
d.sync_booklists([bl, None, None])
if delete and len(bl):
    lp = bl[0].lpath
    d.delete_books([lp]); d.remove_books_from_metadata([lp], [bl]); d.sync_booklists([bl, None, None])
    print('DELETED:', lp, flush=True)
bl2 = d.books()
print('BOOKS AFTER:', [(b.title, b.lpath) for b in bl2], flush=True)
d.eject()
print('EJECTED', flush=True)
d.stop_plugin()

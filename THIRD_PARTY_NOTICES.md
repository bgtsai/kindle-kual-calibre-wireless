# Third-party notices

This extension is licensed under the GNU General Public License v3.0 (see `LICENSE`).
The program `bin/calibre-wireless` is built from this repository's `src/` and contains:

| Component | Used for | License | License text |
| --- | --- | --- | --- |
| [UNCaGED](https://github.com/shermp/UNCaGED) v0.7.3 by Sherman Perry — vendored in `src/third_party/UNCaGED`, two small patches marked "kindle-kual-calibre-wireless patch" | calibre's Smart Device App protocol | GPL-3.0 | `LICENSE` |
| [pyfmt](https://github.com/slongfield/pyfmt) (2018-01-24) by Stephen Longfield, Jr. — used by UNCaGED | string formatting | BSD-3-Clause | `licenses/pyfmt-BSD-3-Clause.txt` |
| [OpenCC](https://github.com/BYVoid/OpenCC) dictionaries (copied from [longbridgeapp/opencc](https://github.com/longbridgeapp/opencc) v0.3.13, unmodified) — `src/zhconv/dict/` | Traditional / Simplified conversion of file names | Apache-2.0 | `licenses/OpenCC-Apache-2.0.txt` |

The conversion code itself (`src/zhconv/zhconv.go`) is our own and GPL-3.0. Up to v0.8.0 the
program used the Go package longbridgeapp/opencc, which depends on liuzl/cedar-go (GPL-2.0,
no "or later" grant); v0.9.0 replaced it to avoid any license conflict with GPL-3.0.

Source code: <https://github.com/bgtsai/kindle-kual-calibre-wireless> (the tag of each release
is the exact source of that release's binary).

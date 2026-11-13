#!/bin/sh
# calibre-wireless pin_toggle.sh v0.10.0
# 「置頂 Calibre 連線」開／關。設定唯一來源是 calibre-wireless.conf；這裡只改寫它，再重畫選單。
# 打開時立刻套用一次（不用等下次連線結束）；關掉只是之後不再改，不還原原本的時間（沒有記下來）。
. "$(dirname "$0")/common.sh"

if [ "$(conf_get pin_calibre_book on)" = on ]; then next=off; else next=on; fi
conf_set pin_calibre_book "$next"
render_menu
log "pin_calibre_book -> $next" "置頂 Calibre 連線改為 $(onoff_label "$next")"
[ "$next" = on ] && apply_recent_order
# 螢幕提示用英文：eips/FBInk 內建字型只有 ASCII
notify_brief "Pin Calibre book: $next"

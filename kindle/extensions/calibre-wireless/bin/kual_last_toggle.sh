#!/bin/sh
# calibre-wireless kual_last_toggle.sh v0.10.0
# 「KUAL 放最後」開／關。設定唯一來源是 calibre-wireless.conf；這裡只改寫它，再重畫選單。
# 不在這裡立刻套用：這是從 KUAL 按的，KUAL 結束時會把自己的時間改回「現在」，
# 現在改了也會被蓋掉 → 等下次連線結束才調整。
. "$(dirname "$0")/common.sh"

if [ "$(conf_get kual_last on)" = on ]; then next=off; else next=on; fi
conf_set kual_last "$next"
render_menu
log "kual_last -> $next" "KUAL 放最後改為 $(onoff_label "$next")"
notify_brief "KUAL last: $next (from next connection end)"

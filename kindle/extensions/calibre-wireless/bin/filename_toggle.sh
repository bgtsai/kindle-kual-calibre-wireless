#!/bin/sh
# calibre-wireless filename_toggle.sh v0.4.0
# 檔名設定輪替：繁體 → 簡體 → 原樣 → 繁體。只影響之後收到的書。
# 設定唯一來源是 calibre-wireless.conf；這裡只改寫它，再重畫選單。
. "$(dirname "$0")/common.sh"

case "$(conf_get filename_chinese traditional)" in
    traditional) next=simplified ;;
    simplified)  next=original ;;
    *)           next=traditional ;;
esac
conf_set filename_chinese "$next"
render_menu
log "filename_chinese -> $next" "檔名設定改為 $(filename_label "$next")"
# 螢幕提示用英文：eips 內建字型只有 ASCII，中文會變亂碼
# 連線中改設定，Go 程式只在啟動時讀 .conf → 下次連線才生效
if session_running; then
    notify "File names: $next (from next connection)"
else
    notify "File names: $next"
fi

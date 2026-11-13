#!/bin/sh
# calibre-wireless filename_toggle.sh v0.11.0
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
# 螢幕提示：有 TrueType 中文字型時畫中文，沒有才畫英文（點陣字只有 ASCII）
# 連線中改設定，Go 程式只在啟動時讀 .conf → 下次連線才生效
if session_running; then
    notify_brief "File names: $next (from next connection)" "檔名：$(filename_label "$next")（下次連線生效）"
else
    notify_brief "File names: $next" "檔名：$(filename_label "$next")"
fi

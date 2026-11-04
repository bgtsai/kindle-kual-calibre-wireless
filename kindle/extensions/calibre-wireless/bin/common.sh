#!/bin/sh
# calibre-wireless common.sh v0.4.0 — 各腳本共用的路徑與函式

BASE="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$BASE/calibre-wireless.conf"
MENU="$BASE/menu.json"
LOG="$BASE/calibre-wireless.log"
CLIENT="$BASE/bin/calibre-wireless"
# 連線階段（toggle.sh 的背景程序）的 pid；有這個檔且程序活著＝連線中
PIDFILE="/var/run/calibre-wireless.pid"
# calibre-wireless.log 超過這個大小 (bytes) 就只保留後半段
LOG_MAX_BYTES=200000

# 雙語 log：log "<English>" "<中文>"（格式同 kindle-kual-firewall）
log() {
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt "$LOG_MAX_BYTES" ]; then
        tail -c $((LOG_MAX_BYTES / 2)) "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "$ts  $1" >> "$LOG"
    [ -n "$2" ] && echo "                     Chinese | $2" >> "$LOG"
}

# 螢幕提示（eips 不存在就略過）。第 2 個參數是列號，預設 2
notify() {
    which eips >/dev/null 2>&1 && eips 2 "${2:-2}" "$1                              " >/dev/null 2>&1
}

# 連線階段是否正在跑
session_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

# 讀 .conf 的值：conf_get <key> <預設值>
conf_get() {
    v="$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$CONF" 2>/dev/null | tail -n 1)"
    echo "${v:-$2}"
}

# 改寫 .conf 的值（保留註解與其他行）；沒有這個 key 就加在檔尾
conf_set() {
    if grep -q "^[[:space:]]*$1[[:space:]]*=" "$CONF" 2>/dev/null; then
        sed "s/^[[:space:]]*$1[[:space:]]*=.*/$1=$2/" "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
    else
        echo "$1=$2" >> "$CONF"
    fi
}

# 檔名設定值 → 選單上顯示的文字
filename_label() {
    case "$1" in
        simplified) echo "簡體" ;;
        original)   echo "原樣" ;;
        *)          echo "繁體" ;;
    esac
}

# 依目前狀態重寫 menu.json。
# 為什麼用重寫檔案：config.xml 設了 dynamic="true"，KUAL 每次打開選單都重讀 menu.json，
# 標籤要跟著狀態變只能改檔。"refresh": true 讓 KUAL 在按完後重新載入選單（實機未驗證；
# 沒生效的話，重新打開 KUAL 選單也會看到新標籤）。
render_menu() {
    if session_running; then conn="斷開 calibre 連線"; else conn="連線到 calibre"; fi
    fn="檔名：$(filename_label "$(conf_get filename_chinese traditional)")"
    cat > "$MENU.tmp" <<EOF
{
  "items": [
    {
      "name": "Calibre Wireless",
      "priority": 1,
      "items": [
        { "name": "$conn", "priority": 1, "action": "./bin/toggle.sh", "exitmenu": false, "refresh": true },
        { "name": "$fn", "priority": 2, "action": "./bin/filename_toggle.sh", "exitmenu": false, "refresh": true },
        { "name": "Diagnose (write diagnose.txt)", "priority": 3, "action": "./bin/diagnose.sh" }
      ]
    }
  ]
}
EOF
    mv "$MENU.tmp" "$MENU"
}

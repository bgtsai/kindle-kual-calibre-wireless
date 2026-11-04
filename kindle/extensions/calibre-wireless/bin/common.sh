#!/bin/sh
# calibre-wireless common.sh v0.6.0 — 各腳本共用的路徑與函式

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

# ---- 螢幕提示：畫在畫面最底部，用完擦掉 ----
# 為什麼在底部：頂端是 Kindle 的狀態列（時間、電量），訊息殘留在那裡最顯眼（使用者回報 2026-11-05）。
# 為什麼要擦：eips/fbink 直接改畫面像素，Kindle 介面不知道，程式結束後字會一直留著，
# 要等介面因為開書等動作重畫才被蓋掉。擦掉＝用空白（白底）蓋回去；原本那一列的介面內容
# 要等介面下次重畫才會回來——沒有查到「只重畫、不切換畫面」的指令（KB 32 第 10 節）。
# 第 2 個參數是第幾列，從底部算：1＝最底下一列（狀態），2＝它上面一列（進度）。
# 優先用 FBInk（Universal Hotfix 會裝，支援負數列號＝從底部算、-r 右邊補空白蓋掉舊字）；
# 沒有 FBInk 就退回 eips，eips 不能從底部算，只好畫在頂端第 2、3 列（v0.5.0 的位置）。
NOTIFY_SLOTS="1 2"
# 結束訊息停留幾秒再擦掉 (s)，讓使用者看得到最後一句
NOTIFY_CLEAR_DELAY_S=4

find_fbink() {
    for f in /var/local/kmc/armhf/bin/fbink /var/local/kmc/armel/bin/fbink /mnt/us/libkh/bin/fbink "$(which fbink 2>/dev/null)"; do
        [ -n "$f" ] && [ -x "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}
FBINK="$(find_fbink)"

notify() {
    slot="${2:-1}"
    if [ -n "$FBINK" ]; then
        "$FBINK" -q -y "-$slot" -r "$1" >/dev/null 2>&1
    elif which eips >/dev/null 2>&1; then
        eips 2 "$((slot + 1))" "$1                              " >/dev/null 2>&1
    fi
}

# 擦掉所有提示列
clear_notify() {
    for slot in $NOTIFY_SLOTS; do
        if [ -n "$FBINK" ]; then
            "$FBINK" -q -y "-$slot" -r " " >/dev/null 2>&1
        elif which eips >/dev/null 2>&1; then
            eips 0 "$((slot + 1))" "                                                  " >/dev/null 2>&1
        fi
    done
}

# 顯示一句、過幾秒擦掉；背景執行，不拖住呼叫的人
notify_brief() {
    notify "$1" "$2"
    ( sleep "$NOTIFY_CLEAR_DELAY_S"; clear_notify ) </dev/null >/dev/null 2>&1 &
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

#!/bin/sh
# calibre-wireless common.sh v0.10.0 — 各腳本共用的路徑與函式

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
# 優先用 FBInk（Universal Hotfix 會裝，支援負數列號＝從底部算、-r 右邊補空白蓋掉舊字）。
# 選 FBInk 要看架構（v0.7.0 實機）：Hotfix 同時裝了 armhf 與 armel 兩份，Oasis 2（5.13.5）是 armel，
# armhf 版在它上面「檔案在卻 not found」（rc 127，缺 armhf 的載入程式）。所以有
# /lib/ld-linux-armhf.so.3 才先試 armhf，每個候選先跑一次 -h，rc 126／127 的跳過。
# 畫字時還是失敗 → 錯誤寫進 log、把「那個檔」記進 FBINK_FAILED（只略過它，不連帶停用其他份），
# 這次改用 eips（v0.6.0 實機：失敗被丟掉、又不退回 eips，畫面全空）。
# eips 不能用負數列號，底部列號＝螢幕高（eips -i 的 yres）÷ EIPS_ROW_PX − EIPS_BOTTOM_MARGIN。
# EIPS_ROW_PX＝24：v0.7.0 實機照片，第 41 列落在 1680 高畫面的約 60%（41×24≈984），
# 字寬約 16（長訊息在約 79 字截斷，1264÷16）。eips 對超出畫面的列號不報錯（row 80 也回 ok），
# 所以不能靠「被拒畫」判斷；讀不到 yres 時才畫在頂端第 2、3 列。
NOTIFY_SLOTS="1 2"
# 結束訊息停留幾秒再擦掉 (s)，讓使用者看得到最後一句
NOTIFY_CLEAR_DELAY_S=4
# eips 一列的高度 (px)，估計值，見上方說明
EIPS_ROW_PX=24
# eips 底部留幾列不畫（最底下那列可能被裁掉）
EIPS_BOTTOM_MARGIN=1
FBINK_FAILED="/tmp/calibre-wireless.fbink-failed"

fbink_candidates() {
    if [ -e /lib/ld-linux-armhf.so.3 ]; then
        echo /var/local/kmc/armhf/bin/fbink /var/local/kmc/armel/bin/fbink
    else
        echo /var/local/kmc/armel/bin/fbink /var/local/kmc/armhf/bin/fbink
    fi
    echo /mnt/us/libkh/bin/fbink "$(which fbink 2>/dev/null)"
}

find_fbink() {
    for f in $(fbink_candidates); do
        if [ -z "$f" ] || [ ! -x "$f" ]; then continue; fi
        grep -qxF "$f" "$FBINK_FAILED" 2>/dev/null && continue
        "$f" -h >/dev/null 2>&1
        case $? in 126|127) continue ;; esac
        echo "$f"
        return 0
    done
    return 1
}
FBINK="$(find_fbink)"

# eips 的總列數（讀不到就空字串）
eips_rows() {
    yres="$(eips -i 2>/dev/null | awk '/yres:/ { for (i = 1; i <= NF; i++) if ($i == "yres:") { print $(i + 1); exit } }')"
    case "$yres" in ''|*[!0-9]*) return 1 ;; esac
    echo $((yres / EIPS_ROW_PX))
}
EIPS_BOTTOM=""

# 用 eips 畫一列；slot 從底部算。底部算不出來或被拒畫就畫在頂端
eips_line() {
    which eips >/dev/null 2>&1 || return 1
    if [ -z "$EIPS_BOTTOM" ]; then
        r="$(eips_rows)"
        if [ -n "$r" ] && [ "$r" -gt 4 ]; then EIPS_BOTTOM=$((r - EIPS_BOTTOM_MARGIN)); else EIPS_BOTTOM=0; fi
    fi
    if [ "$EIPS_BOTTOM" -gt 0 ]; then
        eips 0 "$((EIPS_BOTTOM - $1 + 1))" "$2" >/dev/null 2>&1
    else
        eips 0 "$(($1 + 1))" "$2" >/dev/null 2>&1
    fi
}

# 畫一列（slot 從底部算）；$2 是要畫的完整字串
draw_line() {
    if [ -n "$FBINK" ]; then
        err="$("$FBINK" -q -y "-$1" -r "$2" 2>&1)"
        rc=$?
        [ "$rc" = 0 ] && return 0
        log "WARN: fbink failed (rc=$rc, $FBINK): $err - using eips" "警告：fbink 執行失敗，改用 eips（原因見上一行）"
        echo "$FBINK" >> "$FBINK_FAILED"
        FBINK="$(find_fbink)"
        [ -n "$FBINK" ] && { draw_line "$1" "$2"; return; }
    fi
    eips_line "$1" "$2"
}

notify() {
    # 右邊補空白：蓋掉上一句較長的字（eips 不會自己補）
    draw_line "${2:-1}" "  $1                                        "
}

# 擦掉所有提示列
clear_notify() {
    for slot in $NOTIFY_SLOTS; do
        draw_line "$slot" "                                                            "
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

# ---- 書庫「最近」排序：「Calibre 連線」永遠第一、KUAL 放最後（v0.10.0）----
# 「最近」依 /var/local/cc.db 的 Entries.p_lastAccess（整數 Unix 秒）排。直接用 sqlite3 改不了
# （索引含 COLLATE icu 的欄位，機上 sqlite3 沒有 icu），所以由 client 的 -set-last-access 請書庫
# 服務自己改（src/ccat.go）。這裡只用 sqlite3 讀出 uuid——讀不會碰到 icu。
# uuid 每次重新查：點書本按鈕後那一筆曾被刪掉重建、uuid 換新（v0.9.2 實機，原因未明）。
CCDB=/var/local/cc.db
BOOK_BUTTON_PATH="/mnt/us/documents/Calibre 連線.sh"
KUAL_BOOK_PATH="/mnt/us/documents/KUAL.kual"
# 「Calibre 連線」設成「現在 + pin_days 天」：比任何剛打開的書都晚，pin_days 內用一次就續期。
# 預設 365（使用者選）：時鐘停在 2020 時，時間是 2022-12／2023-03 的書照樣顯示、排序，
# 所以一年的「未來時間」不會被當成無效而隱藏。太遠（例如 2099）有被隱藏的回報，不用。
PIN_DAYS_DEFAULT=365
# KUAL 設成 2000-01-01 00:00 UTC：比使用者所有的書都早；不用 0，0 這類值可能被當成「沒打開過」。
KUAL_LAST_ACCESS=946684800

# 用路徑查 cc.db 那一筆的 uuid；查不到輸出空字串。先試唯讀開啟，舊版 sqlite3 不認得 -readonly 時再一般開啟（只有 SELECT）
ccdb_uuid() {
    q="SELECT p_uuid FROM Entries WHERE p_location = '$1';"
    sqlite3 -readonly "$CCDB" "$q" 2>/dev/null || sqlite3 "$CCDB" "$q" 2>>"$LOG"
}

# 依設定調整兩筆的上次存取時間；結果寫進 log，失敗不影響連線
apply_recent_order() {
    spec=""
    if [ "$(conf_get pin_calibre_book on)" = on ]; then
        days="$(conf_get pin_days "$PIN_DAYS_DEFAULT")"
        case "$days" in ''|*[!0-9]*) days="$PIN_DAYS_DEFAULT" ;; esac
        u="$(ccdb_uuid "$BOOK_BUTTON_PATH")"
        if [ -n "$u" ]; then
            spec="$u=$(( $(date +%s) + days * 86400 ))"
        else
            log "Pin: book button not in library ($BOOK_BUTTON_PATH), skipped" "置頂：書庫裡沒有「Calibre 連線」這本，略過"
        fi
    fi
    if [ "$(conf_get kual_last on)" = on ]; then
        u="$(ccdb_uuid "$KUAL_BOOK_PATH")"
        if [ -n "$u" ]; then
            spec="${spec:+$spec,}$u=$KUAL_LAST_ACCESS"
        else
            log "KUAL last: KUAL not in library ($KUAL_BOOK_PATH), skipped" "KUAL 放最後：書庫裡沒有 KUAL，略過"
        fi
    fi
    [ -n "$spec" ] || return 0
    if "$CLIENT" -set-last-access "$spec" >> "$LOG" 2>&1; then
        log "Recent order updated" "已調整「最近」排序"
    else
        log "WARN: recent order update failed (see lines above)" "警告：調整「最近」排序失敗（原因見上面幾行）"
    fi
}

# 開關設定值 → 選單上顯示的文字
onoff_label() {
    if [ "$1" = on ]; then echo "開"; else echo "關"; fi
}

# 依目前狀態重寫 menu.json。
# 為什麼用重寫檔案：config.xml 設了 dynamic="true"，KUAL 每次打開選單都重讀 menu.json，
# 標籤要跟著狀態變只能改檔。"refresh": true 讓 KUAL 在按完後重新載入選單（實機未驗證；
# 沒生效的話，重新打開 KUAL 選單也會看到新標籤）。
render_menu() {
    if session_running; then conn="斷開 calibre 連線"; else conn="連線到 calibre"; fi
    fn="檔名：$(filename_label "$(conf_get filename_chinese traditional)")"
    pin="置頂 Calibre 連線：$(onoff_label "$(conf_get pin_calibre_book on)")"
    kual="KUAL 放最後：$(onoff_label "$(conf_get kual_last on)")"
    cat > "$MENU.tmp" <<EOF
{
  "items": [
    {
      "name": "Calibre Wireless",
      "priority": 1,
      "items": [
        { "name": "$conn", "priority": 1, "action": "./bin/toggle.sh", "exitmenu": false, "refresh": true },
        { "name": "$fn", "priority": 2, "action": "./bin/filename_toggle.sh", "exitmenu": false, "refresh": true },
        { "name": "$pin", "priority": 3, "action": "./bin/pin_toggle.sh", "exitmenu": false, "refresh": true },
        { "name": "$kual", "priority": 4, "action": "./bin/kual_last_toggle.sh", "exitmenu": false, "refresh": true },
        { "name": "Diagnose (write diagnose.txt)", "priority": 5, "action": "./bin/diagnose.sh" }
      ]
    }
  ]
}
EOF
    mv "$MENU.tmp" "$MENU"
}

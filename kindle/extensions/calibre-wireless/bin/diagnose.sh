#!/bin/sh
# calibre-wireless diagnose.sh v0.4.0 — 唯讀，不改任何設定
# 結果寫到使用者區（USB 拿得到）：
#   extensions/calibre-wireless/diagnose.txt         一次性的系統資訊
#   extensions/calibre-wireless/diagnose_events.txt  按下後 EVENT_RECORD_S 秒內的 powerd／wifid／cmd 事件
#     （這段時間內：讓 Kindle 休眠再喚醒一次、切一次 Wi-Fi，才錄得到喚醒與連線事件）
# 用途：確認 session.sh 裡尚未在 5.13.5 實機驗證的指令（防休眠 preventScreenSaver、
# 書庫掃描 doFullScan）與喚醒事件的名稱。
. "$(dirname "$0")/common.sh"

OUT="$BASE/diagnose.txt"
EVENTS="$BASE/diagnose_events.txt"
# 錄事件的時間 (s)
EVENT_RECORD_S=120
# 錄製期間輪詢屬性的間隔 (s)；lipc-wait-event 漏掉事件時靠這個補
POLL_S=3

section() { echo; echo "===== $1 ====="; }

{
    echo "calibre-wireless diagnose v0.4.0  $(date)"

    section "firmware / kernel"
    cat /etc/prettyversion.txt 2>&1
    cat /etc/version.txt 2>&1
    uname -a 2>&1

    section "tools"
    for t in lipc-get-prop lipc-set-prop lipc-wait-event lipc-probe eips fbink iptables mkfifo timeout; do
        printf '%s: ' "$t"; which "$t" 2>/dev/null || echo "(not found)"
    done
    printf 'client: '; ls -l "$CLIENT" 2>&1

    section "powerd properties (lipc-probe -v com.lab126.powerd)"
    lipc-probe -v com.lab126.powerd 2>&1
    section "powerd values"
    for p in preventScreenSaver state status; do
        printf '%s: ' "$p"; lipc-get-prop com.lab126.powerd "$p" 2>&1
    done

    section "scanner properties (lipc-probe -v com.lab126.scanner)"
    lipc-probe -v com.lab126.scanner 2>&1

    section "wireless state"
    printf 'com.lab126.cmd wirelessEnable: '; lipc-get-prop com.lab126.cmd wirelessEnable 2>&1
    printf 'com.lab126.wifid cmState: ';     lipc-get-prop com.lab126.wifid cmState 2>&1
    ifconfig wlan0 2>&1
    section "routes (/proc/net/route)"
    cat /proc/net/route 2>&1

    section "iptables -L INPUT -n -v"
    iptables -L INPUT -n -v 2>&1
    section "iptables -L OUTPUT -n -v"
    iptables -L OUTPUT -n -v 2>&1

    section "session"
    if session_running; then echo "running, pid $(cat "$PIDFILE")"; else echo "not running"; fi
    ps 2>&1 | grep -E 'session\.sh|calibre-wireless' | grep -v grep

    section "calibre-wireless.conf"
    cat "$CONF" 2>&1

    section "calibre-wireless.log (last 60 lines)"
    tail -n 60 "$LOG" 2>&1

    echo; echo "===== end ====="
} > "$OUT" 2>&1

# ---- 背景錄事件：不拖住 KUAL，時間到自動結束 ----
(
    {
        echo "calibre-wireless events v0.4.0  start $(date)"
        echo "Within ${EVENT_RECORD_S}s: put the Kindle to sleep and wake it once, then turn Wi-Fi off and on."
        echo
    } > "$EVENTS"
    # 參數出自 KOReader frontend/device/kindle/device.lua 的註解（知識庫 32 第 7 節）
    lipc-wait-event -m -s 0 -t com.lab126.powerd '*' >> "$EVENTS" 2>&1 &
    w1=$!
    lipc-wait-event -m -s 0 -t com.lab126.wifid '*' >> "$EVENTS" 2>&1 &
    w2=$!
    lipc-wait-event -m -s 0 -t com.lab126.cmd '*' >> "$EVENTS" 2>&1 &
    w3=$!
    # 用次數計時：休眠期間程序凍結，次數只算醒著的時間，喚醒後還會繼續錄
    n=$((EVENT_RECORD_S / POLL_S))
    last=""
    while [ "$n" -gt 0 ]; do
        now="poll powerd.state=$(lipc-get-prop com.lab126.powerd state 2>&1) cmState=$(lipc-get-prop com.lab126.wifid cmState 2>&1) wirelessEnable=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>&1)"
        [ "$now" != "$last" ] && echo "$(date '+%H:%M:%S') $now" >> "$EVENTS"
        last="$now"
        sleep "$POLL_S"
        n=$((n - 1))
    done
    kill "$w1" "$w2" "$w3" 2>/dev/null
    echo >> "$EVENTS"; echo "end $(date)" >> "$EVENTS"
    notify "calibre-wireless: events recorded" 3
) </dev/null >/dev/null 2>&1 &

notify "diagnose.txt written - sleep/wake + toggle Wi-Fi now (2 min)"

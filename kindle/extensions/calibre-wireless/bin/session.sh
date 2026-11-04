#!/bin/sh
# calibre-wireless session.sh v0.8.0
# 一次連線階段，由 toggle.sh 在背景啟動（單一實例：toggle.sh 寫 $PIDFILE）。
#   解除飛行模式 → 等 Wi-Fi 連上（最多 WIFI_WAIT_S）→ 開 INPUT 讓 calibre 的廣播回覆進來
#   → 防休眠 → 跑 Go client → 結束（任何原因）一律：恢復休眠、關 INPUT、回飛行模式、掃描書庫。
# 中途休眠導致連線中斷（client 非 0 結束）：等喚醒後 Wi-Fi 自己連回來，再連一次，最多 RECONNECT_MAX 次。
. "$(dirname "$0")/common.sh"

# Wi-Fi 最多等多久 (s)，逾時放棄（使用者定案 60 s）
WIFI_WAIT_S=60
# 等 Wi-Fi 時的輪詢間隔 (s)。用「次數」計時而不是比較 date：休眠期間程序凍結，
# 牆上時間會跳，次數只算醒著的時間，喚醒後不會被當成已逾時
WIFI_POLL_S=2
# 休眠中斷後最多重連幾次
RECONNECT_MAX=3
# calibre 回覆廣播用的來源埠＝它監聽的 5 個廣播埠（calibre smart_device_app/driver.py BROADCAST_PORTS）
CALIBRE_BROADCAST_PORTS="54982 48123 39001 44044 59678"
# 每個埠最多刪幾次 INPUT 規則（每次重連加一組，RECONNECT_MAX+1 組就夠，多留餘裕）
INPUT_DELETE_MAX=10
FIFO="/tmp/calibre-wireless.fifo"
# 書本數的提示寫在底部第 2 列（狀態那列的上面），不蓋掉狀態
PROGRESS_ROW=2

cpid=""
rpid=""
stopping=0

input_open() {
    for p in $CALIBRE_BROADCAST_PORTS; do
        iptables -I INPUT -i wlan0 -p udp --sport "$p" -j ACCEPT 2>>"$LOG" \
            || log "WARN: iptables INPUT rule for sport $p failed" "警告：INPUT 規則（來源埠 $p）加入失敗"
    done
}

input_close() {
    for p in $CALIBRE_BROADCAST_PORTS; do
        # 重複刪到刪不掉為止：重連時可能加過不只一次。設上限，iptables 行為異常時也不會卡死
        i=0
        while [ "$i" -lt "$INPUT_DELETE_MAX" ] && iptables -D INPUT -i wlan0 -p udp --sport "$p" -j ACCEPT 2>/dev/null; do
            i=$((i + 1))
        done
    done
}

# 防休眠。-i：preventScreenSaver 是整數屬性，不加 -i 會被當字串而設定失敗
# （寫法同使用者機上 Helper+ 的 ssprevent.sh；v0.4.0 漏了 -i）。結果照實寫進 log
sleep_block() {
    if lipc-set-prop -i com.lab126.powerd preventScreenSaver "$1" 2>>"$LOG"; then
        log "preventScreenSaver=$1 ok" "防休眠設定 $1 成功"
    else
        log "WARN: preventScreenSaver=$1 failed" "警告：防休眠設定 $1 失敗"
    fi
}

wifi_state() { lipc-get-prop com.lab126.wifid cmState 2>/dev/null; }

# 等 Wi-Fi CONNECTED；成功回 0，逾時回 1
wait_wifi() {
    n=$((WIFI_WAIT_S / WIFI_POLL_S))
    while [ "$n" -gt 0 ]; do
        [ "$(wifi_state)" = CONNECTED ] && return 0
        [ "$stopping" = 1 ] && return 1
        sleep "$WIFI_POLL_S"
        n=$((n - 1))
    done
    return 1
}

# 網路對時：Kindle 長期飛行模式不對時，時鐘會停住（實測停在 2020-11-01），新書的時間全錯、
# 「最近」排序跟著錯。每次連線順便用 pool.ntp.org（志願者時間伺服器，不是 Amazon）校正，
# 做法同 KOReader 的 timesync 外掛：ntpdate pool.ntp.org → hwclock -u -w（寫回硬體時鐘，重開機不跑掉）。
# 沒有 ntpdate 就用 busybox ntpd -q。需要 kindle-kual-firewall ≥ 1.16（放行 UDP 123）。
# 失敗只記 log，不影響傳書。整段包 timeout，剛開機 DNS 還沒好時不會拖住連線。
NTP_SERVER="pool.ntp.org"
NTP_TIMEOUT_S=20
sync_clock() {
    before="$(date '+%Y-%m-%d %H:%M:%S')"
    if which ntpdate >/dev/null 2>&1; then
        out="$(timeout -t "$NTP_TIMEOUT_S" ntpdate "$NTP_SERVER" 2>&1)"; rc=$?
    elif which ntpd >/dev/null 2>&1; then
        out="$(timeout -t "$NTP_TIMEOUT_S" ntpd -q -n -p "$NTP_SERVER" 2>&1)"; rc=$?
    else
        log "WARN: clock sync skipped, no ntpdate/ntpd" "警告：沒有 ntpdate／ntpd，略過對時"
        return
    fi
    if [ "$rc" = 0 ]; then
        hwclock -u -w 2>>"$LOG"
        log "Clock synced: $before -> $(date '+%Y-%m-%d %H:%M:%S')" "已對時（前後時間見上一行）"
    else
        log "WARN: clock sync failed (rc=$rc): $(echo "$out" | tail -n 1)" "警告：對時失敗（原因見上一行）"
    fi
}

cleanup() {
    [ -n "$cpid" ] && kill "$cpid" 2>/dev/null
    [ -n "$rpid" ] && kill "$rpid" 2>/dev/null
    rm -f "$FIFO"
    sleep_block 0
    input_close
    lipc-set-prop -i com.lab126.cmd wirelessEnable 0 2>>"$LOG"
    # 書庫重新掃描，讓新書出現在首頁。com.lab126.scanner doFullScan 在 5.13.5 尚未實機驗證
    if lipc-set-prop com.lab126.scanner doFullScan 1 2>>"$LOG"; then
        log "Library rescan requested" "已要求重新掃描書庫"
    else
        log "WARN: library rescan (doFullScan) failed" "警告：書庫掃描（doFullScan）失敗"
    fi
    rm -f "$PIDFILE"
    render_menu
    log "Session ended, airplane mode on" "連線結束，已回到飛行模式"
    # 最後一句訊息留幾秒讓使用者看到，再把提示列擦掉（不然會一直殘留在畫面上）
    sleep "$NOTIFY_CLEAR_DELAY_S"
    clear_notify
}

on_term() {
    stopping=1
    [ -n "$cpid" ] && kill "$cpid" 2>/dev/null
}
trap on_term TERM INT

# 跑一次 Go client，回傳它的結束碼。log 逐行轉進 calibre-wireless.log，並把進度畫在螢幕上
run_client() {
    rm -f "$FIFO"
    mkfifo "$FIFO" || { log "ERROR: mkfifo $FIFO failed" "錯誤：無法建立 FIFO"; return 1; }
    # reader 放背景、主程序用 wait 等 client：wait 會被 TERM 打斷，read 不保證
    (
        while IFS= read -r line; do
            echo "$line" >> "$LOG"
            case "$line" in
                *"book "*/*" received"*)
                    nn="$(echo "$line" | sed -n 's/.*book \([0-9]*\/[0-9]*\) received.*/\1/p')"
                    notify "calibre: received $nn" "$PROGRESS_ROW" ;;
                *"connected to calibre"*) notify "calibre: connected" ;;
                *"auto-disconnect"*)      notify "calibre: idle, disconnecting" ;;
            esac
        done < "$FIFO"
    ) &
    rpid=$!
    "$CLIENT" -conf "$CONF" > "$FIFO" 2>&1 &
    cpid=$!
    wait "$cpid"
    rc=$?
    # wait 被 TERM 打斷時回 >128，client 可能還沒真的結束；再等一次拿真正的結束碼
    # 也停掉 reader：client 若留下子程序握著 FIFO，reader 會一直等不到 EOF
    if [ "$stopping" = 1 ]; then wait "$cpid" 2>/dev/null; kill "$rpid" 2>/dev/null; rc=0; fi
    wait "$rpid" 2>/dev/null
    cpid=""; rpid=""
    return "$rc"
}

log "Session start" "開始連線"
render_menu
notify "calibre: turning on Wi-Fi..."
lipc-set-prop -i com.lab126.cmd wirelessEnable 1 2>>"$LOG"

tries=0
while :; do
    if ! wait_wifi; then
        if [ "$stopping" = 1 ]; then notify "calibre: disconnected"; break; fi
        log "Wi-Fi not connected within ${WIFI_WAIT_S}s, giving up" "Wi-Fi ${WIFI_WAIT_S} 秒內沒連上，放棄"
        notify "calibre: Wi-Fi not connected, gave up"
        break
    fi
    log "Wi-Fi connected" "Wi-Fi 已連上"
    # 只在第一次連上時對時（重連時不必再做）
    [ "$tries" = 0 ] && sync_clock
    notify "calibre: searching for calibre..."
    input_open
    sleep_block 1
    run_client
    rc=$?
    log "client exited rc=$rc" "連線程式結束，結束碼 $rc"
    [ "$stopping" = 1 ] && { notify "calibre: disconnected"; break; }
    case "$rc" in
        0) notify "calibre: disconnected"; break ;;
        2) notify "calibre: calibre not found on network"; break ;;
    esac
    # 非 0：連線中斷（多半是休眠時 Wi-Fi 斷掉）。喚醒後 Wi-Fi 會自己連回來，再試
    tries=$((tries + 1))
    if [ "$tries" -gt "$RECONNECT_MAX" ]; then
        notify "calibre: connection lost, gave up"
        break
    fi
    log "Connection lost, reconnect $tries/$RECONNECT_MAX" "連線中斷，第 $tries 次重連"
    notify "calibre: connection lost, reconnecting..."
    input_close
done
cleanup

#!/bin/sh
# calibre-wireless session.sh v0.14.0
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
# 收完最後一本後閒置多久自動斷線 (min)，只用在畫面訊息；實際計時在 Go client（idle.go afterBookTimeout）
AFTER_BOOK_IDLE_MIN=3
# iptables 被別的程序鎖住時（v0.11.0 實機：Wi-Fi 一連上，防火牆插件同時在重建規則
# →「Resource temporarily unavailable」），最多試幾次、每次間隔幾秒 (s)
IPTABLES_TRIES=5
IPTABLES_RETRY_S=1

cpid=""
rpid=""
spid=""
evpids=""
final_msg=""
stopping=0

input_open() {
    for p in $CALIBRE_BROADCAST_PORTS; do
        t=1
        while ! err="$(iptables -I INPUT -i wlan0 -p udp --sport "$p" -j ACCEPT 2>&1)"; do
            if [ "$t" -ge "$IPTABLES_TRIES" ]; then
                log "WARN: iptables INPUT rule for sport $p failed after $t tries: $err" "警告：INPUT 規則（來源埠 $p）試了 $t 次仍加入失敗（原因見上一行）"
                break
            fi
            t=$((t + 1))
            sleep "$IPTABLES_RETRY_S"
        done
        [ "$t" -gt 1 ] && [ "$t" -lt "$IPTABLES_TRIES" ] && log "iptables INPUT rule for sport $p ok on try $t" "INPUT 規則（來源埠 $p）第 $t 次才加入成功"
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
    # 「最近」排序：放在收尾才做——這時點書本按鈕、開 KUAL 寫入的時間早就寫完了；在要求重新掃描之前
    apply_recent_order
    # 書庫重新掃描，讓新書出現在首頁。com.lab126.scanner doFullScan 在 5.13.5 尚未實機驗證
    if lipc-set-prop com.lab126.scanner doFullScan 1 2>>"$LOG"; then
        log "Library rescan requested" "已要求重新掃描書庫"
    else
        log "WARN: library rescan (doFullScan) failed" "警告：書庫掃描（doFullScan）失敗"
    fi
    rm -f "$PIDFILE"
    render_menu
    log "Session ended, airplane mode on" "連線結束，已回到飛行模式"
    # 失敗的原因（找不到 calibre、Wi-Fi 連不上…）留著給使用者看，不蓋成「已斷線」
    [ -n "$final_msg" ] || status_set "calibre: disconnected, airplane mode on" "calibre：已斷線，回到飛行模式"
    # 最後一句留 FINAL_HOLD_S 秒、每秒重畫（結束時書庫會重新啟動蓋掉它），再停掉所有重畫、擦掉
    i=0
    while [ "$i" -lt "$FINAL_HOLD_S" ]; do
        sleep 1
        status_redraw
        i=$((i + 1))
    done
    rm -f "$STATUS_FILE"
    [ -n "$spid" ] && kill "$spid" 2>/dev/null
    # 先殺等待者（讀取端隨之讀到 EOF 結束），再保險殺讀取端
    [ -n "$evpids" ] && kill $evpids 2>/dev/null
    rm -f "$STATUS_EV_FIFO"
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
                *"book "*/*" receiving"*)
                    nn="$(echo "$line" | sed -n 's/.*book \([0-9]*\/[0-9]*\) receiving.*/\1/p')"
                    status_set "calibre: receiving book $nn..." "calibre：接收中 第 $nn 本…" ;;
                *"book "*/*" received"*)
                    nn="$(echo "$line" | sed -n 's/.*book \([0-9]*\/[0-9]*\) received.*/\1/p')"
                    if [ "${nn%/*}" = "${nn#*/}" ]; then
                        status_set "calibre: all ${nn#*/} received, auto-disconnect after $AFTER_BOOK_IDLE_MIN min idle" "calibre：已收到全部 ${nn#*/} 本，閒置 $AFTER_BOOK_IDLE_MIN 分鐘後自動斷線"
                    else
                        status_set "calibre: received book $nn" "calibre：已收到 第 $nn 本"
                    fi ;;
                *"connected to calibre"*) status_set "calibre: connected, waiting for books..." "calibre：已連線，等待 calibre 傳書…" ;;
                *"auto-disconnect"*)      status_set "calibre: idle, disconnecting" "calibre：閒置太久，斷線" ;;
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
status_set "calibre: turning on Wi-Fi..." "calibre：開啟 Wi-Fi 中…"
status_redraw_loop </dev/null >/dev/null 2>&1 &
spid=$!
evpids="$(status_event_redraw_start)"
lipc-set-prop -i com.lab126.cmd wirelessEnable 1 2>>"$LOG"

tries=0
while :; do
    if ! wait_wifi; then
        [ "$stopping" = 1 ] && break
        log "Wi-Fi not connected within ${WIFI_WAIT_S}s, giving up" "Wi-Fi ${WIFI_WAIT_S} 秒內沒連上，放棄"
        status_set "calibre: Wi-Fi not connected, gave up" "calibre：Wi-Fi 連不上，放棄"; final_msg=1
        break
    fi
    log "Wi-Fi connected" "Wi-Fi 已連上"
    # 只在第一次連上時對時（重連時不必再做）
    if [ "$tries" = 0 ]; then
        status_set "calibre: Wi-Fi connected, setting the clock..." "calibre：Wi-Fi 已連上，對時中…"
        sync_clock
    fi
    status_set "calibre: searching for calibre..." "calibre：尋找電腦上的 calibre…"
    input_open
    sleep_block 1
    run_client
    rc=$?
    log "client exited rc=$rc" "連線程式結束，結束碼 $rc"
    [ "$stopping" = 1 ] && break
    case "$rc" in
        0) break ;;
        2) status_set "calibre: calibre not found on network" "calibre：網路上找不到 calibre"; final_msg=1; break ;;
    esac
    # 非 0：連線中斷（多半是休眠時 Wi-Fi 斷掉）。喚醒後 Wi-Fi 會自己連回來，再試
    tries=$((tries + 1))
    if [ "$tries" -gt "$RECONNECT_MAX" ]; then
        status_set "calibre: connection lost, gave up" "calibre：連線中斷，放棄"; final_msg=1
        break
    fi
    log "Connection lost, reconnect $tries/$RECONNECT_MAX" "連線中斷，第 $tries 次重連"
    status_set "calibre: connection lost, reconnecting..." "calibre：連線中斷，重新連線中…"
    input_close
done
cleanup

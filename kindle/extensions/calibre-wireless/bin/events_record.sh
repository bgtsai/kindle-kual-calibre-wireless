#!/bin/sh
# calibre-wireless events_record.sh v0.12.0 — 唯讀，不改任何設定
# 查「按連線就跳出 VoiceView 視窗」（2026-11-14 使用者回報；手動解除飛航模式不會跳，v0.9.3 也會跳
# → 裝置狀態變了，觸發點在我們連線流程裡的某一步）。按下後背景錄 EVENT_RECORD_S 秒，
# 這段時間內使用者去點「Calibre 連線」，把藍牙／VoiceView／介面相關服務的 lipc 事件連同時間記下來，
# 再對照 calibre-wireless.log 每一步的時間，就知道視窗是在哪一步之後出現的。
# 結果：extensions/calibre-wireless/diagnose_connect_events.txt
. "$(dirname "$0")/common.sh"

OUT="$BASE/diagnose_connect_events.txt"
# 錄多久 (s)
EVENT_RECORD_S=60
# 輪詢 Wi-Fi／飛航狀態的間隔 (s)
POLL_S=1
# 要錄的服務：名稱猜的，不存在的 lipc-wait-event 會馬上失敗、錯誤照記（下面的服務清單會列出實際有哪些）
PUBLISHERS="com.lab126.btfd com.lab126.bluetooth com.lab126.voiceview com.lab126.accessibility com.lab126.pillow com.lab126.appmgrd com.lab126.cmd com.lab126.wifid com.lab126.powerd com.lab126.tts com.lab126.audio"

ts() { date '+%H:%M:%S'; }

# 時間到自己結束：busybox 的寫法是 timeout -t N（KB 32 第 7 節），GNU 是 timeout N
if timeout -t 1 true 2>/dev/null; then TO="timeout -t"; else TO="timeout"; fi

(
    {
        echo "calibre-wireless connect events v0.12.0  start $(date)  (date +%s = $(date +%s))"
        echo "Within ${EVENT_RECORD_S}s: tap 'Calibre 連線' (book or KUAL), note when the VoiceView dialog appears."
        echo
        echo "===== lipc publishers (lipc-probe -l / -a) ====="
        lipc-probe -l 2>&1 | head -n 200
        lipc-probe -a 2>&1 | head -n 200
        echo
        echo "===== properties at start ====="
        for p in $PUBLISHERS; do
            echo "--- lipc-probe -v $p"
            lipc-probe -v "$p" 2>&1 | head -n 80
        done
        echo
        echo "===== events (lipc-wait-event -m -s 0 -t <publisher> '*') ====="
    } > "$OUT" 2>&1
    for p in $PUBLISHERS; do
        # 每行前面加上服務名稱，分得出是誰發的
        # 不能事後 killall lipc-wait-event：防火牆插件的背景程序也在用它等 Wi-Fi 事件
        ( $TO "$EVENT_RECORD_S" lipc-wait-event -m -s 0 -t "$p" '*' 2>&1 | while IFS= read -r l; do echo "$(ts) [$p] $l"; done >> "$OUT" ) &
    done
    # 用次數計時（同 diagnose.sh）；狀態有變才記
    n=$((EVENT_RECORD_S / POLL_S))
    last=""
    while [ "$n" -gt 0 ]; do
        now="poll wirelessEnable=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>&1) cmState=$(lipc-get-prop com.lab126.wifid cmState 2>&1) session=$(session_running && echo running || echo stopped)"
        [ "$now" != "$last" ] && echo "$(ts) $now" >> "$OUT"
        last="$now"
        sleep "$POLL_S"
        n=$((n - 1))
    done
    # 各個 lipc-wait-event 由 timeout 自己結束；等它們把最後幾行寫完
    wait
    {
        echo
        echo "===== properties at end ====="
        for p in $PUBLISHERS; do
            echo "--- lipc-probe -v $p"
            lipc-probe -v "$p" 2>&1 | head -n 80
        done
        echo
        echo "===== calibre-wireless.log (last 40 lines) ====="
        tail -n 40 "$LOG" 2>&1
        echo; echo "end $(date)"
    } >> "$OUT" 2>&1
    notify_brief "calibre-wireless: connect events recorded" "calibre-wireless：連線事件錄好了"
) </dev/null >/dev/null 2>&1 &

notify "Recording ${EVENT_RECORD_S}s: now tap Calibre connect" "錄事件 ${EVENT_RECORD_S} 秒：現在去點「Calibre 連線」"

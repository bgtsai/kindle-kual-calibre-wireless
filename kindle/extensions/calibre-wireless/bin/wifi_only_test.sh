#!/bin/sh
# calibre-wireless wifi_only_test.sh v0.14.0 — 測試用：暫時打開 Wi-Fi、測完關回去；不碰飛航模式與藍牙
# 為什麼：使用者的藍牙翻頁器一斷線就要重新配對，藍牙永遠不能斷；但開回飛航模式時 Kindle 一定會關藍牙
# （v0.13.0 錄到：手動或指令切換都一樣，約 6 秒後 BTstateChanged 0）。所以連線不能再切換飛航模式，
# 只能單獨開關 Wi-Fi。飛航模式開著時 com.lab126.wifid enable 是 0、解除後是 1 → 測試在飛航模式下
# 自己把它設成 1，Wi-Fi 連不連得上、飛航模式與藍牙會不會被改。
# 結果：extensions/calibre-wireless/diagnose_wifi_only.txt
. "$(dirname "$0")/common.sh"

OUT="$BASE/diagnose_wifi_only.txt"
# 開著 Wi-Fi 最多等多久連上 (s)
ON_WAIT_S=40
# 關回去之後再記錄多久 (s)
OFF_WATCH_S=10
if timeout -t 1 true 2>/dev/null; then TO="timeout -t"; else TO="timeout"; fi

if session_running; then
    notify_brief "calibre-wireless: disconnect first" "請先斷開 calibre 連線再測"
    exit 0
fi

ts() { date '+%H:%M:%S'; }
state() {
    echo "$(ts) wirelessEnable=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>&1) wifid.enable=$(lipc-get-prop com.lab126.wifid enable 2>&1) cmState=$(lipc-get-prop com.lab126.wifid cmState 2>&1) BTstate=$(lipc-get-prop com.lab126.btfd BTstate 2>&1) BTmode=$(lipc-get-prop com.lab126.btfd currentBTOperatingMode 2>&1) wlan0=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')"
}

(
    total=$((ON_WAIT_S + OFF_WATCH_S + 5))
    {
        echo "calibre-wireless Wi-Fi-only test v0.14.0  start $(date)"
        echo "--- before"; state
    } > "$OUT" 2>&1
    for p in com.lab126.cmd com.lab126.wifid com.lab126.btfd com.lab126.btmd; do
        ( $TO "$total" lipc-wait-event -m -s 0 -t "$p" '*' 2>&1 | while IFS= read -r l; do echo "$(ts) [$p] $l"; done >> "$OUT" ) &
    done
    sleep 1
    echo "$(ts) >>> lipc-set-prop -i com.lab126.wifid enable 1" >> "$OUT"
    lipc-set-prop -i com.lab126.wifid enable 1 >> "$OUT" 2>&1; echo "rc=$?" >> "$OUT"
    n=0; last=""
    while [ "$n" -lt "$ON_WAIT_S" ]; do
        now="$(state)"; [ "${now#* }" != "$last" ] && echo "$now" >> "$OUT"; last="${now#* }"
        case "$now" in *cmState=CONNECTED*) echo "$(ts) connected after ${n}s" >> "$OUT"; sleep 3; break ;; esac
        sleep 1; n=$((n + 1))
    done
    { echo "--- just before turning off"; state; } >> "$OUT"
    echo "$(ts) >>> lipc-set-prop -i com.lab126.wifid enable 0" >> "$OUT"
    lipc-set-prop -i com.lab126.wifid enable 0 >> "$OUT" 2>&1; echo "rc=$?" >> "$OUT"
    n=0; last=""
    while [ "$n" -lt "$OFF_WATCH_S" ]; do
        now="$(state)"; [ "${now#* }" != "$last" ] && echo "$now" >> "$OUT"; last="${now#* }"
        sleep 1; n=$((n + 1))
    done
    wait
    { echo "--- after"; state; echo; echo "end $(date)"; } >> "$OUT" 2>&1
    notify_brief "calibre-wireless: Wi-Fi test done" "Wi-Fi 測試完成，請把 diagnose_wifi_only.txt 傳出來"
) </dev/null >/dev/null 2>&1 &

notify "Wi-Fi-only test (about 1 min): keep the page turner connected" "只開 Wi-Fi 測試（約 1 分鐘）：請保持翻頁器連著"

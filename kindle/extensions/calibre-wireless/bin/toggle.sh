#!/bin/sh
# calibre-wireless toggle.sh v0.11.0
# KUAL「連線／斷線」與書本按鈕共用：沒在連線 → 背景啟動 session.sh；連線中 → 結束它。
# 一定要馬上返回：KUAL 與 scriptlet 會等腳本結束，連線階段要跑好幾分鐘。
. "$(dirname "$0")/common.sh"

if session_running; then
    log "Disconnect requested" "使用者要求斷線"
    notify "calibre: disconnecting..." "calibre：斷線中…"
    # session.sh 收到 TERM 會自己收尾（關 Go 程式、恢復飛行模式、掃描書庫、重畫選單）
    kill "$(cat "$PIDFILE")" 2>/dev/null
    exit 0
fi

rm -f "$PIDFILE"
# </dev/null 與輸出導走：KUAL 結束後背景程序不能綁著它的終端
sh "$BASE/bin/session.sh" </dev/null >/dev/null 2>&1 &
echo $! > "$PIDFILE"
render_menu

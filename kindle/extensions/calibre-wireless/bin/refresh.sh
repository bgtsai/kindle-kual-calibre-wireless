#!/bin/sh
# calibre-wireless refresh.sh v0.16.0
# 「重新整理（封面與排序）」：KUAL 子選單與書本按鈕「重新整理」共用。
# 1. 讓書庫重讀兩本書本按鈕的封面：sh_integration 只在一本 .sh「被登記進書庫」時讀一次
#    # Icon:（解到 <檔名>.sdr/），之後就固定了。所以把兩本移出 documents → 掃描（書庫刪掉那兩筆）
#    → 移回 → 掃描（重新登記、重讀封面）。.sdr 先刪掉，免得留著舊封面。
# 2. 重新排序：apply_recent_order（Calibre 連線最前、KUAL 最後、重新整理在 KUAL 後面）。
# 實機未驗證：移出／移回＋doFullScan 能不能觸發刪除與重新登記、要等多久 → 每一步都寫 log，
# 用輪詢 cc.db 等結果，等不到就寫明停在哪一步。
# 一定要馬上返回（KUAL 與 scriptlet 會等腳本結束）：真正的工作在背景跑。
. "$(dirname "$0")/common.sh"

# 等書庫刪掉／登記那兩筆，最多幾秒 (s)；每秒查一次 cc.db
REFRESH_SCAN_WAIT_S=60
# 移出去暫放的地方：同一個分割區（mv 不用複製），但不在 documents 裡（書庫不掃）
REFRESH_STASH="/mnt/us/.calibre-wireless-refresh"
# 排序前先等幾秒 (s)：從 KUAL 按的話，KUAL 關掉時會把自己的時間改回「現在」；
# 從書本按鈕按的話，那一筆會在點下時被重建（v0.9.3 實機）。等這些寫完再排。
REFRESH_ORDER_DELAY_S=5
REFRESH_PIDFILE="/var/run/calibre-wireless-refresh.pid"

# 兩本都不在書庫（want=gone）或都在（want=present）就回 0
books_state_is() {
    for p in "$BOOK_BUTTON_PATH" "$REFRESH_BOOK_PATH"; do
        [ -f "$p" ] || [ -f "$REFRESH_STASH/$(basename "$p")" ] || continue   # 檔案本來就沒有的不算
        u="$(ccdb_uuid "$p")"
        if [ "$1" = gone ]; then [ -z "$u" ] || return 1; else [ -n "$u" ] || return 1; fi
    done
    return 0
}

scan_and_wait() {
    lipc-set-prop com.lab126.scanner doFullScan 1 2>>"$LOG" \
        || log "WARN: doFullScan failed" "警告：書庫掃描（doFullScan）失敗"
    i=0
    while [ "$i" -lt "$REFRESH_SCAN_WAIT_S" ]; do
        books_state_is "$1" && { log "Library: books $1 after ${i} s" "書庫：$i 秒後兩本已$( [ "$1" = gone ] && echo 移除 || echo 登記)"; return 0; }
        sleep 1; i=$((i + 1))
    done
    log "WARN: library did not show books $1 within $REFRESH_SCAN_WAIT_S s" "警告：$REFRESH_SCAN_WAIT_S 秒內書庫沒有$( [ "$1" = gone ] && echo 移除 || echo 登記)那兩本"
    return 1
}

refresh_run() {
    notify "Refreshing covers and order..." "重新整理封面與排序中…"
    log "Refresh start" "開始重新整理（封面與排序）"
    mkdir -p "$REFRESH_STASH"
    moved=""
    for p in "$BOOK_BUTTON_PATH" "$REFRESH_BOOK_PATH"; do
        [ -f "$p" ] || { log "Refresh: $p not found, skipped" "重新整理：找不到 $p，略過"; continue; }
        rm -rf "$p.sdr"
        mv "$p" "$REFRESH_STASH/" && moved="$moved
$p"
    done
    if [ -n "$moved" ]; then
        # 沒等到「移除」＝書庫沒刪掉舊的那筆，移回後也不會重讀封面 → 不算成功
        scan_and_wait gone && gone_ok=1
        # 不管有沒有等到都要移回去：書本按鈕不能留在外面
        echo "$moved" | while IFS= read -r p; do
            [ -n "$p" ] && mv "$REFRESH_STASH/$(basename "$p")" "$p"
        done
        scan_and_wait present && [ -n "$gone_ok" ] && cover_ok=1
    fi
    rmdir "$REFRESH_STASH" 2>/dev/null
    sleep "$REFRESH_ORDER_DELAY_S"
    apply_recent_order
    if [ -n "$cover_ok" ]; then
        log "Refresh done" "重新整理完成"
        notify_brief "Covers and order refreshed" "封面與排序已重新整理"
    else
        log "Refresh finished with warnings (see above)" "重新整理結束，但有警告（見上面幾行）"
        notify_brief "Refresh: see calibre-wireless.log" "重新整理：有問題，請看 calibre-wireless.log"
    fi
    rm -f "$REFRESH_PIDFILE"
}

if [ -f "$REFRESH_PIDFILE" ] && kill -0 "$(cat "$REFRESH_PIDFILE")" 2>/dev/null; then
    notify_brief "Refresh already running" "重新整理已在進行中"
    exit 0
fi
if session_running; then
    # 連線中會收書、掃描書庫，移動書本按鈕可能打斷使用者斷線
    notify_brief "Disconnect from calibre first" "請先斷開 calibre 連線再重新整理"
    exit 0
fi
refresh_run </dev/null >/dev/null 2>&1 &
echo $! > "$REFRESH_PIDFILE"
exit 0

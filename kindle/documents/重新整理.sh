#!/bin/sh
# Name: 重新整理
# Author: bgtsai
# Icon: /mnt/us/extensions/calibre-wireless/cover_refresh.png
# DontUseFBInk
#
# calibre-wireless 書本按鈕 v0.16.0：重讀「Calibre 連線」與這本的封面，再把「最近」排序調回來
# （Calibre 連線最前、KUAL 最後、這本在 KUAL 後面）。跟 KUAL 子選單「重新整理（封面與排序）」同一支腳本。
REFRESH=/mnt/us/extensions/calibre-wireless/bin/refresh.sh
if [ -f "$REFRESH" ]; then
    sh "$REFRESH"
else
    which eips >/dev/null 2>&1 && eips 2 2 "calibre-wireless extension not installed        " >/dev/null 2>&1
fi

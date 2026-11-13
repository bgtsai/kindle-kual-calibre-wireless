#!/bin/sh
# Name: Calibre 連線
# Author: bgtsai
# Icon: /mnt/us/extensions/calibre-wireless/cover_connect.png
# DontUseFBInk
#
# calibre-wireless 書本按鈕 v0.16.0（Universal Hotfix 的 sh_integration：documents/*.sh 會顯示成一本書）
# 點一下＝連線到 calibre，再點一下＝斷線，跟 KUAL 選單的「連線／斷線」是同一支腳本。
# 書名不能隨狀態改變，所以狀態用畫面提示（toggle.sh 自己畫）。
# DontUseFBInk：不要讓 hotfix 幫我們顯示輸出，訊息由 toggle.sh 用 eips 畫。
# 這本「書」不會出現在 calibre 的書單裡：client 只列 calibre 傳過來的書。
TOGGLE=/mnt/us/extensions/calibre-wireless/bin/toggle.sh
if [ -x "$TOGGLE" ] || [ -f "$TOGGLE" ]; then
    sh "$TOGGLE"
else
    which eips >/dev/null 2>&1 && eips 2 2 "calibre-wireless extension not installed        " >/dev/null 2>&1
fi

[Switch to English](README.md)

# kindle-kual-calibre-wireless

給已越獄 Kindle 用的 KUAL 插件。裝了以後，電腦上的 calibre 用「連線/分享 → 啟動無線裝置連線」就能透過 Wi-Fi 找到 Kindle，像接 USB 一樣傳書、刪書——不需要 KOReader，書用 Kindle 原生閱讀器開。

- Kindle 首頁封面縮圖，寫法跟 calibre 的 USB 驅動一樣
- 每本書一個資料夾：`documents/<書名>/<書名> - <作者>.<副檔名>`，Kindle 建的 `.sdr` 也收在裡面；在 calibre 刪書會連資料夾一起刪
- 中文檔名：calibre 一律把檔名轉成拼音；這個插件改用「書名 - 作者」存檔，可選繁體、簡體或跟 calibre 裡一樣
- 自動處理飛行模式：按連線時開 Wi-Fi，結束後回到飛行模式
- 會自己結束：連上後 5 分鐘沒傳書、最後一本傳完 3 分鐘、或在 calibre 按「退出」時
- 連線中不讓 Kindle 休眠；萬一休眠了，喚醒後自動重連

> **狀態：** v0.5.0。協定、計時與檔名已在雲端對 calibre 7.6 測過；**還沒在實機 Kindle 上測。** 針對 Kindle Oasis 2、韌體 5.13.5 撰寫，其他機型可能要調整，見[請 AI 幫你改成適合你的 Kindle](#請-ai-幫你改成適合你的-kindle)。

## 需要的東西

- 已**越獄**、裝好 **KUAL** 的 Kindle
- 書本按鈕需要 **Universal Hotfix** 的 shell 腳本整合（書庫裡看得到 KOReader 這本「書」就是有）。KUAL 選單不需要它。
- 同一個 Wi-Fi 網路裡、裝了 calibre 的電腦
- 如果有用 [kindle-kual-firewall](https://github.com/bgtsai/kindle-kual-firewall)：要 **1.9 以上**（放行 calibre 的搜尋廣播）

## 安裝

1. 到 [Releases](../../releases/latest) 下載 **`calibre-wireless.zip`**（不要用 GitHub 綠色的「Code → Download ZIP」，那是原始碼）。
2. 解壓縮，裡面有兩個資料夾：`extensions` 和 `documents`。
3. 用 USB 接上 Kindle，把**兩個**資料夾都複製到 Kindle 磁碟的**根目錄**，讓電腦跟既有的資料夾**合併**——你的書和其他插件不會受影響。
4. 退出 Kindle。打開 KUAL 應該會看到 **Calibre Wireless**；書庫裡會多一本叫 **Calibre 連線** 的「書」。

更新：把新 zip 的內容照同樣方式蓋過去。注意檔名設定會回到「繁體」（設定存在 `calibre-wireless.conf`，它在 zip 裡）。

## 使用方式

1. calibre：**連線/分享 → 啟動無線裝置連線**（做一次就好，calibre 會記住）。
2. Kindle：點書庫裡的 **Calibre 連線**，或 KUAL ▸ Calibre Wireless ▸ **連線到 calibre**。
3. 畫面上方會出現狀態訊息：`turning on Wi-Fi…`、`searching for calibre…`、`connected`、`received 1/3`…
4. calibre 裡會出現 **Wireless device: Kindle**，照平常傳書、刪書。
5. 結束：在 calibre 按退出、再點一次書本按鈕／選單，或等它自動結束（見上方計時）。Kindle 會回到飛行模式並重新掃描書庫。

## 選單

KUAL ▸ **Calibre Wireless**：

| 項目 | 作用 |
| --- | --- |
| 連線到 calibre／斷開 calibre 連線 | 連線／斷線（標籤顯示目前狀態） |
| 檔名：繁體／簡體／原樣 | 之後收到的書的檔名：繁體、簡體、跟 calibre 一樣。點一下輪替。已在 Kindle 上的書不會改名。 |
| Diagnose | 寫出 `diagnose.txt` 並錄 2 分鐘事件（見下方） |

## 會產生的檔案

| 檔案 | 內容 |
| --- | --- |
| `extensions/calibre-wireless/calibre-wireless.log` | 每次連線的紀錄（英文，附中文行） |
| `extensions/calibre-wireless/calibre-wireless.conf` | 設定（`filename_chinese=traditional/simplified/original`） |
| `documents/.calibre-wireless.json` | calibre 傳過哪些書，讓 calibre 的「在裝置上」欄位重連後還在 |
| `system/thumbnails/thumbnail_*_portrait.jpg` | 首頁封面；備份在 `amazon-cover-bug/` |

## 已知限制

- 還沒在實機上測。以下指令在韌體 5.13.5 上未驗證，用 Diagnose 確認：防休眠（`com.lab126.powerd preventScreenSaver`）、重新掃描書庫（`com.lab126.scanner doFullScan`）。
- 畫面訊息是英文：Kindle 的 `eips` 只能畫 ASCII。
- KFX 檔還沒有首頁縮圖。
- 剛開機的幾分鐘 Kindle 可能沒有網路路由；這時搜尋 calibre 會改用子網路廣播位址（例如 `192.168.1.255`）。

## 移除

刪掉 `extensions/calibre-wireless/` 和 `documents/Calibre 連線.sh`；需要的話也刪 `documents/.calibre-wireless.json`。

## 請 AI 幫你改成適合你的 Kindle

### 第 1 步：收集資料

1. KUAL ▸ Calibre Wireless ▸ **Diagnose**。
2. 2 分鐘內：按電源鍵讓 Kindle 休眠、再喚醒，然後把 Wi-Fi 關掉再打開。
3. 2 分鐘過後，用 USB 複製出 `extensions/calibre-wireless/diagnose.txt` 和 `diagnose_events.txt`。裡面沒有帳號資料，分享前還是先看一下。

### 第 2 步：交給 AI

開一個新對話，附上 `calibre-wireless.zip`、`diagnose.txt`、`diagnose_events.txt`，貼上：

```
我在越獄的 Kindle 上用 KUAL 插件「kindle-kual-calibre-wireless」（https://github.com/bgtsai/kindle-kual-calibre-wireless）。附件是插件 zip 和我 Kindle 上的 diagnose.txt／diagnose_events.txt。

請先讀 repo 裡的 CLAUDE.md（「Model-specific parts」那張表），再檢查我的檔案：
- 「powerd properties」：有沒有 preventScreenSaver？沒有的話，我的 Kindle 要怎麼防休眠？
- 「scanner properties」：有沒有 doFullScan？
- diagnose_events.txt：com.lab126.powerd 的休眠／喚醒事件叫什麼？Wi-Fi 事件呢？
- 「tools」：有沒有 eips、mkfifo、iptables？
- 「calibre-wireless.log」：上一次連線有沒有找到 calibre、收到書？

動手前先告訴我要改什麼、為什麼。然後給我結構一樣的新 calibre-wireless.zip，config.xml 的版本號要遞增。

我的問題：<描述發生什麼事>
```

## 從原始碼編譯

```
cd src && GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o ../kindle/extensions/calibre-wireless/bin/calibre-wireless .
```

再把 `kindle/` 的內容壓成 zip。GitHub Actions 在每次推送改到 `config.xml` 版本號時就是這樣做。

## 參考

- [UNCaGED](https://github.com/shermp/UNCaGED)：calibre Smart Device App 協定的 Go 實作（放在 `src/third_party/UNCaGED`，有兩處小修改，程式碼裡有標註）
- calibre `src/calibre/devices/smart_device_app/driver.py`（協定）與 `devices/kindle/driver.py`（縮圖檔名）
- KOReader `platform/kindle/koreader.sh`（為 calibre 的回覆開防火牆）

## 授權

GPL-3.0（UNCaGED 是 GPL-3.0）。

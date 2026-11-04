[Switch to English](README.md)

# kindle-kual-calibre-wireless

給已越獄 Kindle 用的 KUAL 插件。裝了以後，電腦上的 calibre 用「連線/分享 → 啟動無線裝置連線」就能透過 Wi-Fi 找到 Kindle，像接 USB 一樣傳書、刪書——不需要 KOReader，書用 Kindle 原生閱讀器開。

- **首頁封面縮圖**，寫法跟 calibre 的 USB 驅動一樣
- **每本書一個資料夾**：`documents/<書名>/<書名> - <作者>.<副檔名>`，Kindle 建的 `.sdr` 資料夾也收在裡面。在 calibre 刪書會連資料夾一起刪。
- **中文檔名**：calibre 一律把檔名轉成拼音；這個插件改用「書名 - 作者」存檔，可選繁體、簡體或跟 calibre 裡一樣
- **自動處理飛行模式**：按連線時開 Wi-Fi，結束後回到飛行模式
- **會自己結束**：連上後 5 分鐘沒傳書、最後一本傳完 3 分鐘、或在 calibre 按「退出」時
- **連線中不休眠**；萬一休眠了，喚醒後自動重連
- **USB 傳的書也看得到**：calibre 的裝置清單會列出它們（讀 calibre USB 驅動留在 Kindle 上的 `metadata.calibre`），從無線刪掉時也會同步移除那份紀錄
- **兩種啟動方式**：KUAL 選單，或點書庫裡的一本「書」（需要 Universal Hotfix，見[需要的東西](#需要的東西)）

> **實測機型：** Kindle Oasis 2、韌體 5.13.5（核心 4.1.15），搭配 calibre 7.6——KUAL 連線、收書、書庫書本按鈕都測過。其他機型可能要調整，見[請 AI 幫你改成適合你的 Kindle](#請-ai-幫你改成適合你的-kindle)。

## 需要的東西

- 已**越獄**、裝好 **KUAL** 的 Kindle
- **同一個 Wi-Fi 網路**裡、裝了 calibre 的電腦（不能是訪客網路，也不能是開了「AP 隔離／用戶端隔離」的路由器，那會擋掉搜尋用的廣播）
- 只有書庫書本按鈕需要：[KindleModding 的 Universal Hotfix](https://github.com/KindleModding/Hotfix)（它的 sh_integration 會讓 `documents/` 裡的 `.sh` 變成書）。書庫裡有 **Run Hotfix** 這本書就是有裝。KUAL 選單不需要它。安裝方式見[安裝 Universal Hotfix](#安裝-universal-hotfix)。
- 如果有用 [kindle-kual-firewall](https://github.com/bgtsai/kindle-kual-firewall)：要 **1.9 以上**（放行 calibre 的搜尋廣播）；要對時則需 **1.16 以上**

## 安裝

1. 下載 **[calibre-wireless.zip](../../releases/latest/download/calibre-wireless.zip)**（最新版）。
   （不要用 GitHub 綠色的「Code → Download ZIP」，那是原始碼，資料夾結構不一樣。）
2. 解壓縮，裡面有**兩個資料夾**：`extensions` 和 `documents`。
3. 用 USB 接上 Kindle，把**兩個**資料夾都複製到 Kindle 磁碟的**根目錄**（原本 `documents` 所在的那一層），讓電腦跟既有的資料夾**合併**——你的書和其他插件不會受影響。
4. 退出 Kindle。打開 KUAL 應該會看到 **Calibre Wireless**；有裝 Universal Hotfix 的話，書庫裡會多一本叫 **Calibre 連線** 的書。

不需要重開機。

**更新：** 把新 zip 的內容照同樣方式蓋過去。檔名設定會回到「繁體」（設定存在 `calibre-wireless.conf`，它在 zip 裡）。

### Kindle 上的結構一定要長這樣

```
Kindle 磁碟（根目錄）
├── documents/
│   └── Calibre 連線.sh            ← 書庫裡的書本按鈕
└── extensions/
    └── calibre-wireless/          ← 資料夾名稱必須是 calibre-wireless
        ├── config.xml
        ├── menu.json
        ├── calibre-wireless.conf
        └── bin/
            ├── calibre-wireless   ← 主程式
            ├── common.sh
            ├── toggle.sh
            ├── session.sh
            ├── filename_toggle.sh
            └── diagnose.sh
```

常見錯誤：

| 錯誤的放法 | 為什麼不行 |
| --- | --- |
| Kindle 上變成 `calibre-wireless/extensions/calibre-wireless/...` | 解壓縮工具多建了一層跟 zip 同名的資料夾。要把它**裡面**的東西複製到 Kindle 根目錄。 |
| `extensions/calibre-wireless/calibre-wireless/config.xml` | 多了一層，KUAL 找不到。 |
| `Calibre 連線.sh` 放在磁碟根目錄 | 一定要放在 `documents/` 裡，否則不會變成書。 |

## 使用方式

1. calibre：**連線/分享 → 啟動無線裝置連線**。密碼**留空**（插件不會送密碼），埠號維持預設。做一次就好，calibre 會記住。
2. Kindle：點書庫裡的 **Calibre 連線**，或 KUAL ▸ Calibre Wireless ▸ **連線到 calibre**。
3. 畫面**底部**會出現狀態訊息：`turning on Wi-Fi…`、`searching for calibre…`、`connected`、`received 1/3`…可以先在 Kindle 按連線、再去開 calibre——Kindle 會持續尋找最多 5 分鐘。
4. calibre 裡會出現 **Wireless device: Kindle**，照平常傳書、刪書。
5. 結束：在 calibre 按退出、再點一次書本／選單，或等它自動結束（見上方計時）。Kindle 會回到飛行模式並重新掃描書庫。

### calibre 找不到 Kindle（`calibre not found on network`）

- **電腦的防火牆**：calibre 要收 UDP 54982、48123、39001、44044、59678 與 TCP 9090。Windows 要允許 calibre 通過**私人**網路（Windows 安全性 → 防火牆 → 允許應用程式通過防火牆），網路設定檔要是「私人」不是「公用」。
- **同一個網路**：電腦和 Kindle 接同一台路由器；不能是訪客 Wi-Fi，不能開用戶端隔離。
- 還是不行，回報問題時附上 `extensions/calibre-wireless/calibre-wireless.log`。

## 選單

全部放在 KUAL 的一個項目底下：

```
Calibre Wireless ▸
    連線到 calibre  /  斷開 calibre 連線
    檔名：繁體  /  簡體  /  原樣
    Diagnose (write diagnose.txt)
```

| 項目 | 作用 |
| --- | --- |
| **連線到 calibre／斷開 calibre 連線** | 連線／斷線，標籤顯示目前狀態。跟點書庫的 **Calibre 連線** 一樣。 |
| **檔名：繁體／簡體／原樣** | 之後收到的書的檔名與資料夾名：繁體、簡體、跟 calibre 一樣。點一下輪替。已在 Kindle 上的書不會改名。連線中改設定，下次連線才生效。 |
| **Diagnose** | 把系統資訊寫到 `diagnose.txt`（只讀，不改任何東西）。接著在背景錄 2 分鐘電源與 Wi-Fi 事件到 `diagnose_events.txt`——這段時間內讓 Kindle 休眠再喚醒一次，然後把 Wi-Fi 關掉再打開。用來排查問題，或改成適合其他機型。 |

## 一次連線會做什麼

1. 解除飛行模式，最多等 **60 秒** Wi-Fi 連上（等不到就放棄、回到飛行模式）。
2. 用 `pool.ntp.org`（公開的志願者時間伺服器，不是 Amazon；做法同 KOReader 的對時外掛）校正 Kindle 時鐘——長期飛行模式的 Kindle 從不對時，時鐘會停住，「最近」排序也會跟著錯。失敗只記 log。
3. 連線期間在 Kindle 自己的防火牆（`iptables INPUT`）開一個口給 calibre 的回覆——只收**來自** calibre 那 5 個廣播埠的 UDP。
4. 防止休眠（`com.lab126.powerd preventScreenSaver`）。
5. 廣播尋找 calibre，每幾秒重試一次、最多 **5 分鐘**（剛開機時 `255.255.255.255` 送不出去的話，改用你網段的廣播位址，例如 `192.168.1.255`），再用 TCP 跟它連線。
6. 連線中斷（多半是 Kindle 休眠了）就等 Wi-Fi 回來再重連，最多 3 次。
7. 結束時不管原因：恢復休眠、移除防火牆規則、回到飛行模式、重新掃描書庫。最後一句訊息停留 4 秒，然後把提示列擦掉。

### 各步驟等多久

下表任何一種情況結束連線，Kindle 都會回到飛行模式。

| 步驟 | 時間 | 時間到了會怎樣 |
| --- | --- | --- |
| 等 Wi-Fi 連上 | **60 秒** | 放棄：`Wi-Fi not connected, gave up` |
| 尋找 calibre | **5 分鐘**（每幾秒重試一次） | 放棄：`calibre not found on network` |
| 連上了，但一直沒傳書 | **5 分鐘** | 斷線 |
| 最後一本傳完（或刪完書）之後 | 閒置 **3 分鐘** | 斷線。每傳一本或刪一本，都會重新倒數 3 分鐘。 |
| 在 calibre 按退出 | 立即 | 斷線 |
| 連線中斷（例如 Kindle 休眠） | 最多重連 **3** 次，每次等 Wi-Fi 60 秒 | 放棄：`connection lost, gave up` |

等待時間只算醒著的時間：休眠期間不會用掉。另外兩個時間限制來自 UNCaGED 函式庫，平常碰不到：calibre 60 秒完全沒回應算連線中斷；傳一本書每 100 KB 給 2 秒。5 分鐘、3 分鐘（和搜尋時間）是程式的啟動參數（`-search-timeout`、`-no-book-timeout`、`-idle-timeout`），選單沒有提供修改。

## 會產生的檔案

| 檔案 | 位置（USB 磁碟上） | 用途 |
| --- | --- | --- |
| `calibre-wireless.log` | `extensions/calibre-wireless/` | 每次連線的每一步。超過約 200 KB 會自動裁短。 |
| `calibre-wireless.conf` | `extensions/calibre-wireless/` | 設定（`filename_chinese=traditional/simplified/original`）。在 zip 裡，選單會改寫它。 |
| `metadata.calibre` | 磁碟根目錄 | 不是這個插件建的，是 calibre 的 USB 驅動寫的。讀它來列出 USB 傳的書；從無線刪掉的書會移除那一筆。不是透過 calibre 放進 Kindle 的書，兩份清單都沒有，不會出現。 |
| `.calibre-wireless.json` | `documents/` | calibre 傳過哪些書、各自的檔名，讓 calibre 的「在裝置上」欄位重連後還在。隱藏檔。 |
| `thumbnail_*_portrait.jpg` | `system/thumbnails/` | 首頁封面。備份在 `amazon-cover-bug/`，Kindle 刪掉的話每次連線會補回來。 |
| `diagnose.txt`、`diagnose_events.txt` | `extensions/calibre-wireless/` | **Diagnose** 的結果。 |

### 確認有沒有正常運作

連線一次之後，打開 `extensions/calibre-wireless/calibre-wireless.log`，應該會看到：

```
2026-11-04 23:15:24  Session start
                     Chinese | 開始連線
2026-11-04 23:15:24  Wi-Fi connected
                     Chinese | Wi-Fi 已連上
2026-11-04 23:15:24  preventScreenSaver=1 ok
                     Chinese | 防休眠設定 1 成功
2026/11/04 23:15:25 found 1 calibre instance(s), using MyPC at 192.168.1.20
2026/11/04 23:15:26 connected to calibre
2026/11/04 23:15:26 book 1/2 received
2026/11/04 23:15:26 book 2/2 received
2026/11/04 23:18:26 auto-disconnect: idle after last book for 3m0s
2026-11-04 23:18:26  Session ended, airplane mode on
                     Chinese | 連線結束，已回到飛行模式
```

日期用 `-` 的是腳本寫的，每筆寫兩行：英文一行，下一行縮排、以 `Chinese |` 開頭的是同一句中文。日期用 `/` 的是主程式寫的，只有英文。`WARN:` 開頭的行會告訴你哪一步失敗（例如 `preventScreenSaver=1 failed`）。

## 已知限制

- **畫面訊息是英文**：訊息是直接畫在螢幕上的（FBInk，沒裝 Universal Hotfix 時用 `eips`），這裡只能畫 ASCII。
- **擦掉後會留一條空白，等 Kindle 重畫才恢復**：訊息改的是螢幕像素，Kindle 介面不知道。結束時會擦掉，但那幾列原本的介面內容（例如閱讀進度那一行）要等介面重畫（翻頁、開書）才會回來。沒有查到能讓介面「只重畫、不切換畫面」的指令。訊息用 FBInk 畫（Universal Hotfix 附帶）；FBInk 不存在或執行失敗時，改用 `eips` 畫在靠近底部的位置（它的列高是估計值，位置可能略有不同），那一列被拒畫就畫在頂端。FBInk 失敗會在 log 記一次（`WARN: fbink failed`）。
- **對時需要 Wi-Fi 能連到 `pool.ntp.org`**（UDP 123；kindle-kual-firewall 1.16 以上會放行）。剛開機的幾分鐘 Kindle 可能還沒有 DNS，那次連線可能對時失敗，log 會寫 `clock sync failed`。
- **KFX 檔**還沒有首頁縮圖。
- **更新會重設設定**：蓋過新 zip 會覆蓋 `calibre-wireless.conf`。
- **不支援密碼**：calibre 的無線連線密碼要留空。

## 安裝 Universal Hotfix

只有書庫書本按鈕需要。官方說明是 [KindleModding – Setting up a Hotfix](https://kindlemodding.org/jailbreaking/Legacy/post-jailbreak/setting-up-a-hotfix/)；以下是實測機上成功的做法：

1. 下載 [Update_hotfix_universal.bin](https://github.com/KindleModding/Hotfix/releases/latest/download/Update_hotfix_universal.bin)。
2. **先在電腦上把副檔名 `.bin` 拿掉**，複製到 Kindle 根目錄，**再在 Kindle 磁碟上**改回 `Update_hotfix_universal.bin`。帶著副檔名直接複製的話，Kindle 可能在檔案還沒複製完時就把它收走（USB 一直斷線、檔案被改名成 `update-18446744073709551615-<id>.bin`），之後更新會跳錯誤畫面。
3. 如果有用 `update.bin.tmp.partial` 資料夾或 KUAL 的 *Rename OTA Binaries* 擋更新，先解除（資料夾改名／按 **Restore**），裝完再封回去。
4. 退出 USB，設定 ▸ ⋮ ▸ **更新您的 Kindle**。裝完點書庫裡的 **Run Hotfix**。

**不要**用 MRPI（KUAL ▸ Install MR Packages）裝：在從沒裝過 Hotfix 的 Kindle 上，Hotfix 2.x 用 MRPI 一定會失敗（`/var/local/kmc/armel/bin/fbink: not found`，回傳碼 127）。失敗時不會改動任何東西。

## 移除

用 USB 刪掉 `extensions/calibre-wireless/` 和 `documents/Calibre 連線.sh`；需要的話也刪 `documents/.calibre-wireless.json`。已經收到的書留在原處。

## 請 AI 幫你改成適合你的 Kindle

有些指令跟 Kindle 型號、韌體有關。就算不會寫程式，也可以請 AI 助理（Claude、ChatGPT 等）幫你改。

### 第 1 步：從 Kindle 收集資料

1. 先連線一次（calibre 啟動無線連線，再從 Kindle 連線）。
2. KUAL ▸ Calibre Wireless ▸ **Diagnose**。2 分鐘內：按電源鍵讓 Kindle 休眠、再喚醒，然後把 Wi-Fi 關掉再打開。
3. 2 分鐘過後，用 USB 複製出 `extensions/calibre-wireless/diagnose.txt`、`diagnose_events.txt` 和 `calibre-wireless.log`。

裡面沒有帳號資料，分享前還是先看一下。

### 第 2 步：交給 AI

開一個**新**對話，附上 `calibre-wireless.zip`（Release 的原檔）和這三個檔案，貼上以下訊息（改最後一段）：

```
我在越獄的 Kindle 上用 KUAL 插件「kindle-kual-calibre-wireless」（https://github.com/bgtsai/kindle-kual-calibre-wireless）。附件是插件 zip 和我 Kindle 上的 diagnose.txt／diagnose_events.txt／calibre-wireless.log。

請先讀 repo 裡的 CLAUDE.md（「Model-specific parts」那張表），再檢查我的檔案：
- 「powerd properties」：有沒有 preventScreenSaver？log 有沒有出現「preventScreenSaver=1 ok」？
- 「scanner properties」：有沒有 doFullScan？新書有沒有出現在首頁？
- diagnose_events.txt：com.lab126.powerd 的休眠／喚醒事件叫什麼？Wi-Fi 事件呢？
- 「tools」：有沒有 eips、mkfifo、iptables？
- 「calibre-wireless.log」：上一次連線有沒有找到 calibre、收到書？有沒有 WARN？

動手前先告訴我要改什麼、為什麼。然後給我結構一樣的新 calibre-wireless.zip（extensions/calibre-wireless/... 和 documents/...），config.xml 的版本號要遞增。

我的問題：<描述發生什麼事>
```

### 第 3 步：裝上新版

把新 zip 的內容蓋過舊的（見[安裝](#安裝)），再連線試一次。

## 給 AI 的說明

見 [CLAUDE.md](CLAUDE.md)——裡面列出機型相依的部分、沒有 Kindle 時怎麼在雲端測試，以及跟作者講好的設計決定。

## 從原始碼編譯

```
cd src && GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o ../kindle/extensions/calibre-wireless/bin/calibre-wireless .
```

再把 `kindle/` 的內容壓成 zip。GitHub Actions 在 `config.xml` 的版本號改變時就是這樣做。

## 參考

- [UNCaGED](https://github.com/shermp/UNCaGED)：calibre Smart Device App 協定的 Go 實作（放在 `src/third_party/UNCaGED`，有兩處小修改，程式碼裡有標註）
- calibre [`smart_device_app/driver.py`](https://github.com/kovidgoyal/calibre/blob/master/src/calibre/devices/smart_device_app/driver.py)（協定、廣播埠）與 [`kindle/driver.py`](https://github.com/kovidgoyal/calibre/blob/master/src/calibre/devices/kindle/driver.py)（縮圖檔名、封面尺寸）
- KOReader [`platform/kindle/koreader.sh`](https://github.com/koreader/koreader/blob/master/platform/kindle/koreader.sh)（為 calibre 的回覆開 Kindle 的防火牆）
- [KindleModding – Scriptlets](https://kindlemodding.org/kindle-dev/scriptlets.html)（`documents/*.sh` 書本）與 [KindleModding/Hotfix](https://github.com/KindleModding/Hotfix)
- [OpenCC](https://github.com/longbridgeapp/opencc)（檔名的繁簡轉換）

## 授權

GPL-3.0（UNCaGED 是 GPL-3.0）。

# PinLinPanLan（PLPL）— 專案交接文件

> 截至 2026-11-06 的完整現況。給接手的人或 AI（Codex 等）快速理解專案用。
> 原型代號 Papapa，GitHub repo：`Xionday/Papapa`（目前為**公開** repo）。

---

## 1. 這是什麼

手機當桌球拍的體感小遊戲。手機平舉，螢幕就是拍面（俯視）；球在拍面上方彈跳，玩家在球落地的瞬間把手機往上揮，就是「拍到」。目標是連續拍越多下越好，揮擊時機分成 PERFECT / GOOD / BAD / MISS。

核心特色（做差異化時要守住的部分）：

| 特色 | 說明 |
|---|---|
| 螢幕即拍面 | 不是「螢幕上有一支拍子」，而是整個螢幕就是拍面，俯視角 |
| 影子提示落點 | 球越高影子越大越淡，球只在接近拍面時才畫出來 |
| 真的揮手機 | 用加速度計偵測「往上揮」，不是點螢幕 |
| 判定環 | 球從最高點開始，一個圓環從螢幕外等速收縮，落地瞬間貼住球，像音遊的 approach circle |
| 傾斜控制 | 手機傾斜決定球往哪邊飄，撞到螢幕邊緣會反彈 |

---

## 2. 技術棧與執行方式

| 項目 | 內容 |
|---|---|
| 引擎 | Godot **4.7.2**，GDScript，GL Compatibility 渲染器 |
| 畫面 | 直式 720×1280，`canvas_items` 縮放 |
| Web 測試版 | 單執行緒 Web 匯出 → GitHub Actions → GitHub Pages：`https://xionday.github.io/Papapa/`（push 到 main 自動部署） |
| 原生 iOS | `export_presets.cfg` 裡的 iOS preset，只匯出 Xcode 專案，再用 Xcode 簽章安裝。Bundle ID `com.allanluo.pinlinpanlan`、最低 iOS 16 |
| 本機開啟 | Godot 4.7.2 開 `project.godot`。感測器在編輯器裡永遠是 0，手感一定要在實機測 |

**更新 iOS 版的流程**：`git pull` → Godot「專案 → 匯出 → iOS → 匯出專案…」覆蓋 `build/ios/` → Xcode 打開 `build/ios/PinLinPanLan.xcodeproj` → ▶。免費 Apple ID 簽章 7 天到期。

> 注意：repo 裡 `export_presets.cfg` 的 iOS preset 是 `com.xionday.pinlinpanlan` 且 Team ID 空白；實際能裝機的值（Team ID、`com.allanluo.pinlinpanlan`）是在 Allan 的 Mac 本機 Godot 裡改的，沒有 commit。

---

## 3. 檔案結構

| 路徑 | 作用 |
|---|---|
| `project.godot` | 專案設定：名稱、解析度、開啟加速度計/重力/陀螺儀 |
| `scenes/main.tscn` | 唯一場景：Main(game.gd) + SensorBridge + Sfx + HUD(選單、結算、除錯面板) |
| `scripts/game.gd` | **核心**：球的物理、揮擊偵測、判定、計分、連擊特效、所有 `_draw` 繪製 |
| `scripts/sensor_bridge.gd` | 統一的感測器入口。Web 讀 `window.papapaMotion`，原生讀 `Input.get_accelerometer/get_gravity`；也包震動 |
| `scripts/hud.gd` | 選單、結算畫面、判定字樣、開發者模式（除錯數值、tune 滑桿、測試鈕） |
| `scripts/sfx.gd` | 程式合成音效（沒有音檔）：perfect / good / bad / miss / stop / tick / wall / zone |
| `scripts/paddle_icon.gd` | 選單裡的小球拍、小球示意圖（程式繪製） |
| `scripts/logo_mark.gd` | 首頁標誌：有 `assets/logo.png` 就顯示，沒有就畫佔位版 |
| `shaders/frosted.gdshader` | 首頁與結算頁的毛玻璃（16 點取樣模糊，不用 mipmap，Web 才不會黑畫面） |
| `web/motion.js` | 瀏覽器端：iOS 動作感測器授權跳窗、DeviceMotion 監聽、iOS 正負號修正 |
| `assets/` | `logo.png`（1024 圓角透明）、`icon_1024.png`（iOS 圖示，不透明）、`LOGO_PROMPT.md`（生成指令） |
| `tests/` | headless 模擬與離線渲染腳本（見第 8 節） |
| `.github/workflows/deploy.yml` | push main → 下載 Godot 4.7.2 headless → 匯出 Web → 部署 Pages |

---

## 4. 核心機制與參數

所有可調參數都在 `scripts/game.gd` 開頭的 `@export var`，開發者模式的 tune 面板可以即時調整其中一部分。

### 4.1 感測器與座標

- 「往上」= 物理重力的反方向：`up = -gravity.normalized()`，`up_accel = linear · up`。手機沒拿平也不會誤判。
- 傾斜 = 重力在拍面上的分量，`zero` 鈕可以把目前握持角度當成水平。
- **iOS Safari 的 DeviceMotion 正負號與 W3C 規格相反**，`web/motion.js` 偵測到 iOS 就整組取負。原生 iOS 的軸向已實機確認可用。

### 4.2 揮擊偵測（`game.gd` 的 `_swings_between`）

| 參數 | 值 | 意義 |
|---|---|---|
| `hit_threshold` | 2.0 m/s² | 向上加速度超過才算揮 |
| `swing_merge` | 0.22 s | 兩段超過門檻的訊號間隔小於這個 = 同一次揮擊（揮完手的回彈不另算） |
| `max_swings` | 2 | 一次下落揮超過 2 次 = 亂晃，直接判 BAD |

判定時刻用揮擊的**起手時刻**（第一筆超過門檻的樣本），不是峰值。視窗內有多次揮擊時取**最後一次**（揮早了可以再揮一次補救）。

### 4.3 判定（用判定環離球的距離）

判定環半徑 = 球「目前」的半徑 + gap，gap 從最高點開始等速縮到 0（落地）。揮擊那一刻的 gap 決定等級：

| gap (px) | 判定 | 約落地前 | 起跳速度 | 分數 |
|---|---|---|---|---|
| ≤ 70（含落地後 80 ms 寬限） | PERFECT | 60 ms | 全力 | +3 |
| ≤ 200 | GOOD | 175 ms | ×0.9 | +1 |
| ≤ 380 | BAD | 330 ms | ×0.6（累乘） | 0 |
| 更遠或沒揮 | MISS | — | ×0.6 | 0 |

**連續 2 次 BAD/MISS → 球停住，回合結束**，顯示結算畫面。

### 4.4 物理

| 參數 | 值 |
|---|---|
| `full_launch` | 5.9 m/s（滯空約 1.2 秒） |
| `lateral_gain` | 150（傾斜 → 球的橫向速度） |
| `wall_bounce` | 0.6（撞螢幕邊緣的反彈係數） |
| `show_height` | 0.6 m（球低於這高度才畫出來） |
| 球半徑 | 落地 46 px，最高 120 px |
| 時鐘 | `_game_time` 累加 delta，不用壁鐘（模擬與暫停才正確） |

### 4.5 手機位移（目前**關閉**，`move_enabled = false`）

衝量法：水平加速度低通 → 死區 0.7 → 積分成速度 → 連續安靜 0.15 秒歸零（ZUPT）→ 乘 px_per_m（由螢幕實體寬度 7 cm 算出，約 10300）。已知限制：慢於 1 秒的移動不會起步，球不可能真正「釘在世界」。見第 6 節。

---

## 5. 畫面與回饋

| 元素 | 說明 |
|---|---|
| 背景 | 拍面色：紅 / 黑 / flip（每次拍到球後 0.5 秒換面） |
| 球 | 乒乓黃（預設）或白 |
| 置中計數 | 大數字 = 分數（半透明、壓在球之下），小字 `x連擊  BEST 分數` |
| 判定環 | 白線 6 px ＋極淡暗邊 |
| PERFECT | 金環從球擴大到 130 px，線淡掉的同時碎成 72 個光點往外飄散 |
| 撞牆 | 沿整個螢幕外框跑的雷射光，從撞點往兩側擴散、轉角自然繞過、漸暗 |
| 連擊 10+ | 邊緣白色波浪（三道正弦亮波沿外框跑） |
| 連擊 20+ | 球冒煙 |
| 連擊 30+ | 波浪轉金黃 |
| 連擊 40+ | 小火 |
| 連擊 50+ | 大火＋球帶光暈 |
| 首頁／結算頁 | 一顆球隨傾斜在桌面滾動，上面蓋毛玻璃 |
| 震動 | 原生 iOS 用 `Input.vibrate_handheld`；**iOS Web 版無法震動**（見第 6 節） |

### 畫面流程

1. （僅 iOS Web）感測器授權跳窗 → ENABLE MOTION
2. 首頁：PLPL 標誌、標題 PinLinPanLan、BEST、選拍面／球、PLAY、developer mode 開關
3. 遊戲中
4. 結算：結束原因、本局分數、BEST（破紀錄顯示 NEW BEST）、PERFECT/GOOD/BAD/MISS 四欄、PLAY AGAIN / menu

---

## 6. 試過並放棄的方案（不要重走）

| 方案 | 結論 | 原因 |
|---|---|---|
| 加速度計二次積分追蹤手機位置 | 放棄 | 誤差平方成長，幾秒內飄掉 |
| AR（ARKit／PocketAR）追蹤位置 | 暫不做 | 要一直開相機、相機朝地板時特徵點不足的風險、無法 Web 測試 |
| UWB（Nearby Interaction） | 放棄 | 需要第二台裝置；Apple Watch 只給距離不給方向 |
| iOS Web 震動 | 不可能 | Safari 無 `navigator.vibrate`；`<input switch>` hack 只在使用者親手點時觸發，程式模擬點擊無效（iOS 18.7 實測） |
| 高度判定 | 改掉 | 接近落地時高度變化太快，差 30 ms 等級就跳，玩家體感不一致 |
| 峰值時刻判定 | 改掉 | 揮擊後手的回彈會被當成第二次揮擊，BAD 時機會被判成 PERFECT |
| 球自動回螢幕中心 | 拿掉 | 玩家要自己控制球留在畫面內 |
| 光圈模式（zone mode） | 暫停，選單已隱藏 | 依賴位移，位移精度不夠；程式碼還在 |

---

## 7. 實測數據（Allan 的 iPhone）

- Safari DeviceMotion 60 Hz、FPS 60
- 平放靜止時 Safari 回報重力 z = −9.69（取負前）
- 隨手往上揮峰值約 18 m/s²；正常遊玩揮擊峰值平均 7 m/s²
- 舊時間判定下，揮擊中位數穩定落在落地前 33–58 ms（已改為距離判定，此數據供參考）

---

## 8. 測試腳本

| 腳本 | 指令 | 用途 |
|---|---|---|
| `tests/sim_judge.gd` | `godot --headless --path . -s tests/sim_judge.gd` | 在指定 gap 揮擊，驗證判定、最後一次為準、亂晃、真實揮擊波形（含回彈） |
| `tests/sim_game.gd` | 同上 | 整場景位移模擬 |
| `tests/sim_move.gd` | 同上 | 位移模型參數比較 |
| `tests/render_ui.gd` | `xvfb-run godot --path . --rendering-driver opengl3 -s tests/render_ui.gd` | 離線渲染選單、遊戲、結算到 `build/ui_*.png` |
| `tests/render_judge.gd` | 同上 | 四個判定門檻當下的畫面 |
| `tests/render_perfect.gd` | 同上 | PERFECT 特效三個時間點 |
| `tests/render_combo.gd` | 同上 | 五個連擊階段 |
| `tests/render_wall.gd` | 同上 | 撞牆雷射光 |

render 類腳本不能 `--headless`，需要虛擬顯示（xvfb）。

---

## 9. 已知待辦

| 類別 | 項目 |
|---|---|
| 遊戲 | 開場教學（審核人員要看得懂體感操作）、設定頁（音效／震動開關）、暫停、切到背景自動暫停、最佳成績存檔（Web 用 localStorage、原生用檔案） |
| 介面 | HUD 文字目前全英文；要中文需打包子集化的 Noto Sans TC |
| 觸覺 | 原生版滾動與撞牆的觸覺回饋（強度隨速度） |
| 延遲 | dev 面板的 latency test 還沒收到實測數據 |
| 上架 | Apple Developer Program、截圖、描述、隱私權政策網址、隱私標籤、TestFlight |
| repo | 目前公開；上架前考慮改私人（Web 測試版會停掉，除非升級 GitHub Pro） |

## 10. 討論中的方向（未決定）

1. **音樂**：分層音樂隨連擊疊加、擊球發五聲音階的音；之後可做節奏模式（滯空時間鎖定 BPM：T = 60/BPM × 拍數，起跳速度 = g×T/2）
2. **冥想模式**：Allan 覺得擊球像敲木魚。不失敗、計時制、約 2 秒滯空配合呼吸、木魚音色、念珠式計數
3. **盈利**：傾向「免費＋一次買斷完整版＋外觀／音色內購」，避免廣告破壞沉浸感
4. **差異化**：名字（乒乒乓乓狀聲詞）、手感調校、台灣乒乓與木魚的文化元素、自錄聲音

---

## 11. 開發協作規則

- Allan 以繁體中文溝通，偏好表格式整理、事實要附來源。
- 沒有明確指示要做的東西，不要自己動手做；想做先提議。
- 所有手感參數都用 `@export`，改值前先在 tune 面板試。
- 改判定或位移邏輯後，先跑 `tests/sim_judge.gd` 和 `tests/sim_game.gd` 再推。

# Papapa

手機當桌球拍、靠感測器連續拍球的原型。Godot 4.7.2，Web 匯出（單執行緒），走 GitHub Actions → GitHub Pages，用 iPhone Safari 測試。

## 目前階段：第 2 步 — 核心玩法

第 1 步結果（iPhone, iOS 18.7, Safari 26.6）：授權 OK、DeviceMotion 60 Hz、FPS 60、平放重力 z = −9.69、隨手往上揮峰值約 18 m/s²。

第 2 步內容：螢幕即拍面（俯視）。球落到拍面時，看最近 0.15 秒內「沿重力反方向」的加速度峰值有沒有超過門檻 → 有用力就全力起跳，沒用力就衰減。球在空中時水平方向推一下 → 拍面在世界裡移動。影子：球越高越大越淡。球低於 show height 才畫出來。

HUD 右下 `tune` 開參數滑桿、`zero` 把目前握持角度設為水平。HUD 文字先用英文，因為 Web 版沒有 CJK 字型。

### 手機測試步驟

1. 用 iPhone Safari 開 Pages 網址，點「啟用感測器」並允許。
2. 平舉手機、按 `zero`。球會自動發球。
3. 球落下時往上揮一下：畫面閃綠＝強擊，閃黃＝弱擊，閃紅＝漏接。
4. 刻意不揮三次，確認球越來越早落地。
5. 傾斜約 10°，落點飄出畫面；往同方向推一下手機，看格線有沒有跟著動、落點有沒有回來。
6. 推的時候有沒有被誤判成揮擊（debug 行會印 HIT / PUSH）。

### 本機跑（可選）

用 Godot 4.7.2 開 `project.godot`。感測器在編輯器裡永遠是零，要匯出 Web 後用 `python -m http.server` 在同一個 Wi-Fi 下開給手機看，記得把 `web/motion.js` 複製到匯出資料夾。

## 檔案

| 路徑 | 作用 |
|---|---|
| `scenes/main.tscn` | 主場景：Main(game.gd) + SensorBridge + HUD |
| `scripts/sensor_bridge.gd` | 統一感測器入口；Web 讀 `window.papapaMotion`，原生讀 `Input` |
| `scripts/game.gd` | 球的物理、揮擊與推動判定、影子與球的繪製 |
| `scripts/hud.gd` | 分數、除錯數值、參數滑桿 |
| `web/motion.js` | 瀏覽器端：授權按鈕、DeviceMotion 監聽、寫入 `window.papapaMotion` |
| `export_presets.cfg` | Web 匯出設定（thread_support=false，head_include 載入 motion.js） |
| `.github/workflows/deploy.yml` | push 到 main 就匯出並部署 Pages |

## 測試腳本

| 腳本 | 用途 |
|---|---|
| `tests/sim_move.gd` | 位移模型：合成移動曲線比較各參數的位移與飄移（headless） |
| `tests/sim_game.gd` | 整場景：餵合成感測器資料驗證位移、靜止飄移、光圈命中（headless） |
| `tests/sim_judge.gd` | 高度判定：在指定高度比例揮擊，驗證 perfect/good/bad/miss 與「最後一次揮擊為準」（headless） |
| `tests/render_wall.gd` | 離線渲染撞牆雷射光到 `build/*.png`（需 xvfb，不能 headless） |

## 下一步

第 3 步：依實測調手感；若要中文 UI，子集化 Noto Sans TC 打包。

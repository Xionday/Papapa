# Papapa

手機當桌球拍、靠感測器連續拍球的原型。Godot 4.7.2，Web 匯出（單執行緒），走 GitHub Actions → GitHub Pages，用 iPhone Safari 測試。

## 目前階段：第 1 步 — 感測器管線驗證

畫面只有一個 HUD，顯示 DeviceMotion 原始值。目的是確認 Safari 的感測器在這條管線上讀得到、頻率多少、延遲感覺如何。

### 手機測試步驟

1. 用 iPhone Safari 開 Pages 網址。
2. 點畫面上方「啟用感測器」按鈕，iOS 會跳出動作感測器授權，選允許。
3. HUD 的「狀態」應該變成 `granted`，數字開始跳動。
4. 回報：事件頻率（Hz）、靜止平舉時重力 z 的值和正負號、往上揮一下時線性加速度峰值大約多少。

### 本機跑（可選）

用 Godot 4.7.2 開 `project.godot`。感測器在編輯器裡永遠是零，要匯出 Web 後用 `python -m http.server` 在同一個 Wi-Fi 下開給手機看，記得把 `web/motion.js` 複製到匯出資料夾。

## 檔案

| 路徑 | 作用 |
|---|---|
| `scenes/main.tscn` | 主場景：SensorBridge + HUD |
| `scripts/sensor_bridge.gd` | 統一感測器入口；Web 讀 `window.papapaMotion`，原生讀 `Input` |
| `scripts/hud.gd` | 印出原始數值 |
| `web/motion.js` | 瀏覽器端：授權按鈕、DeviceMotion 監聽、寫入 `window.papapaMotion` |
| `export_presets.cfg` | Web 匯出設定（thread_support=false，head_include 載入 motion.js） |
| `.github/workflows/deploy.yml` | push 到 main 就匯出並部署 Pages |

## 下一步

第 2 步：加入 Ball、Shadow、揮擊與推動判定（見聊天室規劃）。

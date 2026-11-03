// Papapa — 瀏覽器端感測器橋接
// 由 export_presets.cfg 的 head_include 以 <script src="motion.js"> 載入。
// 把 DeviceMotion 的最新值放在 window.papapaMotion，GDScript 每幀用 JavaScriptBridge 讀。
// iOS 13+ 必須在使用者點擊的同一個事件裡呼叫 requestPermission，所以用 HTML 按鈕而不是 Godot 內的按鈕。

(function () {
  var M = {
    status: "idle",      // idle | requesting | granted | denied | unsupported
    ax: 0, ay: 0, az: 0, // 線性加速度（不含重力）m/s²
    gx: 0, gy: 0, gz: 0, // 含重力的加速度 m/s²
    rx: 0, ry: 0, rz: 0, // 旋轉速率 deg/s
    interval: 0,         // 瀏覽器回報的取樣間隔 ms
    hz: 0,               // 實測每秒事件數
    seq: 0,              // 每次事件 +1，GDScript 用來判斷有沒有新資料
    ua: navigator.userAgent
  };
  window.papapaMotion = M;

  var count = 0, lastTick = performance.now();

  function onMotion(e) {
    var a = e.acceleration, g = e.accelerationIncludingGravity, r = e.rotationRate;
    if (a) { M.ax = a.x || 0; M.ay = a.y || 0; M.az = a.z || 0; }
    if (g) { M.gx = g.x || 0; M.gy = g.y || 0; M.gz = g.z || 0; }
    if (r) { M.rx = r.alpha || 0; M.ry = r.beta || 0; M.rz = r.gamma || 0; }
    M.interval = e.interval || 0;
    M.seq++;
    count++;
    var now = performance.now();
    if (now - lastTick >= 1000) {
      M.hz = Math.round(count * 1000 / (now - lastTick));
      count = 0; lastTick = now;
    }
  }

  function start() {
    window.addEventListener("devicemotion", onMotion, true);
    M.status = "granted";
    hideButton();
  }

  var btn;
  function hideButton() { if (btn) btn.style.display = "none"; }

  function request() {
    if (typeof DeviceMotionEvent === "undefined") { M.status = "unsupported"; hideButton(); return; }
    if (typeof DeviceMotionEvent.requestPermission === "function") {
      M.status = "requesting";
      DeviceMotionEvent.requestPermission().then(function (res) {
        if (res === "granted") start(); else { M.status = "denied"; }
      }).catch(function () { M.status = "denied"; });
    } else {
      start();
    }
  }

  function makeButton() {
    btn = document.createElement("button");
    btn.textContent = "啟用感測器";
    btn.style.cssText = [
      "position:fixed", "left:50%", "top:16px", "transform:translateX(-50%)",
      "z-index:9999", "padding:14px 28px", "font-size:18px", "border:0",
      "border-radius:12px", "background:#d85a30", "color:#fff", "font-family:sans-serif"
    ].join(";");
    btn.addEventListener("click", request);
    document.body.appendChild(btn);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", makeButton);
  } else {
    makeButton();
  }
})();

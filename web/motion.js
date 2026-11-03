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

  // iOS Safari 回傳的加速度正負號與 W3C 規格相反（規格：平放時 accelerationIncludingGravity.z ≈ +9.8，
  // iOS 給 −9.8）。這裡把 iOS 的兩組向量取負，讓 GDScript 永遠收到規格慣例的值。
  var isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
              (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  var sign = isIOS ? -1 : 1;
  M.sign = sign;

  var count = 0, lastTick = performance.now();

  function onMotion(e) {
    var a = e.acceleration, g = e.accelerationIncludingGravity, r = e.rotationRate;
    if (a) { M.ax = sign * (a.x || 0); M.ay = sign * (a.y || 0); M.az = sign * (a.z || 0); }
    if (g) { M.gx = sign * (g.x || 0); M.gy = sign * (g.y || 0); M.gz = sign * (g.z || 0); }
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

  // ---- 震動 ----
  // Safari 不支援 navigator.vibrate。已知的替代法：iOS 的 <input type="checkbox" switch>
  // 被切換時會觸發系統觸覺回饋，用 JS 點它的 <label> 也會。這是 hack，Apple 隨時可能擋掉。
  // 需要手機「設定 → 聲音與觸覺回饋 → 系統觸覺回饋」是開的。
  var H = { supported: false, mode: "none" };
  window.papapaHaptic = H;
  var swInput, swLabel;

  function setupHaptic() {
    if (navigator.vibrate) { H.supported = true; H.mode = "vibrate"; return; }
    swInput = document.createElement("input");
    swInput.type = "checkbox";
    swInput.setAttribute("switch", "");
    swInput.id = "papapa-haptic-switch";
    swLabel = document.createElement("label");
    swLabel.htmlFor = swInput.id;
    var hide = "position:fixed;left:-9999px;top:-9999px;width:1px;height:1px;opacity:0;pointer-events:none";
    swInput.style.cssText = hide;
    swLabel.style.cssText = hide;
    document.body.appendChild(swInput);
    document.body.appendChild(swLabel);
    // 實測 iOS 18.7：親手點 switch 會震，程式 label.click() 不會。
    // 元件留著給 showSwitch() 除錯用，但對遊戲來說等於沒有震動。
    H.supported = false;
    H.mode = "web-none";
  }

  // count: 連點幾下；gap: 間隔 ms
  H.tap = function (count, gap) {
    count = count || 1; gap = gap || 70;
    if (H.mode === "vibrate") { var p = []; for (var i = 0; i < count; i++) { p.push(30); p.push(gap); } navigator.vibrate(p); return; }
    if (H.mode !== "switch") return; // web-none：什麼都不做
    var n = 0;
    (function step() {
      swLabel.click();
      n++;
      if (n < count) setTimeout(step, gap);
    })();
  };

  // 除錯：把真正的 switch 顯示在左下角，讓使用者親手點，確認 iOS 到底會不會給觸覺
  H.showSwitch = function () {
    if (!swInput) return;
    swInput.style.cssText = "position:fixed;left:16px;bottom:120px;z-index:9999;transform:scale(1.6);transform-origin:left bottom;opacity:1;pointer-events:auto;width:auto;height:auto";
  };

  function init() { makeButton(); setupHaptic(); }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

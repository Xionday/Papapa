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

  var overlay, btn, msgEl;
  function hideButton() {
    if (!overlay) return;
    overlay.style.opacity = "0";
    setTimeout(function () { if (overlay) overlay.style.display = "none"; }, 350);
  }
  function setMsg(t) { if (msgEl) msgEl.textContent = t; }

  function request() {
    if (typeof DeviceMotionEvent === "undefined") { M.status = "unsupported"; setMsg("This device has no motion sensors."); return; }
    if (typeof DeviceMotionEvent.requestPermission === "function") {
      M.status = "requesting";
      DeviceMotionEvent.requestPermission().then(function (res) {
        if (res === "granted") start();
        else { M.status = "denied"; setMsg("Motion access was denied. Reload the page and allow it, or enable it in Settings › Safari › Motion & Orientation Access."); }
      }).catch(function () { M.status = "denied"; setMsg("Could not request motion access. Reload and try again."); });
    } else {
      start();
    }
  }

  // 進入遊戲前的跳窗：iOS 要求授權必須在使用者點擊的同一個事件裡發出，所以這層是 HTML 不是 Godot。
  // 非 iOS（不需要授權）直接開始、不顯示。
  function makeButton() {
    var needsPrompt = typeof DeviceMotionEvent !== "undefined" && typeof DeviceMotionEvent.requestPermission === "function";
    if (!needsPrompt) { request(); return; }
    var css = document.createElement("style");
    css.textContent = [
      "#plpl-gate{position:fixed;inset:0;z-index:9999;display:flex;align-items:center;justify-content:center;",
      "background:rgba(28,22,22,.78);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);",
      "font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;transition:opacity .35s ease}",
      "#plpl-gate .card{width:min(86vw,420px);background:#2b2425;border:1px solid rgba(255,255,255,.12);border-radius:28px;",
      "padding:36px 28px 28px;text-align:center;color:#fff2d9;box-shadow:0 20px 60px rgba(0,0,0,.45)}",
      "#plpl-gate .mark{width:84px;height:84px;margin:0 auto 18px;border-radius:22px;background:#fff2d9;position:relative}",
      "#plpl-gate .mark .p{position:absolute;left:50%;top:38%;width:38px;height:38px;margin:-19px 0 0 -19px;border-radius:50%;background:#e86b66;box-shadow:0 0 0 3px #8c6640}",
      "#plpl-gate .mark .h{position:absolute;left:50%;top:60%;width:12px;height:22px;margin-left:-6px;background:#c79e6b;border-radius:3px}",
      "#plpl-gate .mark .b{position:absolute;left:62%;top:18%;width:16px;height:16px;border-radius:50%;background:#ffdd33}",
      "#plpl-gate h1{font-size:30px;margin:0 0 6px;letter-spacing:.5px;font-weight:700}",
      "#plpl-gate p{font-size:15px;line-height:1.5;color:rgba(255,242,217,.7);margin:0 0 24px}",
      "#plpl-gate button{width:100%;border:0;border-radius:20px;padding:18px;font-size:20px;font-weight:700;",
      "background:#fff2d9;color:#332919;letter-spacing:.5px}",
      "#plpl-gate button:active{transform:scale(.98)}",
      "#plpl-gate .msg{min-height:18px;font-size:13px;color:#ffc46b;margin-top:14px}"
    ].join("");
    document.head.appendChild(css);
    overlay = document.createElement("div");
    overlay.id = "plpl-gate";
    overlay.innerHTML =
      '<div class="card">' +
      '<div class="mark"><div class="p"></div><div class="h"></div><div class="b"></div></div>' +
      '<h1>PinLinPanLan</h1>' +
      '<p>This game uses your phone\'s motion sensors as the paddle.<br>Allow motion access to play.</p>' +
      '<button type="button">ENABLE MOTION</button>' +
      '<div class="msg"></div></div>';
    document.body.appendChild(overlay);
    btn = overlay.querySelector("button");
    msgEl = overlay.querySelector(".msg");
    btn.addEventListener("click", request);
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

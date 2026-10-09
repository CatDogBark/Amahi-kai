// Amahi-kai ocean background
//
// A living underwater scene behind the page: water lit from above, the surface overhead in
// perspective, sun and moon, caustics, weather, tides, bubbles and the occasional sea creature.
// Time of day, weather, tide and sea-life sightings follow the clock and the visitor's settings.
// The rest (the water's motion, bubbles, fish in formation) is handed from each page to the next
// in sessionStorage, so following a link carries the scene on instead of starting it again.
//
// Markup:  <div id="ocean" data-ocean-occlude="CSS selector" [data-ocean-theme="dark"] [data-ocean-fab]></div>
//   data-ocean-occlude  elements that near bubbles fade over (cards, header, forms)
//   data-ocean-theme    force a theme; otherwise html[data-theme] or the system setting decides
//   data-ocean-fab      add a floating "Water" button (pages without a header to put one in)
// Any element with [data-ocean-panel] opens the settings panel. Styles live in ocean-bg.css.
//
// This file is mirrored to site/assets/ocean.js for amahi-kai.com. Edit it here, then run
// script/sync-ocean-assets.
(() => {
  "use strict";
  if (window.AmahiOcean) return;

  const run = () => {
    const mount = document.getElementById("ocean");
    if (!mount || mount.dataset.oceanReady) return;
    mount.dataset.oceanReady = "1";

    const TAU = Math.PI * 2;
    const $ = (s, r = document) => r.querySelector(s);
    const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
    const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
    const mix = (a, b, k) => a + (b - a) * k;
    const mix3 = (a, b, k) => [mix(a[0], b[0], k), mix(a[1], b[1], k), mix(a[2], b[2], k)];
    const scale3 = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
    const smooth = (e0, e1, x) => { const k = clamp((x - e0) / (e1 - e0), 0, 1); return k * k * (3 - 2 * k); };
    const hash1 = n => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };
    const noise1 = x => { const i = Math.floor(x), f = x - i; return mix(hash1(i), hash1(i + 1), f * f * (3 - 2 * f)); };

    // ── Settings: the scene is a function of the clock plus these ──
    const STORE = "amahi-ocean";
    const DEFAULTS = {
      on: true, timeMode: "live", manualHour: 14,
      weather: "auto", wFrom: 0.3, wSetAt: 0,
      cycle: 1, anchorReal: 0, anchorScene: 0,
      quality: "balanced", life: "occasional",
      layers: { caustics: true, rays: true, surface: true, rings: true, back: true, front: true },
    };
    let previewing = false;
    const S = (() => {
      let s = null;
      try { s = JSON.parse(localStorage.getItem(STORE) || "null"); } catch (e) { s = null; }
      if (!s || typeof s !== "object") {
        s = {};
        try { if (localStorage.getItem("ocean-off") === "1") s.on = false; } catch (e) { /* storage unavailable */ }  // the old on/off toggle
      }
      return Object.assign({}, DEFAULTS, s, { layers: Object.assign({}, DEFAULTS.layers) });
    })();
    function save() {
      if (previewing) return;
      try { localStorage.setItem(STORE, JSON.stringify(S)); } catch (e) { /* storage unavailable */ }
    }
    if (!S.anchorReal) { S.anchorReal = S.anchorScene = Date.now(); save(); }
    const REDUCED = matchMedia("(prefers-reduced-motion: reduce)").matches;

    // ── Layers: water and far bubbles behind the page, a few near bubbles in front of it ──
    const OCCLUDE = mount.getAttribute("data-ocean-occlude") || ".navbar, .card, fieldset, table, form, .modal-content";
    const glCanvas = document.createElement("canvas");
    glCanvas.className = "ocean-gl";
    const backCanvas = document.createElement("canvas");
    backCanvas.className = "ocean-back";
    mount.append(glCanvas, backCanvas);
    const frontLayer = document.createElement("div");
    frontLayer.className = "ocean-front";
    frontLayer.setAttribute("aria-hidden", "true");
    const frontCanvas = document.createElement("canvas");
    frontLayer.append(frontCanvas);
    document.body.append(frontLayer);

    const sceneMs = now => S.anchorScene + (now - S.anchorReal) * S.cycle;

    // Weather: one number w from 0 (clear) to 3 (storm); auto weather is smooth noise over scene time
    const TARGET = { clear: 0.3, cloudy: 1.15, rain: 1.95, storm: 2.85 };
    const BLEND_MS = 20000;
    const autoW = ms => { const x = ms / (45 * 60000); return 3 * Math.pow(noise1(x) * 0.65 + noise1(x * 2.3 + 17.3) * 0.35, 1.7); };
    const weatherW = now => {
      const target = S.weather === "auto" ? autoW(sceneMs(now)) : TARGET[S.weather];
      return mix(S.wFrom, target, smooth(0, 1, (now - S.wSetAt) / BLEND_MS));
    };
    const cloudOf = w => smooth(0.55, 1.5, w);
    const rainOf = w => smooth(1.5, 2.15, w);
    const stormOf = w => smooth(2.25, 2.85, w);
    function turbAt(now) {      // sediment stirred by recent storms, settling over a scene-hour
      let tb = 0;
      const step = (7.5 * 60000) / S.cycle;
      for (let k = 0; k < 8; k++) {
        const w = weatherW(now - k * step);
        tb = Math.max(tb, (stormOf(w) + 0.3 * rainOf(w)) * Math.pow(1 - k / 8, 1.2));
      }
      return clamp(tb, 0, 1);
    }
    let manualFlashAt = -1e12;
    const flashEnv = dt => (dt < 0 || dt > 0.9) ? 0 : 0.9 * Math.exp(-dt * 8) + 0.7 * Math.exp(-Math.pow((dt - 0.22) * 22, 2));
    function flashAt(now) {     // lightning is tied to real seconds so every open page agrees
      let f = flashEnv((now - manualFlashAt) / 1000);
      const st = stormOf(weatherW(now));
      if (st > 0.05) {
        const sec = Math.floor(now / 1000);
        for (let k = 0; k < 2; k++) {
          const s = sec - k;
          if (hash1(s * 1.37) < st * 0.09) f = Math.max(f, flashEnv((now - (s * 1000 + hash1(s * 7.13) * 1000)) / 1000));
        }
      }
      return clamp(f, 0, 1);
    }

    const RISE = 6.5, SET = 19.5;
    function hourAt(now) {
      if (S.timeMode === "manual") return S.manualHour;
      const d = new Date(sceneMs(now));
      return d.getHours() + d.getMinutes() / 60 + d.getSeconds() / 3600;
    }
    function sky(hour) {
      const dayLen = SET - RISE;
      let day, p, elev;
      if (hour >= RISE && hour <= SET) { day = true; p = (hour - RISE) / dayLen; elev = Math.sin(Math.PI * p); }
      else { day = false; p = (((hour - SET) % 24) + 24) % 24 / (24 - dayLen); elev = -Math.sin(Math.PI * p); }
      const dayF = smooth(-0.1, 0.22, elev);
      return {
        day, p, elev, dayF,
        warm: Math.exp(-Math.pow((elev - 0.03) / 0.14, 2)),
        sunX: day ? p : 0.5, sunElev: Math.max(0, elev), sunAmt: day ? smooth(-0.02, 0.12, elev) : 0,
        moonX: day ? 0.5 : p, moonElev: day ? 0 : Math.sin(Math.PI * p),
        moonAmt: day ? 0 : smooth(0, 0.2, Math.sin(Math.PI * p)) * (1 - dayF),
      };
    }
    function sceneState(now) {
      const hour = hourAt(now), w = weatherW(now);
      const ph = TAU * (sceneMs(now) / 3.6e6) / 12.42 + 1.1;
      return Object.assign(sky(hour), {
        hour, w, cloud: cloudOf(w), rain: rainOf(w), storm: stormOf(w), turb: turbAt(now),
        tide: Math.sin(ph), tideRising: Math.cos(ph) > 0, flash: flashAt(now),
      });
    }


    // ── Colors: theme sets the brightness range, time and weather move within it ──
    const PAL = {
      dark: {
        dayTop: [0.075, 0.255, 0.345], dayMid: [0.040, 0.125, 0.195], dayDeep: [0.016, 0.050, 0.085],
        nightTop: [0.030, 0.060, 0.105], nightMid: [0.016, 0.032, 0.060], nightDeep: [0.008, 0.016, 0.032],
        warm: [0.42, 0.22, 0.10], grey: [0.075, 0.10, 0.12], storm: [0.040, 0.075, 0.070], silt: [0.075, 0.085, 0.060],
        surfDay: [0.62, 0.90, 0.98], surfNight: [0.30, 0.40, 0.55], surfWarm: [1.0, 0.70, 0.45],
        surfAmtDay: 0.34, surfAmtNight: 0.07,
        sun: [1.0, 0.97, 0.88], sunWarm: [1.0, 0.62, 0.32], sunAmt: 0.55, moon: [0.75, 0.85, 1.0], moonAmt: 0.18,
        caus: [0.16, 0.71, 0.84], causAmt: 0.22, ray: [0.40, 0.84, 0.95], rayAmt: 0.09,
        flash: [0.75, 0.85, 1.0], flashAmt: 0.55,
        rim: [178, 232, 246],
      },
      light: {
        dayTop: [0.905, 0.970, 0.990], dayMid: [0.720, 0.875, 0.925], dayDeep: [0.520, 0.745, 0.830],
        nightTop: [0.700, 0.780, 0.860], nightMid: [0.600, 0.680, 0.775], nightDeep: [0.500, 0.585, 0.690],
        warm: [1.0, 0.86, 0.70], grey: [0.760, 0.810, 0.830], storm: [0.640, 0.700, 0.690], silt: [0.700, 0.700, 0.600],
        surfDay: [1, 1, 1], surfNight: [0.85, 0.90, 1.0], surfWarm: [1.0, 0.85, 0.65],
        surfAmtDay: 0.42, surfAmtNight: 0.18,
        sun: [1, 1, 0.95], sunWarm: [1.0, 0.78, 0.50], sunAmt: 0.55, moon: [0.95, 0.97, 1.0], moonAmt: 0.25,
        caus: [1, 1, 1], causAmt: 0.32, ray: [1, 1, 1], rayAmt: 0.22,
        flash: [1, 1, 1], flashAmt: 0.45,
        rim: [8, 96, 122],
      },
    };
    function uniformsFor(st, theme) {
      const P = PAL[theme], L = S.layers;
      let top = mix3(P.nightTop, P.dayTop, st.dayF);
      let mid = mix3(P.nightMid, P.dayMid, st.dayF);
      let deep = mix3(P.nightDeep, P.dayDeep, st.dayF);
      top = mix3(top, P.warm, st.warm * 0.45);
      mid = mix3(mid, P.warm, st.warm * 0.12);
      const ov = st.cloud * 0.55;
      top = mix3(top, P.grey, ov); mid = mix3(mid, P.grey, ov * 0.6); deep = mix3(deep, P.grey, ov * 0.3);
      top = mix3(top, P.storm, st.storm * 0.6); mid = mix3(mid, P.storm, st.storm * 0.55); deep = mix3(deep, P.storm, st.storm * 0.4);
      mid = mix3(mid, P.silt, st.turb * 0.35); deep = mix3(deep, P.silt, st.turb * 0.25);
      const through = (1 - 0.8 * st.cloud) * (1 - 0.5 * st.storm);
      const surfCol = mix3(mix3(P.surfNight, P.surfDay, st.dayF), P.surfWarm, st.warm * 0.5);
      const surfAmt = L.surface ? mix(P.surfAmtNight, P.surfAmtDay, st.dayF) * (0.45 + 0.55 * through) : 0;
      return {
        top, mid, deep, surfCol, surfAmt,
        ringAmt: L.rings ? st.rain : 0,
        chop: 0.2 + 0.8 * st.storm + 0.3 * st.rain + 0.15 * st.cloud,
        eyeD: 1 + 0.12 * st.tide,
        sun: [0.08 + 0.84 * st.sunX, mix(0.24, 0.075, st.sunElev), st.sunElev, L.surface ? P.sunAmt * st.sunAmt * Math.pow(through, 1.5) : 0],
        sunCol: mix3(P.sun, P.sunWarm, st.warm),
        moon: [0.08 + 0.84 * st.moonX, mix(0.24, 0.09, st.moonElev), st.moonElev, L.surface ? P.moonAmt * st.moonAmt * through : 0],
        moonCol: P.moon,
        cloud: st.cloud,
        causCol: mix3(P.caus, P.sunWarm, st.warm * 0.4),
        causAmt: L.caustics ? P.causAmt * (st.dayF + 0.15 * st.moonAmt) * through * through : 0,
        rayCol: mix3(P.ray, P.sunWarm, st.warm * 0.5),
        rayAmt: L.rays ? P.rayAmt * st.dayF * Math.pow(through, 1.5) * (0.7 + 0.3 * st.sunElev) : 0,
        flashCol: P.flash, flash: P.flashAmt * st.flash,
      };
    }


    // ── WebGL water ─────────────────────────────────────────────────
    const VS = "attribute vec2 p; void main(){ gl_Position = vec4(p, 0.0, 1.0); }";
    const FS = `
  #ifdef GL_FRAGMENT_PRECISION_HIGH
  precision highp float;
  #else
  precision mediump float;
  #endif
  uniform vec2 uRes;
  uniform vec2 uView;
  uniform float uTime;
  uniform vec3 uTop;
  uniform vec3 uMid;
  uniform vec3 uDeep;
  uniform vec3 uSurfCol;
  uniform float uSurfAmt;
  uniform float uRingAmt;
  uniform float uChop;
  uniform float uEyeD;
  uniform vec4 uSun;
  uniform vec3 uSunCol;
  uniform vec4 uMoon;
  uniform vec3 uMoonCol;
  uniform float uCloud;
  uniform vec3 uCausCol;
  uniform float uCausAmt;
  uniform vec3 uRayCol;
  uniform float uRayAmt;
  uniform vec3 uFlashCol;
  uniform float uFlash;
  uniform float uSurge;

  float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
  vec2 hash2(vec2 p){ return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }

  float vnoise(vec2 p){
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
  }

  float fbm(vec2 p){
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++){ s += a * vnoise(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; }
    return s;
  }

  // Distance to the nearest edge of an animated cell pattern (F2 - F1)
  float cellEdge(vec2 p, float t){
    vec2 i = floor(p);
    vec2 f = fract(p);
    float d1 = 8.0;
    float d2 = 8.0;
    for (int y = -1; y <= 1; y++){
      for (int x = -1; x <= 1; x++){
        vec2 g = vec2(float(x), float(y));
        vec2 h = hash2(i + g);
        vec2 o = 0.5 + 0.38 * sin(t * (0.35 + 0.4 * h) + 6.2831 * h);
        vec2 r = g + o - f;
        float d = dot(r, r);
        if (d < d1){ d2 = d1; d1 = d; } else if (d < d2){ d2 = d; }
      }
    }
    return sqrt(d2) - sqrt(d1);
  }

  // Height of the water surface in world units
  float waveH(vec2 p, float t){
    float h = sin(dot(p, vec2(1.0, 0.35)) * 4.2 + t * 0.9) * 0.5;
    h += sin(dot(p, vec2(-0.55, 1.0)) * 6.1 + t * 1.25) * 0.32;
    h += sin(dot(p, vec2(0.25, -1.0)) * 9.7 + t * 1.8) * (0.12 + 0.2 * uChop);
    h += (vnoise(p * 5.0 + vec2(t * 0.5, -t * 0.35)) - 0.5) * (0.3 + 0.9 * uChop);
    return h;
  }

  // Expanding rings where raindrops hit; one drop per cell per cycle
  float rainRings(vec2 p, float t, float density){
    vec2 i = floor(p);
    vec2 f = fract(p);
    float s = 0.0;
    for (int y = -1; y <= 1; y++){
      for (int x = -1; x <= 1; x++){
        vec2 g = vec2(float(x), float(y));
        vec2 h = hash2(i + g);
        if (h.y > density) continue;
        float cyc = t * (0.7 + 0.6 * h.x) + h.y * 13.0;
        float life = fract(cyc);
        vec2 c = g + 0.15 + 0.7 * hash2(i + g + mod(floor(cyc), 89.0) * 1.37) - f;
        float r = life * 0.75;
        s += exp(-abs(length(c) - r) * 30.0) * (1.0 - life) * (1.0 - life);
      }
    }
    return s;
  }

  // The sun or moon seen through the moving surface
  float lightSpot(vec4 L, vec2 v, vec2 slope, float W, float H){
    vec2 c = vec2(L.x * W, L.y * H);
    vec2 q = (v - c) / (vec2(0.16 * W, 0.09 * H) * (1.0 + 1.2 * uCloud));
    q += slope * 0.05;
    float r2 = dot(q, q);
    return exp(-r2 * 1.8) * 0.6 + exp(-r2 * 9.0) * 0.9;
  }

  void main(){
    float px = uView.x / uRes.x;
    vec2 v = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y) * px;   // CSS px, y down
    float W = uView.x;
    float H = uView.y;
    float d = clamp(v.y / H, 0.0, 1.0);
    float t = uTime;
    vec2 vs = v + vec2(uSurge, 0.0);

    // Open water: lighter toward the surface, darker below
    vec3 col = mix(uTop, uMid, smoothstep(0.0, 0.5, d));
    col = mix(col, uDeep, smoothstep(0.4, 1.0, d));
    col *= 0.94 + 0.12 * fbm(vs * 0.0012 + vec2(t * 0.01, -t * 0.008));

    // The surface overhead, in perspective: the camera looks forward from under the water
    float yh = 0.5 * H;
    float f = 0.6 * H;
    float haze = 0.0;
    vec2 slope = vec2(0.0);
    if (v.y < yh - 2.0 && uSurfAmt + uRingAmt > 0.0) {
      float z = uEyeD * f / (yh - v.y);
      float z0 = uEyeD * f / yh;
      haze = exp(-(z - z0) * 0.95);
      if (haze > 0.004) {
        vec2 w = vec2((vs.x - 0.5 * W) / f * z, z);
        float h = waveH(w, t);
        float hx = waveH(w + vec2(0.02, 0.0), t) - h;
        float hz = waveH(w + vec2(0.0, 0.02), t) - h;
        slope = vec2(hx, hz) / 0.02;
        float web = exp(-cellEdge(w * 2.6 + slope * 0.05, t * 1.1) * 9.0);
        float lum = 0.5 + 0.3 * clamp(h * 0.7, -1.0, 1.0) + 0.55 * web;
        col += uSurfCol * uSurfAmt * haze * lum;
        if (uRingAmt > 0.01) {
          col += uSurfCol * (0.25 + uSurfAmt) * haze * uRingAmt * 0.9 * rainRings(w * 3.2, t, 0.25 + 0.75 * uRingAmt);
        }
      }
    }
    if (uSun.w > 0.0) col += uSunCol * uSun.w * lightSpot(uSun, vs, slope, W, H);
    if (uMoon.w > 0.0) col += uMoonCol * uMoon.w * lightSpot(uMoon, vs, slope, W, H);

    // Light shafts, slanting with the sun
    if (uRayAmt > 0.001) {
      float sx = uSun.x * W;
      vec2 src = vec2(sx - (0.5 - (uSun.x - 0.08) / 0.84) * 2.2 * W * (1.0 - uSun.z), -(0.35 + 0.6 * uSun.z) * H);
      vec2 dv = vs - src;
      float ang = atan(dv.x, dv.y);
      float rays = 0.6 * vnoise(vec2(ang * 9.0 + t * 0.03, t * 0.05))
                 + 0.4 * vnoise(vec2(ang * 23.0 - t * 0.045, 4.0 + t * 0.07));
      rays = pow(smoothstep(0.4, 1.0, rays), 1.5);
      col += uRayCol * uRayAmt * rays * (1.0 - smoothstep(0.02, 0.9, d)) * (1.0 - 0.4 * haze);
    }

    // Caustics: drifting patches of focused light, fading with depth
    if (uCausAmt > 0.001 && d < 0.9) {
      float mask = smoothstep(0.32, 0.72, fbm(vs * 0.0015 + vec2(t * 0.018, t * 0.011)));
      vec2 cp = vs / vec2(150.0, 128.0);
      cp += (vec2(fbm(cp * 0.5 + t * 0.06), fbm(cp * 0.5 + vec2(5.2, 1.3) - t * 0.05)) - 0.5) * 1.6;
      float e1 = cellEdge(cp, t * 0.8);
      float e2 = cellEdge(cp * 1.7 + vec2(3.7, 8.1), t * 1.1 + 2.0);
      float l1 = exp(-e1 * 22.0);
      float l2 = exp(-e2 * 26.0);
      float caus = l1 * 0.5 + l2 * 0.3 + l1 * l2 * 2.2;
      col += uCausCol * uCausAmt * caus * exp(-d * 3.0) * (0.3 + 0.7 * mask) * (1.0 - 0.7 * haze);
    }

    // Lightning lights the surface first, then the water
    col += uFlashCol * uFlash * (0.18 + 0.6 * haze + 0.25 * (1.0 - d));

    col += (hash(gl_FragCoord.xy + fract(t * 7.0)) - 0.5) / 255.0;
    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
  }`;


    const glView = (() => {
      const canvas = glCanvas;
      let gl = null;
      const U = {};
      let error = "";
      try {
        gl = canvas.getContext("webgl", { alpha: false, antialias: false, depth: false, stencil: false, powerPreference: "low-power" });
      } catch (e) { gl = null; }
      if (gl) {
        const compile = (type, src) => {
          const sh = gl.createShader(type);
          gl.shaderSource(sh, src);
          gl.compileShader(sh);
          if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) { error = gl.getShaderInfoLog(sh) || "compile failed"; return null; }
          return sh;
        };
        const vs = compile(gl.VERTEX_SHADER, VS);
        const fs = vs && compile(gl.FRAGMENT_SHADER, FS);
        const prog = fs ? gl.createProgram() : null;
        if (prog) { gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog); }
        if (!prog || !gl.getProgramParameter(prog, gl.LINK_STATUS)) {
          if (prog && !error) error = gl.getProgramInfoLog(prog) || "link failed";
          gl = null;
        } else {
          gl.useProgram(prog);
          gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
          gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
          const loc = gl.getAttribLocation(prog, "p");
          gl.enableVertexAttribArray(loc);
          gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
          ["uRes", "uView", "uTime", "uTop", "uMid", "uDeep", "uSurfCol", "uSurfAmt", "uRingAmt", "uChop", "uEyeD",
           "uSun", "uSunCol", "uMoon", "uMoonCol", "uCloud", "uCausCol", "uCausAmt", "uRayCol", "uRayAmt",
           "uFlashCol", "uFlash", "uSurge"].forEach(n => { U[n] = gl.getUniformLocation(prog, n); });
          canvas.addEventListener("webglcontextlost", e => { e.preventDefault(); gl = null; mount.classList.add("no-gl"); });
        }
      } else {
        error = "WebGL is not available in this browser";
      }
      if (!gl) {
        mount.classList.add("no-gl");
        console.warn("Ocean background: water shader unavailable, showing the plain gradient. " + String(error).split("\n")[0]);
      }
      let cssW = 1, cssH = 1;
      function resize(w, h, dpr, res) {
        cssW = w; cssH = h;
        canvas.width = Math.max(1, Math.round(w * dpr * res));
        canvas.height = Math.max(1, Math.round(h * dpr * res));
      }
      function draw(u, t, surge) {
        if (!gl) return;
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.uniform2f(U.uRes, canvas.width, canvas.height);
        gl.uniform2f(U.uView, cssW, cssH);
        gl.uniform1f(U.uTime, t);
        gl.uniform3fv(U.uTop, u.top); gl.uniform3fv(U.uMid, u.mid); gl.uniform3fv(U.uDeep, u.deep);
        gl.uniform3fv(U.uSurfCol, u.surfCol); gl.uniform1f(U.uSurfAmt, u.surfAmt);
        gl.uniform1f(U.uRingAmt, u.ringAmt); gl.uniform1f(U.uChop, u.chop); gl.uniform1f(U.uEyeD, u.eyeD);
        gl.uniform4fv(U.uSun, u.sun); gl.uniform3fv(U.uSunCol, u.sunCol);
        gl.uniform4fv(U.uMoon, u.moon); gl.uniform3fv(U.uMoonCol, u.moonCol);
        gl.uniform1f(U.uCloud, u.cloud);
        gl.uniform3fv(U.uCausCol, u.causCol); gl.uniform1f(U.uCausAmt, u.causAmt);
        gl.uniform3fv(U.uRayCol, u.rayCol); gl.uniform1f(U.uRayAmt, u.rayAmt);
        gl.uniform3fv(U.uFlashCol, u.flashCol); gl.uniform1f(U.uFlash, u.flash);
        gl.uniform1f(U.uSurge, surge);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }
      return { resize, draw, size: () => [canvas.width, canvas.height], ok: () => !!gl };
    })();


    // ── Bubbles (two canvases: behind and in front of the cards) ──
    const parts = (() => {
      const back = backCanvas, front = frontCanvas;
      const bctx = back.getContext("2d"), fctx = front.getContext("2d");
      let W = 1, H = 1, dpr = 1, area = 1, eyeD = 1;
      const bubbles = [], fronts = [];
      const sources = [
        { base: 0.17, phase: 0.0, next: 0.8, left: 0, gap: 0 },
        { base: 0.76, phase: 2.1, next: 3.1, left: 0, gap: 0 },
      ];
      let sprites = null, rects = [];
      const SPR = 64, SPR_R = SPR / 2 - 3, SPR_K = SPR / (2 * SPR_R);
      const rgba = (c, a) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`;

      function makeSprites(theme) {
        const P = PAL[theme];
        const sharp = document.createElement("canvas");
        sharp.width = sharp.height = SPR;
        const g = sharp.getContext("2d");
        const C = SPR / 2, R = SPR_R;
        let grd = g.createRadialGradient(C, C, 0, C, C, R);
        grd.addColorStop(0, rgba(P.rim, 0.03));
        grd.addColorStop(0.7, rgba(P.rim, 0.08));
        grd.addColorStop(0.88, rgba(P.rim, 0.4));
        grd.addColorStop(0.97, rgba(P.rim, 0.68));
        grd.addColorStop(1, rgba(P.rim, 0));
        g.fillStyle = grd;
        g.beginPath(); g.arc(C, C, R, 0, TAU); g.fill();
        const hx = SPR * 0.36, hy = SPR * 0.32, hr = R * 0.34;
        grd = g.createRadialGradient(hx, hy, 0, hx, hy, hr);
        grd.addColorStop(0, "rgba(255,255,255,0.95)");
        grd.addColorStop(0.5, "rgba(255,255,255,0.35)");
        grd.addColorStop(1, "rgba(255,255,255,0)");
        g.fillStyle = grd;
        g.beginPath(); g.arc(hx, hy, hr, 0, TAU); g.fill();
        g.strokeStyle = "rgba(255,255,255,0.3)";
        g.lineWidth = SPR * 0.04;
        g.lineCap = "round";
        g.beginPath(); g.arc(C, C, R * 0.72, Math.PI * 0.15, Math.PI * 0.55); g.stroke();

        const soft = document.createElement("canvas");
        soft.width = soft.height = SPR;
        const sg = soft.getContext("2d");
        if ("filter" in sg) { sg.filter = "blur(2px)"; sg.drawImage(sharp, 0, 0); }
        else { sg.globalAlpha = 0.7; sg.drawImage(sharp, 0, 0); }
        sprites = { sharp, soft };
      }

      // z: 0 far .. 1 near. Distance from the camera in eye-depth units sets size, speed and where it meets the surface.
      const depth = z => { const dist = 3.4 + (0.55 - 3.4) * z; return { dist, k: 1.2 / dist }; };
      const popY = dist => H * 0.5 - (0.6 * H * eyeD) / dist;

      function newBubble(isFront, initial) {
        const z = isFront ? 0.84 + Math.random() * 0.16 : Math.pow(Math.random(), 1.25) * 0.78;
        const { dist, k } = depth(z);
        const r0 = 1.6 + 4.4 * Math.pow(Math.random(), 2);
        const big = r0 > 3.6;
        const top = Math.max(-40, popY(dist));
        return {
          z, dist, k, r0, stream: false,
          x: Math.random() * W,
          y: initial ? top + Math.random() * (H - top) : H + 10 + Math.random() * H * 0.15,
          vy: (26 + 7 * r0) * k * (0.9 + 0.2 * Math.random()),
          amp: (big ? r0 + 2 : 0.6 + r0 * 0.35) * k,
          freq: big ? 1.6 + Math.random() * 1.2 : 0.8 + Math.random() * 0.8,
          ph: Math.random() * TAU,
        };
      }
      function newStream(x) {
        const z = 0.55, { dist, k } = depth(z);
        const r0 = 1.3 + Math.random() * 1.3;
        return {
          z, dist, k, r0, stream: true,
          x: x + (Math.random() - 0.5) * 3 * k, y: H + 6,
          vy: (26 + 7 * r0) * k * 1.3,          // a train rises a little faster in its own wake
          amp: (0.5 + Math.random() * 0.7) * k, freq: 2.4 + Math.random(), ph: Math.random() * TAU,
        };
      }

      function populate(initial) {
        const nb = Math.max(10, Math.round(40 * area));
        const nf = Math.max(2, Math.round(4 * area));
        let singles = bubbles.filter(b => !b.stream).length;
        while (singles < nb) { bubbles.push(newBubble(false, initial)); singles++; }
        for (let i = bubbles.length - 1; i >= 0 && singles > nb; i--) {
          if (!bubbles[i].stream) { bubbles.splice(i, 1); singles--; }
        }
        while (fronts.length < nf) fronts.push(newBubble(true, initial));
        fronts.length = Math.min(fronts.length, nf);
      }
      function resize(w, h, d) {
        const oldH = H;
        W = w; H = h; dpr = d; area = (W * H) / (1920 * 1200);
        back.width = front.width = Math.max(1, Math.round(W * dpr));
        back.height = front.height = Math.max(1, Math.round(H * dpr));
        if (oldH > 1 && oldH !== H) {
          const f = H / oldH;
          for (const b of bubbles) b.y *= f;
          for (const b of fronts) b.y *= f;
        }
        populate(true);
      }
      function updateRects() {
        rects = $$(OCCLUDE).map(el => el.getBoundingClientRect()).filter(r => r.bottom > 0 && r.top < H && r.width > 0);
      }
      function occlusion(x, y) {          // 1 in open water, down to 0.32 over a card or the header
        let f = 0;
        for (const r of rects) {
          const inside = Math.min(x - r.left, r.right - x, y - r.top, r.bottom - y);
          if (inside > -8) f = Math.max(f, clamp((inside + 8) / 26, 0, 1));
        }
        return 1 - 0.68 * f;
      }
      const wrapX = b => { if (b.x < -30) b.x += W + 60; else if (b.x > W + 30) b.x -= W + 60; };

      function update(dt, t, st) {
        eyeD = 1 + 0.12 * st.tide;
        const surge = 7 * st.storm * Math.cos(t * 0.5);
        const drift = (x, y) => 7 * Math.sin(y * 0.0035 + t * 0.21) + 4 * Math.sin(t * 0.11 + x * 0.0021) + surge;
        if (S.layers.back) {
          for (const src of sources) {
            const sx = W * src.base + 26 * Math.sin(t * 0.07 + src.phase);
            if (src.left > 0) {
              src.gap -= dt;
              if (src.gap <= 0) { bubbles.push(newStream(sx)); src.left--; src.gap = 0.09 + Math.random() * 0.07; }
            } else {
              src.next -= dt;
              if (src.next <= 0) { src.left = 6 + Math.floor(Math.random() * 9); src.gap = 0; src.next = 3 + Math.random() * 4; }
            }
          }
        }
        for (let i = bubbles.length - 1; i >= 0; i--) {
          const b = bubbles[i];
          b.y -= b.vy * dt;
          b.x += drift(b.x, b.y) * dt * b.k;
          if (b.y < popY(b.dist) - 4) {
            if (b.stream) bubbles.splice(i, 1); else Object.assign(b, newBubble(false, false));
          } else wrapX(b);
        }
        for (const b of fronts) {
          b.y -= b.vy * dt;
          b.x += drift(b.x, b.y) * dt * b.k;
          if (b.y < -40) Object.assign(b, newBubble(true, false)); else wrapX(b);
        }
      }

      function drawBubble(ctx, b, t, alpha, sprite) {
        const span = Math.max(1, H - popY(b.dist));
        let rr = b.r0 * b.k * (1 + 0.15 * clamp(1 - (b.y - popY(b.dist)) / span, 0, 1));   // grows as pressure drops
        const x = b.x + b.amp * Math.sin(b.ph + t * b.freq);
        const squash = b.r0 > 3.6 ? 0.07 * Math.sin(b.ph * 1.7 + t * b.freq * 2) : 0;
        const size = rr * 2 * SPR_K;
        const w = size * (1 + squash), h = size * (1 - squash);
        ctx.globalAlpha = alpha;
        ctx.drawImage(sprite, x - w / 2, b.y - h / 2, w, h);
      }

      function draw(t, st, theme, underlay) {
        for (const ctx of [bctx, fctx]) {
          ctx.setTransform(1, 0, 0, 1, 0, 0);
          ctx.clearRect(0, 0, back.width, back.height);
          ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        }
        if (underlay) { underlay(bctx); bctx.globalAlpha = 1; }   // sea life sits behind the bubbles
        if (!sprites) return;
        const lit = Math.min(1.2, 0.45 + 0.55 * st.dayF + 0.6 * st.flash);

        if (S.layers.back) {
          bubbles.sort((a, b) => a.z - b.z);
          for (const b of bubbles) {
            const py = popY(b.dist);
            let a = (0.35 + 0.65 * b.z) * lit;
            a *= clamp((H + 8 - b.y) / 70, 0, 1);
            a *= clamp((b.y - py) / (30 * b.k + 6), 0, 1);
            if (a > 0.01) drawBubble(bctx, b, t, Math.min(1, a), b.z < 0.3 ? sprites.soft : sprites.sharp);
          }
        }
        if (S.layers.front) {
          for (const b of fronts) {
            const a = 0.9 * Math.min(1, lit) * clamp((H + 8 - b.y) / 70, 0, 1) * occlusion(b.x, b.y);
            if (a > 0.01) drawBubble(fctx, b, t, a, sprites.sharp);
          }
        }
        bctx.globalAlpha = 1; fctx.globalAlpha = 1;
      }

      // Hand-off: the next page's bubbles carry on from these, scaled if the window changed size.
      function snapshot() {
        return { W, H, bubbles, fronts, sources: sources.map(s => ({ next: s.next, left: s.left, gap: s.gap })) };
      }
      function restore(d) {
        const fine = b => b && ["x", "y", "vy", "z", "dist", "k", "r0", "amp", "freq", "ph"].every(n => Number.isFinite(b[n]));
        const sx = W / d.W, sy = H / d.H;
        const fit = list => list.filter(fine).map(b => Object.assign(b, { x: b.x * sx, y: b.y * sy }));
        bubbles.splice(0, bubbles.length, ...fit(d.bubbles));
        fronts.splice(0, fronts.length, ...fit(d.fronts));
        d.sources.forEach((s, i) => { if (sources[i]) Object.assign(sources[i], s); });
        populate(false);
      }
      return { makeSprites, resize, update, draw, updateRects, snapshot, restore, counts: () => [bubbles.length, fronts.length] };
    })();


    // ── Sea life: distant animals that travel sideways, so nothing reads as a bubble ──
    // Sightings are scheduled from the real clock (like lightning), so every open page sees the same ones.
    // Each animal is painted solid on a scratch canvas, then placed on the water once, tinted toward the
    // water around it and faded with distance. Edges stay sharp, as they would through a dive mask.
    const life = (() => {
      const RATE = {                       // [slot length in seconds, chance of a sighting per slot]
        occasional: { school: [60, 0.85], big: [420, 0.9], jelly: [35, 0.9] },
        lively: { school: [12, 0.85], big: [84, 0.9], jelly: [7, 0.9] },
      };
      const CAP = { school: 5, big: 2, jelly: 10 };   // most on screen at once, per kind
      const SEED = { school: 11.3, big: 47.9, jelly: 83.1 };
      const LOOKBACK_S = 240;              // nothing stays on screen longer than this
      const COL = {
        dark: {
          fish: [95, 142, 162], flash: [205, 238, 248], flashMax: 0.8,
          manta: { edge: [62, 78, 94], belly: [206, 218, 224], spot: [96, 106, 116] },
          dolphin: { back: [70, 86, 100], belly: [184, 198, 206] },
          turtle: { shell: [98, 102, 90], shellEdge: [128, 130, 112], skin: [112, 124, 118], plastron: [158, 164, 152], scute: [72, 76, 66] },
          jelly: { core: "rgba(200,230,255,0.55)", body: "rgba(140,180,255,0.26)", rim: "rgba(175,210,255,0.6)", line: "rgb(150,190,255)", glow: [120, 170, 255] },
        },
        light: {
          fish: [20, 74, 94], flash: [150, 195, 210], flashMax: 0.6,
          manta: { edge: [26, 38, 50], belly: [230, 236, 240], spot: [84, 96, 108] },
          dolphin: { back: [56, 70, 84], belly: [210, 218, 224] },
          turtle: { shell: [72, 78, 70], shellEdge: [104, 108, 96], skin: [90, 102, 98], plastron: [168, 174, 164], scute: [52, 56, 50] },
          jelly: { core: "rgba(255,255,255,0.55)", body: "rgba(95,105,175,0.22)", rim: "rgba(70,80,150,0.5)", line: "rgb(70,80,150)", glow: [120, 130, 210] },
        },
      };
      const cache = new Map();             // slot id -> event or null
      const accepted = { school: [], big: [], jelly: [] };
      const schools = new Map();           // event id -> fish
      let handed = null;                   // event id -> fish placed relative to their leader, from the previous page
      let forced = [], active = [];
      let W = 1, H = 1, dpr = 1, glow = null, glowTheme = "";
      const kOf = z => 1.2 / (3.4 + (0.55 - 3.4) * z);   // same depth scale as the bubbles
      const rgb = c => `rgb(${c[0] | 0},${c[1] | 0},${c[2] | 0})`;

      // ── Scheduling ──
      function makeEvent(kind, start, r) {
        const ev = { kind, start, dir: r(1) < 0.5 ? 1 : -1, ph: r(2) * TAU };
        if (kind === "school") {
          ev.z = 0.15 + r(3) * 0.35; ev.k = kOf(ev.z);
          ev.speed = (34 + 22 * r(4)) * ev.k;
          ev.y0 = 0.42 + r(5) * 0.4;         // lower half: most pages have open water there
          ev.n = 16 + Math.floor(r(6) * 18);
          ev.size = (20 + 8 * r(7)) * ev.k;
          ev.margin = 160;
        } else if (kind === "big") {
          const pick = r(3);
          ev.sub = pick < 0.4 ? "ray" : pick < 0.75 ? "dolphins" : "turtle";
          ev.z = 0.1 + r(4) * 0.2; ev.k = kOf(ev.z);
          ev.y0 = 0.5 + r(5) * 0.32;
          ev.pod = 3 + Math.floor(r(6) * 4);
          ev.offs = [];
          for (let i = 0; i < 6; i++) {
            ev.offs.push({ x: (i - 2.5) * 0.95 + (r(11 + i) - 0.5) * 0.5, y: (r(21 + i) - 0.5) * 1.1, p: r(31 + i) * TAU, s: r(41 + i) });
          }
          sizeBig(ev);
        } else {
          ev.z = 0.2 + r(3) * 0.4; ev.k = kOf(ev.z);
          ev.size = (18 + 14 * r(4)) * ev.k;
          ev.x0 = 0.1 + r(5) * 0.8;
          ev.y0 = 0.5 + r(6) * 0.35;
          ev.life = 120 + 50 * r(7);
        }
        return ev;
      }
      function sizeBig(ev) {
        if (ev.sub === "ray") { ev.size = 200 * ev.k; ev.speed = 40 * ev.k; ev.margin = ev.size; }
        else if (ev.sub === "turtle") { ev.size = 240 * ev.k; ev.speed = 30 * ev.k; ev.margin = ev.size; }
        else { ev.size = 150 * ev.k; ev.speed = 75 * ev.k; ev.margin = ev.size * 3.5; }
      }
      const duration = ev => ev.kind === "jelly" ? ev.life : (W + 2 * ev.margin) / ev.speed;
      const endOf = ev => ev.start + duration(ev) * 1000;
      function allowed(kind, st) {
        if (kind === "school") return st.dayF > 0.35 && st.storm < 0.3;   // fish clear out in storms
        if (kind === "big") return st.dayF > 0.25 && st.storm < 0.4;
        return st.dayF < 0.3;                                             // jellyfish are a night thing
      }
      function scheduled(now) {
        const rate = RATE[S.life], out = [];
        if (!rate) return out;
        if (cache.size > 2000) reset();
        for (const kind of ["school", "big", "jelly"]) {
          const [slot, p] = rate[kind];
          const slotMs = slot * 1000, cur = Math.floor(now / slotMs);
          // look back twice as far as anything lasts, so the on-screen cap is decided the same way on every page
          for (let s = cur - Math.ceil((2 * LOOKBACK_S) / slot) - 1; s <= cur; s++) {
            const id = `${kind}:${S.life}:${s}`;
            let ev = cache.get(id);
            if (ev === undefined) {
              const r = i => hash1(s * 1.731 + SEED[kind] + i * 17.17);
              ev = null;
              if (r(0) < p) {
                const e = makeEvent(kind, (s + r(9) * 0.6) * slotMs, r);
                if (allowed(kind, sceneState(e.start))) {
                  const list = accepted[kind];
                  const overlapping = list.filter(o => o.start <= e.start && endOf(o) > e.start).length;
                  if (overlapping < CAP[kind]) { e.id = id; ev = e; list.push(e); }
                }
              }
              cache.set(id, ev);
            }
            if (ev && now >= ev.start && now <= endOf(ev)) out.push(ev);
          }
          accepted[kind] = accepted[kind].filter(o => endOf(o) > now - 2 * LOOKBACK_S * 1000);
        }
        return out;
      }
      function reset() {
        cache.clear();
        accepted.school = []; accepted.big = []; accepted.jelly = [];
      }
      function summon(kind, mid, y) {      // lab buttons: a visitor right now, already entering the screen
        const big = kind === "ray" || kind === "turtle" || kind === "dolphins";
        const ev = makeEvent(big ? "big" : kind, 0, () => Math.random());
        if (big) { ev.sub = kind; sizeBig(ev); }
        if (y != null && !isNaN(y)) ev.y0 = y;
        ev.id = "summon:" + Math.random();
        const now = Date.now();
        if (ev.kind === "jelly") ev.start = now - (mid ? 20000 : 3000);
        else ev.start = now - (mid ? duration(ev) * 0.45 : (ev.margin / ev.speed) * 0.8) * 1000;
        forced.push(ev);
      }

      // ── Motion ──
      function pathPos(ev, tau) {
        if (ev.kind === "jelly") {       // pulses upward, sinks a little between pulses, drifts with the current
          return {
            x: ev.x0 * W + 14 * ev.k * Math.sin(0.07 * tau + ev.ph),
            y: ev.y0 * H - ev.k * (5 * tau + 3.4 * Math.sin(1.6 * tau)),
          };
        }
        const amp = ev.kind === "school" ? 0.06 : 0.03;
        return {
          x: (ev.dir > 0 ? -ev.margin : W + ev.margin) + ev.dir * ev.speed * tau,
          y: (ev.y0 + amp * Math.sin(tau * 0.09 + ev.ph) + amp * 0.5 * Math.sin(tau * 0.23 + ev.ph * 2)) * H,
        };
      }
      function dolphinPos(ev, i, tau) {  // each dolphin porpoises: rises and dips, nose following the motion
        const o = ev.offs[i], L = ev.size, lead = pathPos(ev, tau);
        const w = 1.2 + 0.25 * o.s;
        const bob = 0.24 * L * Math.sin(tau * w + o.p);
        const vy = 0.24 * L * w * Math.cos(tau * w + o.p);
        return { x: lead.x + ev.dir * o.x * L, y: lead.y + o.y * L + bob, pitch: Math.atan2(vy, ev.speed) };
      }

      // A school follows its leader's path; each fish keeps a loose place in formation,
      // matches its neighbours' heading and keeps its distance.
      function schoolFish(ev, now) {
        let fish = schools.get(ev.id);
        if (fish) return fish;
        const lead = pathPos(ev, (now - ev.start) / 1000);
        if (handed && handed[ev.id]) {       // the same school on the previous page: same formation, where the leader is now
          fish = handed[ev.id].map(f => Object.assign(f, { x: lead.x + f.x, y: lead.y + f.y }));
          schools.set(ev.id, fish);
          return fish;
        }
        fish = [];
        for (let i = 0; i < ev.n; i++) {
          const a = Math.random() * TAU, rr = Math.sqrt(Math.random());
          const off = { x: Math.cos(a) * rr * ev.size * 4.2, y: Math.sin(a) * rr * ev.size * 1.9 };
          fish.push({
            off, x: lead.x + off.x, y: lead.y + off.y, vx: ev.dir * ev.speed, vy: 0,
            head: ev.dir > 0 ? 0 : Math.PI, flash: 0, ph: Math.random() * TAU, len: ev.size * (0.8 + 0.4 * Math.random()),
          });
        }
        schools.set(ev.id, fish);
        return fish;
      }
      function updateSchool(ev, fish, now, dt, t) {
        const tau = (now - ev.start) / 1000;
        const lead = pathPos(ev, tau), ahead = pathPos(ev, tau + 0.5);
        const lvx = (ahead.x - lead.x) / 0.5, lvy = (ahead.y - lead.y) / 0.5;
        const sepR = ev.size * 0.9, alignR = ev.size * 3;
        for (let i = 0; i < fish.length; i++) {
          const f = fish[i];
          const breathe = 1 + 0.18 * Math.sin(t * 0.6 + f.ph);
          let ax = (lead.x + f.off.x * breathe - f.x) * 0.9 + (lvx - f.vx) * 0.6;
          let ay = (lead.y + f.off.y * breathe - f.y) * 0.9 + (lvy - f.vy) * 0.6;
          let avx = 0, avy = 0, cnt = 0;
          for (let j = 0; j < fish.length; j++) {
            if (i === j) continue;
            const o = fish[j], dx = f.x - o.x, dy = f.y - o.y, d2 = dx * dx + dy * dy;
            if (d2 < alignR * alignR) { avx += o.vx; avy += o.vy; cnt++; }
            if (d2 < sepR * sepR && d2 > 0.01) { const d = Math.sqrt(d2); ax += (dx / d) * (sepR - d) * 4; ay += (dy / d) * (sepR - d) * 4; }
          }
          if (cnt) { ax += (avx / cnt - f.vx) * 0.8; ay += (avy / cnt - f.vy) * 0.8; }
          ax += Math.sin(t * 1.3 + f.ph * 3) * ev.size * 0.6;
          ay += Math.cos(t * 1.1 + f.ph * 2) * ev.size * 0.4;
          f.vx += ax * dt; f.vy += ay * dt;
          const sp = Math.hypot(f.vx, f.vy), maxS = ev.speed * 1.8, minS = ev.speed * 0.5;
          if (sp > maxS) { f.vx *= maxS / sp; f.vy *= maxS / sp; }
          else if (sp < minS && sp > 0) { f.vx *= minS / sp; f.vy *= minS / sp; }
          f.x += f.vx * dt; f.y += f.vy * dt;
          let dh = Math.atan2(f.vy, f.vx) - f.head;
          dh = Math.atan2(Math.sin(dh), Math.cos(dh));
          f.head += dh * Math.min(1, dt * 6);
          // flanks catch the light when a fish turns
          f.flash = Math.max(f.flash * Math.exp(-dt * 4), clamp((Math.abs(dh) / Math.max(dt, 1e-3)) * 0.15, 0, 1));
        }
      }
      function update(now, dt, t) {
        forced = forced.filter(ev => now <= endOf(ev));
        active = scheduled(now).concat(forced);
        const live = new Set();
        for (const ev of active) {
          if (ev.kind !== "school") continue;
          live.add(ev.id);
          const fish = schoolFish(ev, now);
          if (dt > 0) updateSchool(ev, fish, now, dt, t);   // a still frame only places them
        }
        for (const id of schools.keys()) if (!live.has(id)) schools.delete(id);
        handed = null;
      }
      // Hand-off: fish are kept relative to their leader, since the leader follows the clock. The
      // sightings already decided go too: worked out afresh from a later start, the on-screen cap
      // can pick different ones, and a school would vanish while another appeared.
      function snapshot(now) {
        const out = {}, decided = [], rate = RATE[S.life];
        for (const ev of active) {
          const fish = ev.kind === "school" && schools.get(ev.id);
          if (!fish) continue;
          const lead = pathPos(ev, (now - ev.start) / 1000);
          out[ev.id] = fish.map(f => Object.assign({}, f, { x: f.x - lead.x, y: f.y - lead.y }));
        }
        if (rate) {
          for (const [id, ev] of cache) {
            const [kind, , s] = id.split(":"), slot = rate[kind][0];
            if (Number(s) >= Math.floor(now / (slot * 1000)) - Math.ceil((2 * LOOKBACK_S) / slot) - 1) decided.push([id, ev]);
          }
        }
        return { schools: out, forced, decided };
      }
      function restore(d) {
        const fine = f => f && f.off && ["x", "y", "vx", "vy", "head", "flash", "ph", "len"].every(n => Number.isFinite(f[n]));
        handed = {};
        schools.clear();                   // a page brought back by Back has its own, older fish
        for (const [id, fish] of Object.entries(d.schools)) if (Array.isArray(fish) && fish.every(fine)) handed[id] = fish;
        forced = d.forced.filter(ev => ev && typeof ev.id === "string" && Number.isFinite(ev.start));
        reset();
        for (const [id, ev] of d.decided) {
          const [kind, life] = id.split(":");
          if (life !== S.life || !accepted[kind] || (ev && !Number.isFinite(ev.start))) continue;
          cache.set(id, ev);
          if (ev) accepted[kind].push(ev);
        }
      }

      // ── Painting helpers ──
      const stamp = document.createElement("canvas");
      const sctx = stamp.getContext("2d");
      const canFilter = "filter" in sctx;
      function composite(ctx, box, alpha, blur, paint) {
        const pad = 4 + blur * 3;
        const bx = Math.floor(box[0] - pad), by = Math.floor(box[1] - pad);
        const bw = Math.ceil(box[2] + pad - bx), bh = Math.ceil(box[3] + pad - by);
        if (alpha <= 0.01 || bw <= 0 || bh <= 0 || bx > W || by > H || bx + bw < 0 || by + bh < 0) return;
        const pw = Math.ceil(bw * dpr), ph = Math.ceil(bh * dpr);
        if (stamp.width < pw) stamp.width = pw;
        if (stamp.height < ph) stamp.height = ph;
        sctx.setTransform(1, 0, 0, 1, 0, 0);
        sctx.clearRect(0, 0, pw, ph);
        sctx.globalAlpha = 1;
        sctx.setTransform(dpr, 0, 0, dpr, -bx * dpr, -by * dpr);
        paint(sctx);
        ctx.save();
        ctx.globalAlpha = alpha;
        if (canFilter && blur > 0.15) ctx.filter = `blur(${blur.toFixed(2)}px)`;
        ctx.drawImage(stamp, 0, 0, pw, ph, bx, by, bw, bh);
        ctx.restore();
      }
      // A closed curve through the midpoints of a point list; a repeated point makes a sharp tip.
      function smoothPath(c, pts) {
        const n = pts.length;
        c.beginPath();
        c.moveTo((pts[n - 1][0] + pts[0][0]) / 2, (pts[n - 1][1] + pts[0][1]) / 2);
        for (let i = 0; i < n; i++) {
          const p = pts[i], q = pts[(i + 1) % n];
          c.quadraticCurveTo(p[0], p[1], (p[0] + q[0]) / 2, (p[1] + q[1]) / 2);
        }
        c.closePath();
      }
      function waterAt(u, y) {           // the water color behind an animal, matching the shader's gradient
        const d = clamp(y / H, 0, 1);
        let c = mix3(u.top, u.mid, smooth(0, 0.5, d));
        c = mix3(c, u.deep, smooth(0.4, 1, d));
        return scale3(c, 255);
      }

      // ── Animals ──
      function drawFish(c, f, t) {
        const L = f.len, wag = Math.sin(t * 9 + f.ph) * L * 0.12;
        c.save();
        c.translate(f.x, f.y);
        c.rotate(f.head);
        c.beginPath(); c.ellipse(0, 0, L * 0.5, L * 0.16, 0, 0, TAU); c.fill();
        c.beginPath();
        c.moveTo(-L * 0.4, 0);
        c.lineTo(-L * 0.72, -L * 0.17 + wag);
        c.lineTo(-L * 0.64, wag * 0.5);
        c.lineTo(-L * 0.72, L * 0.17 + wag);
        c.closePath(); c.fill();
        c.restore();
      }

      // Manta seen from below: white belly with dark margins, gill slits, curled head fins.
      // The wings flex in a wave from body to tip, and look narrower at the top and bottom of each beat.
      function drawManta(c, x, y, head, S0, t, ph, C, hz, haze) {
        const beat = t * 1.1 + ph;
        const lag = Math.sin(beat - 0.9);
        const span = S0 * (0.47 + 0.07 * Math.cos(beat));
        const tipX = -S0 * 0.04 + S0 * 0.09 * lag;
        const edgeC = mix3(C.edge, hz, haze), edge = rgb(edgeC);
        const belly = mix3(C.belly, hz, haze);
        c.save();
        c.translate(x, y);
        c.rotate(head);
        const half = sg => [
          [S0 * 0.30, sg * S0 * 0.075],
          [S0 * 0.22, sg * span * 0.45],
          [tipX + S0 * 0.07, sg * span * 0.93],
          [tipX, sg * span], [tipX, sg * span],
          [tipX - S0 * 0.045, sg * span * 0.8],
          [-S0 * 0.1, sg * span * 0.42],
          [-S0 * 0.2, sg * S0 * 0.1],
          [-S0 * 0.25, sg * S0 * 0.045],
        ];
        const outline = [...half(1), [-S0 * 0.27, 0], ...half(-1).reverse(), [S0 * 0.315, 0]];
        c.fillStyle = edge;
        smoothPath(c, outline); c.fill();
        const inset = 0.74 + 0.06 * Math.cos(beat);
        const bellyPts = outline.map(([px, py]) => [px * 0.84 - S0 * 0.01, py * inset]);
        const g = c.createRadialGradient(S0 * 0.06, 0, S0 * 0.04, S0 * 0.02, 0, span * 0.8);
        g.addColorStop(0, rgb(belly));
        g.addColorStop(0.7, rgb(belly));
        g.addColorStop(1, rgb(mix3(belly, edgeC, 0.85)));
        c.fillStyle = g;
        smoothPath(c, bellyPts); c.fill();
        c.strokeStyle = edge;
        c.lineCap = "round";
        c.lineWidth = Math.max(0.6, S0 * 0.008);
        for (let i = 0; i < 5; i++) {
          const gx = S0 * (0.14 - i * 0.026);
          for (const sg of [1, -1]) {
            c.beginPath();
            c.moveTo(gx, sg * S0 * 0.045);
            c.quadraticCurveTo(gx - S0 * 0.01, sg * S0 * 0.07, gx - S0 * 0.004, sg * S0 * 0.096);
            c.stroke();
          }
        }
        c.beginPath();
        c.moveTo(S0 * 0.292, -S0 * 0.052);
        c.quadraticCurveTo(S0 * 0.312, 0, S0 * 0.292, S0 * 0.052);
        c.stroke();
        c.fillStyle = rgb(mix3(C.spot, hz, haze));
        for (let i = 0; i < 4; i++) {
          const sx = S0 * (0.0 - 0.05 * i + 0.02 * Math.sin(ph * 3 + i)), sy = S0 * 0.05 * Math.sin(ph * 5 + i * 2.1);
          c.beginPath(); c.arc(sx, sy, S0 * (0.008 + 0.006 * ((i + 1) % 2)), 0, TAU); c.fill();
        }
        c.fillStyle = edge;
        for (const sg of [1, -1]) {
          smoothPath(c, [[S0 * 0.29, sg * S0 * 0.05], [S0 * 0.36, sg * S0 * 0.088], [S0 * 0.405, sg * S0 * 0.072],
                         [S0 * 0.385, sg * S0 * 0.048], [S0 * 0.31, sg * S0 * 0.034]]);
          c.fill();
        }
        c.lineWidth = Math.max(0.8, S0 * 0.01);
        c.beginPath();
        c.moveTo(-S0 * 0.25, 0);
        c.quadraticCurveTo(-S0 * 0.45, Math.sin(beat + 1.4) * S0 * 0.03, -S0 * 0.68, Math.sin(beat + 2.2) * S0 * 0.02);
        c.stroke();
        c.restore();
      }

      // Dolphin in side profile, nose at +x. The tail beats up and down, which is how dolphins swim.
      function dolphinPts(L, bend) {
        const P = [
          [0.53, 0.045], [0.53, 0.045],                                     // tip of the beak
          [0.45, 0.022], [0.39, -0.05], [0.3, -0.1],                       // melon and forehead
          [0.12, -0.125], [0.03, -0.13],                                    // back
          [-0.04, -0.2], [-0.09, -0.255], [-0.09, -0.255], [-0.08, -0.16], // dorsal fin, swept back
          [-0.16, -0.105], [-0.32, -0.055], [-0.42, -0.03],                // tail stock
          [-0.5, -0.05], [-0.585, -0.075], [-0.585, -0.075], [-0.53, -0.01], // upper fluke
          [-0.575, 0.04], [-0.575, 0.04], [-0.47, 0.012],                   // lower fluke, seen at an angle
          [-0.38, 0.03], [-0.2, 0.075], [-0.02, 0.112], [0.2, 0.1], [0.36, 0.072], [0.46, 0.06],
        ];
        return P.map(([px, py]) => {
          const tail = Math.max(0, -px - 0.05);
          return [px * L, (py + bend * tail * tail * 1.6) * L];
        });
      }
      function drawDolphin(c, x, y, dir, pitch, L, t, ph, C, hz, haze) {
        const beat = Math.sin(t * 3.2 + ph);
        const back = mix3(C.back, hz, haze), belly = mix3(C.belly, hz, haze);
        c.save();
        c.translate(x, y);
        c.scale(dir, 1);
        c.rotate(pitch);
        const g = c.createLinearGradient(0, -0.13 * L, 0, 0.11 * L);
        g.addColorStop(0, rgb(back));
        g.addColorStop(0.5, rgb(back));
        g.addColorStop(0.72, rgb(belly));
        g.addColorStop(1, rgb(belly));
        c.fillStyle = g;
        smoothPath(c, dolphinPts(L, 0.2 * beat)); c.fill();
        c.fillStyle = rgb(mix3(back, belly, 0.25));
        smoothPath(c, [[0.25 * L, 0.06 * L], [0.17 * L, 0.15 * L], [0.17 * L, 0.15 * L], [0.12 * L, 0.1 * L], [0.17 * L, 0.06 * L]]);
        c.fill();
        c.fillStyle = rgb(mix3(back, [0, 0, 0], 0.5));
        c.beginPath(); c.arc(0.355 * L, -0.02 * L, Math.max(0.6, 0.012 * L), 0, TAU); c.fill();
        c.restore();
      }

      // Sea turtle in side view: domed shell over a pale underside, beaked head, long front flippers that
      // beat together like wings. Far flippers are drawn behind the shell, near flippers in front of it.
      function flipperPts(len, w0, camber) {   // a short paddle: narrow at the wrist, broad blade, rounded end
        const top = [], bot = [], cap = [];
        const blade = len * 0.78, capLen = len - blade;
        const curve = x => camber * len * (x / len) * (x / len);
        for (let i = 0; i <= 5; i++) {
          const u = i / 5, x = u * blade;
          const hw = w0 * (0.6 + 0.4 * Math.sin((Math.PI / 2) * u));
          top.push([x, curve(x) - hw]);
          bot.push([x, curve(x) + hw]);
        }
        for (const a of [-1.1, -0.45, 0.45, 1.1]) cap.push([blade + capLen * Math.cos(a) * 1.25, curve(blade) + w0 * Math.sin(a) * 1.05]);
        return [...top, ...cap, ...bot.reverse()];
      }
      function drawFlipper(c, sx, sy, ang, len, w0, camber, col) {
        c.save();
        c.translate(sx, sy);
        c.rotate(ang);
        c.fillStyle = col;
        smoothPath(c, flipperPts(len, w0, camber));
        c.fill();
        c.restore();
      }
      function drawTurtle(c, x, y, dir, L, t, ph, C, hz, haze) {
        const s = Math.sin(t * 0.9 + ph);
        const frontAng = Math.PI - 0.62 + 0.68 * s;          // pointing back; sweeps from level to down, never up past the shell
        const rearAng = Math.PI - 0.35 + 0.2 * Math.sin(t * 0.9 + ph + 1.2);
        const pitch = 0.05 * Math.sin(t * 0.9 + ph + 0.6);
        const skin = mix3(C.skin, hz, haze), skinFar = mix3(skin, hz, 0.3);
        const shell = mix3(C.shell, hz, haze), shellEdge = mix3(C.shellEdge, hz, haze);
        c.save();
        c.translate(x, y);
        c.scale(dir, 1);
        c.rotate(pitch);
        drawFlipper(c, 0.12 * L, -0.02 * L, frontAng - 0.3, 0.33 * L, 0.078 * L, 0.1, rgb(skinFar));
        drawFlipper(c, -0.22 * L, 0, rearAng - 0.25, 0.13 * L, 0.045 * L, 0.06, rgb(skinFar));
        c.fillStyle = rgb(skin);
        smoothPath(c, [[0.24 * L, -0.03 * L], [0.36 * L, -0.07 * L], [0.46 * L, -0.078 * L], [0.535 * L, -0.03 * L],
                       [0.535 * L, -0.03 * L], [0.5 * L, 0.002 * L], [0.42 * L, 0.03 * L], [0.3 * L, 0.07 * L]]);
        c.fill();
        const g = c.createLinearGradient(0, -0.19 * L, 0, 0.08 * L);
        g.addColorStop(0, rgb(shell));
        g.addColorStop(0.75, rgb(mix3(shell, shellEdge, 0.6)));
        g.addColorStop(1, rgb(shellEdge));
        c.fillStyle = g;
        smoothPath(c, [[0.3 * L, 0.03 * L], [0.27 * L, -0.08 * L], [0.12 * L, -0.18 * L], [-0.08 * L, -0.185 * L],
                       [-0.27 * L, -0.1 * L], [-0.37 * L, 0], [-0.37 * L, 0], [-0.26 * L, 0.06 * L], [0, 0.085 * L], [0.22 * L, 0.07 * L]]);
        c.fill();
        c.fillStyle = rgb(mix3(C.plastron, hz, haze));
        smoothPath(c, [[0.25 * L, 0.045 * L], [0, 0.062 * L], [-0.26 * L, 0.045 * L], [-0.23 * L, 0.072 * L], [0, 0.094 * L], [0.21 * L, 0.078 * L]]);
        c.fill();
        c.strokeStyle = rgb(mix3(C.scute, hz, haze));
        c.lineWidth = Math.max(0.6, 0.012 * L);
        c.globalAlpha = 0.35;
        for (const sx of [-0.16, 0, 0.15]) {
          c.beginPath();
          c.moveTo((sx - 0.03) * L, -0.17 * L);
          c.quadraticCurveTo((sx + 0.02) * L, -0.07 * L, (sx - 0.02) * L, 0.035 * L);
          c.stroke();
        }
        c.beginPath();
        c.moveTo(-0.29 * L, -0.055 * L);
        c.quadraticCurveTo(0, -0.115 * L, 0.25 * L, -0.055 * L);
        c.stroke();
        c.globalAlpha = 1;
        drawFlipper(c, -0.21 * L, 0.045 * L, rearAng, 0.15 * L, 0.05 * L, 0.06, rgb(skin));
        drawFlipper(c, 0.14 * L, 0.045 * L, frontAng, 0.36 * L, 0.085 * L, 0.12, rgb(skin));
        c.fillStyle = rgb(mix3(skin, [0, 0, 0], 0.6));
        c.beginPath(); c.arc(0.46 * L, -0.045 * L, Math.max(0.6, 0.012 * L), 0, TAU); c.fill();
        c.restore();
      }

      function makeGlow(theme) {
        const c = COL[theme].jelly.glow;
        glow = document.createElement("canvas");
        glow.width = glow.height = 64;
        const g = glow.getContext("2d");
        const gr = g.createRadialGradient(32, 32, 0, 32, 32, 32);
        gr.addColorStop(0, `rgba(${c[0]},${c[1]},${c[2]},0.5)`);
        gr.addColorStop(0.4, `rgba(${c[0]},${c[1]},${c[2]},0.16)`);
        gr.addColorStop(1, `rgba(${c[0]},${c[1]},${c[2]},0)`);
        g.fillStyle = gr;
        g.fillRect(0, 0, 64, 64);
        glowTheme = theme;
      }
      function drawJelly(ctx, ev, x, y, tau, t, alpha, C) {
        const r0 = ev.size;
        const c = Math.max(0, Math.cos(1.6 * tau));      // the bell squeezes while it pushes upward
        const rw = r0 * (1 - 0.14 * c), rh = r0 * (0.78 + 0.16 * c);
        const g = r0 * 3.2;
        ctx.globalAlpha = alpha * 0.55;
        ctx.drawImage(glow, x - g, y - g * 0.8, g * 2, g * 2);
        ctx.globalAlpha = alpha * 0.5;
        ctx.strokeStyle = C.line;
        ctx.lineWidth = Math.max(0.6, r0 * 0.05);
        for (let i = 0; i < 6; i++) {
          const bx = x + (i / 5 - 0.5) * rw * 1.5;
          ctx.beginPath();
          ctx.moveTo(bx, y);
          for (let j = 1; j <= 10; j++) {
            ctx.lineTo(bx + Math.sin(j * 0.55 - t * 1.7 + i * 1.3) * r0 * 0.22 * (j / 10), y + j * r0 * 0.28 * (1 + 0.15 * c));
          }
          ctx.stroke();
        }
        ctx.globalAlpha = alpha;
        const grad = ctx.createRadialGradient(x, y - rh * 0.4, rh * 0.1, x, y - rh * 0.2, rw * 1.1);
        grad.addColorStop(0, C.core);
        grad.addColorStop(0.7, C.body);
        grad.addColorStop(1, C.rim);
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.ellipse(x, y, rw, rh, 0, Math.PI, 0);
        ctx.quadraticCurveTo(x + rw * 0.5, y + rh * 0.18, x, y + rh * 0.08);
        ctx.quadraticCurveTo(x - rw * 0.5, y + rh * 0.18, x - rw, y);
        ctx.fill();
      }

      function draw(ctx, now, t, st, theme, u) {
        if (!active.length) return;
        if (glowTheme !== theme) makeGlow(theme);
        const C = COL[theme];
        const daylight = 0.3 + 0.7 * st.dayF;
        for (const ev of active) {
          const tau = (now - ev.start) / 1000;
          const far = clamp(ev.z / 0.5, 0, 1);                       // 0 farthest .. 1 nearest
          if (ev.kind === "school") {
            const fish = schools.get(ev.id);
            if (!fish || !fish.length) continue;
            let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
            for (const f of fish) { x0 = Math.min(x0, f.x - f.len); y0 = Math.min(y0, f.y - f.len); x1 = Math.max(x1, f.x + f.len); y1 = Math.max(y1, f.y + f.len); }
            const hz = waterAt(u, (y0 + y1) / 2), haze = 0.5 - 0.3 * far;
            composite(ctx, [x0, y0, x1, y1], 0.5 * daylight, 0, c => {
              for (const f of fish) {
                c.fillStyle = rgb(mix3(mix3(C.fish, C.flash, f.flash * C.flashMax), hz, haze));
                drawFish(c, f, t);
              }
            });
          } else if (ev.kind === "big") {
            const haze = 0.55 - 0.25 * far, blur = 0, alpha = 0.78 * daylight;   // distance shows as haze, not blur
            if (ev.sub === "dolphins") {
              const pos = [];
              for (let i = 0; i < ev.pod; i++) pos.push(dolphinPos(ev, i, tau));
              const L = ev.size;
              const box = [Math.min(...pos.map(p => p.x)) - 0.7 * L, Math.min(...pos.map(p => p.y)) - 0.5 * L,
                           Math.max(...pos.map(p => p.x)) + 0.7 * L, Math.max(...pos.map(p => p.y)) + 0.5 * L];
              const hz = waterAt(u, (box[1] + box[3]) / 2);
              composite(ctx, box, alpha, blur, c => {
                pos.forEach((p, i) => drawDolphin(c, p.x, p.y, ev.dir, p.pitch, L * (0.9 + 0.2 * ev.offs[i].s), t, ev.offs[i].p, C.dolphin, hz, haze));
              });
            } else {
              const p = pathPos(ev, tau), q = pathPos(ev, tau + 0.5);
              const R = ev.size * 0.8, hz = waterAt(u, p.y);
              composite(ctx, [p.x - R, p.y - R, p.x + R, p.y + R], alpha, blur, c => {
                if (ev.sub === "ray") drawManta(c, p.x, p.y, Math.atan2(q.y - p.y, q.x - p.x), ev.size, t, ev.ph, C.manta, hz, haze);
                else drawTurtle(c, p.x, p.y, ev.dir, ev.size, t, ev.ph, C.turtle, hz, haze);
              });
            }
          } else {
            const p = pathPos(ev, tau);
            const fade = clamp(tau / 6, 0, 1) * clamp((ev.life - tau) / 8, 0, 1) * clamp((p.y - 0.12 * H) / (0.1 * H), 0, 1);
            const a = fade * (0.45 + 0.55 * (1 - st.dayF)) * (0.55 + 0.45 * far) * (theme === "dark" ? 1 : 0.8);
            if (a > 0.01) drawJelly(ctx, ev, p.x, p.y, tau, t, a, C.jelly);
          }
        }
        ctx.globalAlpha = 1;
      }
      function describe() {
        if (!active.length) return S.life === "off" ? "Off" : "Nothing in sight right now";
        const names = active.map(ev => ev.kind === "school" ? `a school of ${ev.n} fish`
          : ev.kind === "jelly" ? "a jellyfish"
          : ev.sub === "ray" ? "a manta ray" : ev.sub === "dolphins" ? `a pod of ${ev.pod} dolphins` : "a sea turtle");
        const text = names.join(", ") + " passing";
        return text.charAt(0).toUpperCase() + text.slice(1);
      }
      return {
        update, draw, summon, describe, reset, snapshot, restore,
        resize: (w, h, d) => { W = w; H = h; dpr = d || 1; },
      };
    })();


    // ── Settings panel, opened from any [data-ocean-panel] element ──
    const WAVES_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 9c2.5 0 2.5-2 5-2s2.5 2 5 2 2.5-2 5-2 2.5 2 5 2"/><path d="M2 15c2.5 0 2.5-2 5-2s2.5 2 5 2 2.5-2 5-2 2.5 2 5 2"/></svg>';
    const panel = document.createElement("div");
    panel.className = "ocean-panel";
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-label", "Water background");
    panel.hidden = true;
    panel.innerHTML = `
      <div class="ocean-panel-head">
        <strong>Water background</strong>
        <label class="ocean-switch"><input type="checkbox" data-ocean-on> On</label>
      </div>
      <section>
        <h4>Time of day</h4>
        <div class="ocean-seg" data-set="timeMode"><button type="button" data-val="live">Follow clock</button><button type="button" data-val="manual">Pick a time</button></div>
        <input type="range" min="0" max="24" step="0.25" data-ocean-hour aria-label="Time of day">
        <div class="ocean-readout" data-ocean-time></div>
      </section>
      <section>
        <h4>Weather</h4>
        <div class="ocean-seg" data-set="weather"><button type="button" data-val="auto">Auto</button><button type="button" data-val="clear">Clear</button><button type="button" data-val="cloudy">Cloudy</button><button type="button" data-val="rain">Rain</button><button type="button" data-val="storm">Storm</button></div>
        <div class="ocean-row"><span class="ocean-readout" data-ocean-weather></span><button type="button" class="ocean-mini" data-ocean-flash>Lightning</button></div>
      </section>
      <section>
        <h4>Sea life</h4>
        <div class="ocean-seg" data-set="life"><button type="button" data-val="off">Off</button><button type="button" data-val="occasional">Occasional</button><button type="button" data-val="lively">Lively</button></div>
        <div class="ocean-readout" data-ocean-life></div>
        <div class="ocean-row">
          <span class="ocean-fine">Call a visitor</span>
          <span class="ocean-visitors"><button type="button" class="ocean-mini" data-summon="school">Fish</button><button type="button" class="ocean-mini" data-summon="ray">Manta</button><button type="button" class="ocean-mini" data-summon="dolphins">Dolphins</button><button type="button" class="ocean-mini" data-summon="turtle">Turtle</button><button type="button" class="ocean-mini" data-summon="jelly">Jellyfish</button></span>
        </div>
      </section>
      <section>
        <h4>Cycle speed</h4>
        <div class="ocean-seg" data-set="cycle"><button type="button" data-val="1">Real time</button><button type="button" data-val="60">1 hour/min</button><button type="button" data-val="720">Day in 2 min</button></div>
        <div class="ocean-row"><span class="ocean-fine">Moves the clock, auto weather and tide. Sunrise 6:30, sunset 19:30.</span><button type="button" class="ocean-mini" data-ocean-reset>Reset clock</button></div>
      </section>
      <section>
        <h4>Quality</h4>
        <div class="ocean-seg" data-set="quality"><button type="button" data-val="saver">Battery saver</button><button type="button" data-val="balanced">Balanced</button><button type="button" data-val="full">Full</button></div>
      </section>
      <details class="ocean-details"><summary>Performance</summary><div class="ocean-stats" data-ocean-stats></div></details>`;
    document.body.append(panel);
    if (mount.hasAttribute("data-ocean-fab")) {
      const fab = document.createElement("button");
      fab.type = "button";
      fab.className = "ocean-fab";
      fab.setAttribute("data-ocean-panel", "");
      fab.setAttribute("aria-label", "Water background");
      fab.setAttribute("aria-expanded", "false");
      fab.innerHTML = `${WAVES_SVG}<span>Water</span>`;
      document.body.append(fab);
    }
    const P = sel => panel.querySelector(sel);

    // ── Driver: sizing, frame cap, idle mode, automatic quality ──
    const QUALITY = { saver: { res: 0.35, cap: 20 }, balanced: { res: 0.5, cap: 30 }, full: { res: 1, cap: 60 } };
    const quality = () => QUALITY[S.quality] || QUALITY.balanced;
    const IDLE_MS = 3 * 60 * 1000;
    let theme = "dark";
    let resScale = quality().res, autoLowered = false;
    let raf = 0, last = 0, animT = 20, still = false, booting = true;
    let lastInput = performance.now(), jsMs = 0, frames = 0, winStart = 0, fps = 0, slowWindows = 0;
    let current = sceneState(Date.now());

    function effTheme() {
      const forced = mount.getAttribute("data-ocean-theme");
      if (forced === "dark" || forced === "light") return forced;
      const t = document.documentElement.getAttribute("data-theme");
      if (t === "dark" || t === "light") return t;
      return matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    }
    function applyTheme() {
      theme = effTheme();
      panel.classList.toggle("is-dark", theme === "dark");
      parts.makeSprites(theme);
      renderNow();
    }
    function resizeAll() {
      const w = window.innerWidth, h = window.innerHeight;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      glView.resize(w, h, dpr, resScale);
      life.resize(w, h, dpr);
      parts.resize(w, h, dpr);
      parts.updateRects();
      renderNow();
    }
    function drawFrame() {
      const u = uniformsFor(current, theme);
      const now = Date.now();
      glView.draw(u, animT, 14 * current.storm * Math.sin(animT * 0.5));
      parts.draw(animT, current, theme, ctx => life.draw(ctx, now, animT, current, theme, u));
    }
    const running = () => !!S.on;
    const animating = () => running() && !still && !REDUCED;
    function renderNow() {
      if (booting) return;                 // the page isn't shown until the start below has drawn once
      if (running()) {
        current = sceneState(Date.now());
        life.update(Date.now(), 0, animT);   // so the first frame already has the sea life in it
        drawFrame();
      }
      updatePanel();
    }
    function tick(now) {
      raf = requestAnimationFrame(tick);
      const idle = now - lastInput > IDLE_MS;
      const cap = idle ? 12 : quality().cap;
      if (last && now - last < 1000 / cap - 1.5) return;
      const dt = last ? Math.min(0.1, (now - last) / 1000) : 1 / cap;
      last = now;
      const t0 = performance.now();
      current = sceneState(Date.now());
      // Shader maths loses precision as time grows; restart the wave clock while nobody is watching.
      if (idle && animT > 20000) animT = 20;
      animT += dt * (1 + 0.9 * current.storm + 0.25 * current.rain);
      parts.update(dt, animT, current);
      life.update(Date.now(), dt, animT);
      drawFrame();
      const spent = performance.now() - t0;
      jsMs = jsMs ? jsMs * 0.92 + spent * 0.08 : spent;
      frames++;
      if (!winStart) winStart = now;
      if (now - winStart > 3000) {
        fps = (frames * 1000) / (now - winStart);
        frames = 0; winStart = now;
        if (!idle && fps < cap * 0.72 && resScale > 0.26) {
          if (++slowWindows >= 2) { resScale = Math.max(0.25, resScale * 0.75); autoLowered = true; slowWindows = 0; resizeAll(); }
        } else slowWindows = 0;
      }
    }
    function start() { if (raf || !animating()) return; last = 0; frames = 0; winStart = 0; raf = requestAnimationFrame(tick); }
    function stop() { if (raf) cancelAnimationFrame(raf); raf = 0; }
    function settle() {                  // run the bubbles and schools for two simulated seconds before a still frame
      for (let i = 0; i < 60; i++) {
        current = sceneState(Date.now());
        parts.update(1 / 30, animT + i / 30, current);
        life.update(Date.now(), 1 / 30, animT + i / 30);
      }
    }
    // ── Hand-off: a page saves the scene as it's left, and the next page in this tab carries it on ──
    const HANDOFF = "amahi-ocean-scene";
    window.addEventListener("pagehide", () => {
      if (previewing) return;
      try {
        sessionStorage.setItem(HANDOFF, JSON.stringify({ v: 1, animT, parts: parts.snapshot(), life: life.snapshot(Date.now()) }));
      } catch (e) { /* storage unavailable or full: the next page starts afresh */ }
    });
    // Back and Forward can bring a page back as it was left, still running: it takes up the scene
    // from the page just left, instead of going back to its own.
    window.addEventListener("pageshow", e => {
      if (e.persisted && takeHandoff()) renderNow();
    });
    function takeHandoff() {
      let d = null;
      try {
        d = JSON.parse(sessionStorage.getItem(HANDOFF) || "null");
        sessionStorage.removeItem(HANDOFF);   // it only exists between one page and the next
      } catch (e) { return false; }
      if (!d || d.v !== 1 || !Number.isFinite(d.animT)) return false;
      try {
        parts.restore(d.parts);
        life.restore(d.life);
        animT = d.animT;
        return true;
      } catch (e) {
        return false;
      }
    }
    function refreshRun() {
      document.documentElement.classList.toggle("ocean-off", !S.on);
      $$("[data-ocean-panel]").forEach(b => b.classList.toggle("active", !!S.on));
      if (animating()) start(); else { stop(); renderNow(); }
    }
    ["pointermove", "pointerdown", "keydown", "wheel", "touchstart", "scroll"].forEach(ev =>
      window.addEventListener(ev, () => { lastInput = performance.now(); }, { passive: true }));
    window.addEventListener("scroll", () => parts.updateRects(), { passive: true });
    window.addEventListener("resize", () => { resizeAll(); if (!panel.hidden) placePanel(); });
    setInterval(() => { parts.updateRects(); if (!animating()) renderNow(); }, 30000);
    setInterval(() => { if (animating()) parts.updateRects(); }, 1000);
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", applyTheme);
    new MutationObserver(applyTheme).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });

    // ── Panel behaviour ──
    const fmtHour = h => { const m = Math.round(h * 60) % 1440; return String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"); };
    function phaseName(st) {
      if (!st.day && st.elev < -0.15) return "night";
      if (st.warm > 0.35) return st.hour < 12 ? "sunrise" : "sunset";
      if (st.hour < 11) return "morning";
      if (st.hour < 14) return "midday";
      if (st.hour < 18.5) return "afternoon";
      return "evening";
    }
    const weatherName = w => w < 0.8 ? "Clear" : w < 1.6 ? "Cloudy" : w < 2.35 ? "Rain" : "Storm";
    function syncControls() {
      $$(".ocean-seg", panel).forEach(seg => {
        const val = String(S[seg.dataset.set]);
        $$("button", seg).forEach(b => b.setAttribute("aria-pressed", String(val === b.dataset.val)));
      });
      P("[data-ocean-on]").checked = !!S.on;
    }
    function updatePanel() {
      if (panel.hidden) return;
      const st = sceneState(Date.now());
      const slider = P("[data-ocean-hour]");
      if (document.activeElement !== slider) slider.value = String(st.hour);
      P("[data-ocean-time]").textContent = `${fmtHour(st.hour)} · ${phaseName(st)}${S.cycle === 1 ? "" : ` · ${S.cycle}× speed`}`;
      P("[data-ocean-weather]").textContent =
        `${weatherName(st.w)}${S.weather === "auto" ? " (auto)" : ""} · tide ${st.tideRising ? "rising" : "falling"} ${Math.round((st.tide + 1) * 50)}% · ${st.turb > 0.15 ? "murky, settling" : "clear water"}`;
      P("[data-ocean-life]").textContent = life.describe();
      const [gw, gh] = glView.size();
      const [nb, nf] = parts.counts();
      const idle = performance.now() - lastInput > IDLE_MS;
      P("[data-ocean-stats]").textContent =
        (!running() ? "Background is off" :
          !glView.ok() ? "WebGL unavailable: showing the plain gradient" :
          `${gw}×${gh} water · ${animating() ? fps.toFixed(0) + " fps" : "still frame"} · ${jsMs.toFixed(1)} ms script per frame`) +
        `\n${nb} bubbles behind · ${nf} in front` +
        (idle ? "\nIdle: 12 fps until you move the mouse" : "") +
        (autoLowered ? "\nQuality lowered automatically after slow frames" : "") +
        (REDUCED ? "\nReduced motion is on: still frames only" : "");
    }
    setInterval(updatePanel, 500);

    let openTrigger = null;
    function placePanel() {
      const pw = panel.offsetWidth, ph = panel.offsetHeight, m = 12;
      let left = window.innerWidth - pw - 16, top = 70;
      if (openTrigger) {
        const r = openTrigger.getBoundingClientRect();
        left = r.left + r.width / 2 - pw / 2;
        top = r.bottom + 10;
        if (top + ph > window.innerHeight - m) top = r.top - ph - 10;   // a button near the bottom opens upward
      }
      panel.style.left = clamp(left, m, Math.max(m, window.innerWidth - pw - m)) + "px";
      panel.style.top = clamp(top, m, Math.max(m, window.innerHeight - ph - m)) + "px";
    }
    function openPanel(trigger) {
      openTrigger = trigger || null;
      panel.hidden = false;
      syncControls();
      updatePanel();
      placePanel();
      $$("[data-ocean-panel]").forEach(b => b.setAttribute("aria-expanded", String(b === openTrigger)));
      const first = P(".ocean-seg button[aria-pressed='true']") || P("button");
      if (first) first.focus({ preventScroll: true });
    }
    function closePanel() {
      if (panel.hidden) return;
      panel.hidden = true;
      $$("[data-ocean-panel]").forEach(b => b.setAttribute("aria-expanded", "false"));
      if (openTrigger) openTrigger.focus({ preventScroll: true });
      openTrigger = null;
    }
    document.addEventListener("click", e => {
      const t = e.target.closest("[data-ocean-panel]");
      if (!t) return;
      e.preventDefault();
      if (!panel.hidden && openTrigger === t) closePanel(); else openPanel(t);
    });
    document.addEventListener("pointerdown", e => {
      if (!panel.hidden && !panel.contains(e.target) && !e.target.closest("[data-ocean-panel]")) closePanel();
    });
    document.addEventListener("keydown", e => { if (e.key === "Escape") closePanel(); });

    $$(".ocean-seg", panel).forEach(seg => seg.addEventListener("click", e => {
      const b = e.target.closest("button");
      if (!b) return;
      const key = seg.dataset.set, val = b.dataset.val, now = Date.now();
      if (key === "weather") { S.wFrom = weatherW(now); S.wSetAt = now; S.weather = val; }
      else if (key === "cycle") { S.anchorScene = sceneMs(now); S.anchorReal = now; S.cycle = Number(val); }
      else if (key === "timeMode") { if (val === "manual") S.manualHour = hourAt(now); S.timeMode = val; }
      else if (key === "quality") { S.quality = val; resScale = quality().res; autoLowered = false; resizeAll(); }
      else if (key === "life") { S.life = val; }
      life.reset();
      save(); syncControls(); refreshRun(); updatePanel();
    }));
    P("[data-ocean-hour]").addEventListener("input", e => {
      S.timeMode = "manual"; S.manualHour = Number(e.target.value);
      life.reset();
      save(); syncControls(); renderNow();
    });
    P("[data-ocean-on]").addEventListener("change", e => { S.on = e.target.checked; save(); refreshRun(); updatePanel(); });
    P("[data-ocean-flash]").addEventListener("click", () => {
      manualFlashAt = Date.now();
      if (!animating()) { setTimeout(renderNow, 60); setTimeout(renderNow, 400); }
    });
    P("[data-ocean-reset]").addEventListener("click", () => {
      const now = Date.now();
      S.anchorReal = S.anchorScene = now; S.cycle = 1; S.timeMode = "live";
      life.reset();
      save(); syncControls(); renderNow();
    });
    $$("[data-summon]", panel).forEach(b => b.addEventListener("click", () => {
      life.summon(b.dataset.summon, false);
      if (!animating()) renderNow();
    }));

    // ── Public hooks ──
    window.AmahiOcean = {
      open: () => openPanel(null),
      close: closePanel,
      settings: () => JSON.parse(JSON.stringify(S)),
      summon: kind => { life.summon(kind, false); if (!animating()) renderNow(); },
      // Draws one still frame of a chosen moment without saving anything. Used for visual checks.
      preview(opts = {}) {
        previewing = true;
        still = true;
        stop();
        S.timeMode = "manual";
        S.manualHour = opts.hour == null ? 12 : Number(opts.hour);
        if (opts.weather) { S.weather = opts.weather; S.wSetAt = 0; }
        if (opts.life) S.life = opts.life;
        animT = opts.t == null ? 30 : Number(opts.t);
        life.reset();
        (opts.spawn || []).forEach(k => { const [kind, y] = String(k).split("@"); life.summon(kind, true, y ? Number(y) : null); });
        settle();
        renderNow();
      },
    };

    // ── Start ── (one frame drawn, with the scene the previous page handed over: drawing more
    // before the page first paints would only hold that paint up)
    applyTheme();
    resizeAll();
    if (!takeHandoff() && REDUCED) settle();
    booting = false;
    renderNow();
    refreshRun();
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run, { once: true });
  else run();
})();

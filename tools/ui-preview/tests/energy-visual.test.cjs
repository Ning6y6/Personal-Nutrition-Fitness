const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { MODES, normalizePreferences, waterFillState, waveGeometry, waterSVG } = require("../static/energy-visual.js");
const { validateConfig, nutritionStatus, readableColor, contrast } = require("../static/app.js");
const { translate } = require("../static/i18n.js");

test("water empty and confirmed zero have distinct neutral reasons", () => {
  assert.deepEqual(waterFillState(0, 2000, false), { level: 0, excess: 0, neutral: true, reason: "noRecords" });
  assert.deepEqual(waterFillState(0, 2000), { level: 0, excess: 0, neutral: true, reason: "zeroIntake" });
});
test("missing and nonpositive budgets cannot produce a water level", () => {
  for (const budget of [undefined, null]) assert.equal(waterFillState(500, budget).reason, "missingBudget");
  for (const budget of [0, -1, NaN, Infinity, "2000", true]) {
    const state = waterFillState(500, budget); assert.equal(state.neutral, true); assert.equal(state.level, 0); assert.equal(state.reason, "invalidBudget");
  }
});
test("partial, exact and excessive intake preserve actual excess without overflowing the vessel", () => {
  assert.deepEqual(waterFillState(500, 2000), { level: .25, excess: 0, neutral: false, reason: "partial" });
  assert.deepEqual(waterFillState(2000, 2000), { level: 1, excess: 0, neutral: false, reason: "exact" });
  assert.deepEqual(waterFillState(3085.9, 2200), { level: 1, excess: 885.9000000000001, neutral: false, reason: "over" });
  assert.equal(nutritionStatus(3085.9, 2200, "budget").label, "超出预算 885.9");
});
test("extreme finite inputs keep SVG geometry finite", () => {
  const state = waterFillState(Number.MAX_VALUE, Number.MIN_VALUE);
  assert.equal(state.level, 1); assert.equal(Number.isFinite(state.excess), true);
  for (const intake of [NaN, Infinity, -1, "100", true]) { assert.equal(waterFillState(intake, 2000).neutral, true); assert.equal(waterFillState(intake, 2000).level, 0); }
  for (const level of [0, Number.MIN_VALUE, .25, .99, 1]) { const geometry = waveGeometry(level); assert.ok(Number.isFinite(geometry.y)); assert.ok(!/NaN|Infinity/.test(waterSVG(level))); }
});
test("water rises with each intake step, clips to a circle and is flat at extremes", () => {
  const levels = [0, 500, 1000, 2000, 3000].map(intake => waterFillState(intake, 2000).level);
  assert.deepEqual(levels, [0, .25, .5, 1, 1]);
  assert.equal(waveGeometry(0).amplitude, 0); assert.equal(waveGeometry(1).amplitude, 0);
  assert.equal(waveGeometry(.5).y, 98);
  assert.match(waterSVG(.5), /clip-path="url\(#energy-water-clip\)"/);
  assert.match(waterSVG(0), /visibility="hidden"/);
  for (const level of [-1, 1.01, NaN, Infinity, "0.5"]) assert.throws(() => waveGeometry(level), RangeError);
});
test("mode is a separate browser preference and old preferences remain valid", () => {
  assert.deepEqual(MODES, ["ring", "water"]);
  const old = { language: "en", reduceMotion: true, reduceTransparency: false };
  assert.deepEqual(normalizePreferences(old), { ...old, energyVisualMode: "ring" });
  const selected = normalizePreferences({ ...old, energyVisualMode: "water", privateMeal: "not retained" });
  assert.deepEqual(normalizePreferences(JSON.parse(JSON.stringify(selected))), selected);
  assert.equal(Object.hasOwn(selected, "privateMeal"), false);
  for (const value of [null, [], "water", { energyVisualMode: "invalid" }]) assert.equal(normalizePreferences(value).energyVisualMode, "ring");
  const config = { version: 1, theme: "light", colors: { green: "#2ED158", yellow: "#FFD500", red: "#FF4144", lightBackground: "#F6F7F3", lightSurface: "#FFFFFF", darkBackground: "#111214", darkSurface: "#202124" }, warningPercent: 80, radius: 22, density: 1 };
  assert.equal(validateConfig(config), true);
  assert.equal(validateConfig({ ...config, energyVisualMode: "water" }), false);
});
test("water motion is bounded and both reduced-motion settings stop waves", () => {
  const css = fs.readFileSync(path.join(__dirname, "../static/style.css"), "utf8");
  assert.match(css, /\.water-wave-back[^}]*animation: water-drift 3\.6s ease-in-out 1/);
  assert.match(css, /\.water-wave-front[^}]*animation: water-drift 2\.4s ease-in-out 1/);
  assert.match(css, /\.phone\[data-motion=reduce\] \.water-wave[^}]*animation: none/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\) \{ \.water-wave[^}]*animation: none/);
  assert.match(css, /\.water-number-card \{ background: var\(--surface\)/);
});
test("opaque number plate uses readable text on light, dark and custom surfaces", () => {
  for (const surface of ["#FFFFFF", "#202124", "#2ED158", "#FF4144"]) for (const candidate of ["#18251F", "#F3F5F2"]) assert.ok(contrast(readableColor(candidate, surface), surface) >= 4.5);
  assert.equal(translate("水位圆圈", "en"), "Water fill");
  assert.match(translate("水位代表已记录热量，不代表整天已记全。", "en"), /not a confirmed complete day/);
});

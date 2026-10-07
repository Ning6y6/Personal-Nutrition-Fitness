const { test } = require("node:test");
const assert = require("node:assert/strict");
const { validateConfig, nutritionStatus, portionNutrition, readableColor, contrast, escapeHTML } = require("../static/app.js");
const defaultConfig = () => ({ version: 1, theme: "light", colors: { green: "#2ED158", yellow: "#FFD500", red: "#FF4144", lightBackground: "#F6F7F3", lightSurface: "#FFFFFF", darkBackground: "#111214", darkSurface: "#202124" }, warningPercent: 80, radius: 22, density: 1 });

test("valid local design and exact keys", () => {
  assert.equal(validateConfig(defaultConfig()), true);
  for (const patch of [{ unknown: 1 }, { version: 2 }, { theme: "auto" }, { radius: NaN }, { density: Infinity }, { density: .84 }, { warningPercent: 100 }, { warningPercent: 79.5 }]) assert.equal(validateConfig({ ...defaultConfig(), ...patch }), false);
  assert.equal(validateConfig({ ...defaultConfig(), colors: { ...defaultConfig().colors, green: "url(javascript:alert(1))" } }), false);
  assert.equal(validateConfig({ ...defaultConfig(), colors: { ...defaultConfig().colors, extra: "#FFFFFF" } }), false);
});
test("proposed budget transitions at 80% and exactly 100%", () => {
  assert.equal(nutritionStatus(1599, 2000, "budget").color, "green");
  assert.equal(nutritionStatus(1600, 2000, "budget").color, "yellow");
  assert.equal(nutritionStatus(1999, 2000, "budget").color, "yellow");
  const full = nutritionStatus(2000, 2000, "budget"); assert.equal(full.color, "red"); assert.equal(full.label, "已达预算，尚未超出");
  const over = nutritionStatus(2120, 2000, "budget"); assert.equal(over.label, "超出预算 120"); assert.equal(over.progress, 1);
});
test("yellow transition is adjustable without affecting maximum", () => {
  assert.equal(nutritionStatus(1840, 2000, "budget", 95).color, "green");
  assert.equal(nutritionStatus(12, 15, "maximum", 95).color, "yellow");
});
test("minimum target stays achieved above goal", () => {
  for (const [intake, goal] of [[140, 140], [160, 140], [32, 30], [0, 0]]) {
    const result = nutritionStatus(intake, goal, "minimum"); assert.equal(result.color, "green"); assert.equal(result.label, "最低目标已达到");
  }
  assert.equal(nutritionStatus(100, 140, "minimum").label, "距离最低目标还差 40");
  assert.equal(nutritionStatus(0, 0, "minimum").progress, 1);
});
test("maximum distinguishes approaching, equality, and exceedance", () => {
  assert.equal(nutritionStatus(11.9, 15, "maximum").color, "green");
  assert.equal(nutritionStatus(12, 15, "maximum").color, "yellow");
  assert.equal(nutritionStatus(15, 15, "maximum").label, "已达上限，尚未超出");
  assert.equal(nutritionStatus(16, 15, "maximum").label, "超出上限 1");
  assert.equal(nutritionStatus(1, 0, "maximum").color, "red");
});
test("missing meals and missing or invalid target are neutral", () => {
  for (const result of [nutritionStatus(0, 2000, "budget", 80, false), nutritionStatus(1420, null, "budget"), nutritionStatus(1420, 0, "budget"), nutritionStatus(NaN, 2000, "budget"), nutritionStatus(1, Infinity, "minimum"), nutritionStatus(-1, 2000, "budget")]) { assert.equal(result.color, "neutral"); assert.equal(result.progress, 0); }
});
test("real zero in a confirmed demo record differs from no record", () => {
  assert.equal(nutritionStatus(0, 2000, "budget", 80, true).label, "预算剩余 2,000");
  assert.equal(nutritionStatus(0, 2000, "budget", 80, false).label, "尚无可汇总记录");
});
test("per-100-g demo nutrition scales one time only", () => {
  const food = { energy: 160, protein: 10, carbohydrate: 16, fat: 6, saturatedFat: 2, fibre: 2 };
  assert.deepEqual(portionNutrition(food, 350), { energy: 560, protein: 35, carbohydrate: 56, fat: 21, saturatedFat: 7, fibre: 7 });
  for (const grams of [0, -1, Infinity, NaN, 5001, "350"]) assert.equal(portionNutrition(food, grams), null);
});
test("bright colors use readable companion text on both surfaces", () => {
  for (const surface of ["#FFFFFF", "#202124"]) for (const color of ["#2ED158", "#FFD500", "#FF4144"]) assert.ok(contrast(readableColor(color, surface), surface) >= 4.5);
});
test("user-entered meal names are escaped", () => {
  assert.equal(escapeHTML('<img src=x onerror="evil()">&'), "&lt;img src=x onerror=&quot;evil()&quot;&gt;&amp;");
});
test("positive tiny differences never report zero excess", () => {
  for (const kind of ["budget", "maximum"]) assert.match(nutritionStatus(20.01, 20, kind).label, /不足 0\.1/);
});

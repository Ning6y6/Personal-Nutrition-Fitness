const { test } = require("node:test");
const assert = require("node:assert/strict");
const { buildSevenDaySeries, recordingStreak, nearestPointIndex, nearestTrendIndex, renderTrend } = require("../static/trends.js");
const meal = () => ({ meals: [{ id: "fake-only" }], energy: 1600 });
const getData = fixtures => date => fixtures[date] || null;

test("seven-day calendar keys cross a month and a year without timezone conversion", () => {
  const series = buildSevenDaySeries("2026-01-03", () => null);
  assert.deepEqual(series.map(point => point.date), ["2025-12-28", "2025-12-29", "2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02", "2026-01-03"]);
  assert.equal(series.length, 7);
});
test("spring and autumn DST dates remain seven adjacent calendar days", () => {
  for (const anchor of ["2026-03-31", "2026-10-27"]) {
    const series = buildSevenDaySeries(anchor, () => null);
    for (let index = 1; index < 7; index += 1) assert.equal(Date.parse(series[index].date) - Date.parse(series[index - 1].date), 86400000);
  }
});
test("invalid dates fail without normalizing impossible dates", () => {
  for (const date of ["2026-02-30", "2026-13-01", "2026-1-03", "invalid", null]) {
    assert.throws(() => buildSevenDaySeries(date, () => null), RangeError);
    assert.throws(() => recordingStreak(date, () => null), RangeError);
  }
  assert.throws(() => buildSevenDaySeries("2026-10-07", null), TypeError);
  assert.throws(() => recordingStreak("2026-10-07", null), TypeError);
});
test("missing energy stays null while a real zero stays zero", () => {
  const fixtures = { "2026-10-01": meal(), "2026-10-03": { energy: 0, meals: [{}] }, "2026-10-04": { energy: NaN }, "2026-10-05": { energy: -1 }, "2026-10-06": { energy: Infinity }, "2026-10-07": { energy: "1600" } };
  const series = buildSevenDaySeries("2026-10-07", getData(fixtures));
  assert.deepEqual(series.map(point => point.energy), [1600, null, 0, null, null, null, null]);
  assert.equal(series[0].mealCount, 1);
  assert.equal(series[1].mealCount, 0);
});
test("streak is based on recording, not energy or confirmed completeness", () => {
  const fixtures = {
    "2026-10-07": { energy: 3000, meals: [{}], complete: false },
    "2026-10-06": { energy: 2600, meals: [{}] },
    "2026-10-05": { energy: 0, meals: [{}] },
    "2026-10-04": { energy: 1500, meals: [] }
  };
  assert.deepEqual(recordingStreak("2026-10-07", getData(fixtures)), { count: 3, activeThrough: "2026-10-07", includesToday: true });
});
test("today not yet recorded retains a streak through yesterday, with an explicit date", () => {
  const fixtures = { "2026-10-06": meal(), "2026-10-05": meal(), "2026-10-03": meal() };
  assert.deepEqual(recordingStreak("2026-10-07", getData(fixtures)), { count: 2, activeThrough: "2026-10-06", includesToday: false });
  assert.deepEqual(recordingStreak("2026-10-09", getData(fixtures)), { count: 0, activeThrough: null, includesToday: false });
});
test("streak traverses leap day and caps scanning at 366 days", () => {
  const fixtures = { "2024-03-01": meal(), "2024-02-29": meal(), "2024-02-28": meal() };
  assert.equal(recordingStreak("2024-03-01", getData(fixtures)).count, 3);
  assert.equal(recordingStreak("2026-10-07", meal).count, 366);
});
test("magnetic selection uses actual centers with stable midpoint ties", () => {
  assert.equal(nearestPointIndex([35, 105, 175], 108), 1);
  assert.equal(nearestPointIndex([35, 105, 175], 70), 0);
  assert.equal(nearestPointIndex([35, 105, 175], 900), 2);
  for (const [points, position] of [[[], 2], [[NaN, Infinity], 2], [[0], NaN]]) assert.equal(nearestPointIndex(points, position), -1);
  assert.equal(nearestTrendIndex(0, 70, 70), 0);
  assert.equal(nearestTrendIndex(70, 70, 70), 1);
  assert.equal(nearestTrendIndex(1000, 70, 70), 6);
  assert.equal(nearestTrendIndex(0, 0), -1);
});
test("SVG does not bridge missing days; isolated observations retain a dot", () => {
  const fixtures = { "2026-10-01": meal(), "2026-10-02": meal(), "2026-10-04": meal(), "2026-10-06": meal(), "2026-10-07": meal() };
  const html = renderTrend(buildSevenDaySeries("2026-10-07", getData(fixtures)), "2026-10-07");
  assert.equal((html.match(/class="trend-line"/g) || []).length, 2);
  assert.equal((html.match(/data-point=/g) || []).length, 5);
  assert.match(html, /2 天无记录/);
  assert.match(html, /不代表整天已记全/);
});
test("selected count is accessible, missing count is not rendered as zero", () => {
  const series = buildSevenDaySeries("2026-10-07", getData({ "2026-10-07": meal() }));
  const known = renderTrend(series, "2026-10-07");
  assert.match(known, /id="trend-value" data-value="1600">1,600/);
  assert.equal((known.match(/data-trend-date=/g) || []).length, 7);
  assert.equal((known.match(/aria-pressed="true"/g) || []).length, 1);
  const missing = renderTrend(series, "2026-10-01");
  assert.match(missing, /id="trend-value">—/);
  assert.doesNotMatch(missing, /id="trend-value" data-value/);
});
test("unknown selection falls back to latest day; English UI has equivalent no-record semantics", () => {
  const series = buildSevenDaySeries("2026-10-07", () => null);
  const html = renderTrend(series, "2025-01-01", "en");
  assert.match(html, /Last 7 days/);
  assert.match(html, /2026-10-07 · recorded energy/);
  assert.match(html, /7 days have no record; gaps are not zero/);
  assert.match(html, /does not confirm a complete day/);
  assert.equal((html.match(/class="trend-line"/g) || []).length, 0);
});
test("renderer validates its seven calendar points", () => {
  assert.throws(() => renderTrend([], "2026-10-07"), RangeError);
  const series = buildSevenDaySeries("2026-10-07", () => null);
  series[0].date = '<img src=x onerror="evil()">';
  assert.throws(() => renderTrend(series, "2026-10-07"), RangeError);
});

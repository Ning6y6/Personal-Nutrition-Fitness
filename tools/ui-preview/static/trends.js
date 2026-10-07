/* Pure helpers for the fictional, local-only design preview. Not daily intake analytics. */
(() => {
  "use strict";
  const DAY_MS = 86400000;
  const isEnergy = value => typeof value === "number" && Number.isFinite(value) && value >= 0;
  const escapeHTML = value => String(value).replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[character]));

  // These are calendar keys, not instants. UTC arithmetic avoids DST changing a day to 23/25 hours.
  function parseDateKey(key) {
    if (typeof key !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(key)) throw new RangeError("Expected an ISO calendar date.");
    const instant = new Date(`${key}T00:00:00Z`);
    if (!Number.isFinite(instant.getTime()) || instant.toISOString().slice(0, 10) !== key) throw new RangeError("Invalid calendar date.");
    return instant.getTime();
  }
  function shiftedDate(key, offset) {
    return new Date(parseDateKey(key) + offset * DAY_MS).toISOString().slice(0, 10);
  }
  function buildSevenDaySeries(anchorISO, getData) {
    parseDateKey(anchorISO);
    if (typeof getData !== "function") throw new TypeError("getData must be a function.");
    return Array.from({ length: 7 }, (_, index) => {
      const date = shiftedDate(anchorISO, index - 6), data = getData(date);
      return {
        date,
        energy: data && isEnergy(data.energy) ? data.energy : null,
        mealCount: data && Array.isArray(data.meals) ? data.meals.length : 0
      };
    });
  }
  function recordingStreak(anchorISO, getData) {
    parseDateKey(anchorISO);
    if (typeof getData !== "function") throw new TypeError("getData must be a function.");
    const hasMeals = date => {
      const data = getData(date);
      return Boolean(data && Array.isArray(data.meals) && data.meals.length > 0);
    };
    const includesToday = hasMeals(anchorISO);
    const candidate = includesToday ? anchorISO : shiftedDate(anchorISO, -1);
    if (!hasMeals(candidate)) return { count: 0, activeThrough: null, includesToday: false };
    let count = 0;
    while (count < 366 && hasMeals(shiftedDate(candidate, -count))) count += 1;
    return { count, activeThrough: candidate, includesToday };
  }

  // Use actual element centers: variable text widths and padding must not shift the chosen day.
  function nearestPointIndex(points, position) {
    if (!Array.isArray(points) || points.length === 0 || !Number.isFinite(position)) return -1;
    let best = -1, distance = Infinity;
    points.forEach((point, index) => {
      if (typeof point !== "number" || !Number.isFinite(point)) return;
      const candidate = Math.abs(point - position);
      if (candidate < distance) { best = index; distance = candidate; }
    });
    return best;
  }
  function nearestTrendIndex(scrollLeft, itemWidth, viewportWidth = itemWidth, count = 7) {
    if (![scrollLeft, itemWidth, viewportWidth].every(Number.isFinite) || itemWidth <= 0 || viewportWidth <= 0 || !Number.isInteger(count) || count <= 0) return -1;
    return Math.max(0, Math.min(count - 1, Math.round((scrollLeft + viewportWidth / 2 - itemWidth / 2) / itemWidth)));
  }

  function renderTrend(series, selectedDate, language = "zh") {
    if (!Array.isArray(series) || series.length !== 7) throw new RangeError("A seven-day series is required.");
    series.forEach(point => parseDateKey(point.date));
    const english = language === "en", locale = english ? "en-GB" : "zh-CN";
    const format = value => new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(value);
    const selectedIndex = Math.max(0, series.findIndex(point => point.date === selectedDate));
    const activeIndex = series.some(point => point.date === selectedDate) ? selectedIndex : series.length - 1;
    const selected = series[activeIndex], selectedEnergy = isEnergy(selected.energy) ? selected.energy : null;
    const validValues = series.map(point => point.energy).filter(isEnergy);
    const maximum = Math.max(1, ...validValues) * 1.12;
    const coords = series.map((point, index) => ({ x: 24 + index * 52, y: isEnergy(point.energy) ? 112 - point.energy / maximum * 88 : null }));
    const segments = []; let segment = [];
    coords.forEach(point => {
      if (point.y === null) { if (segment.length) segments.push(segment); segment = []; }
      else segment.push(point);
    });
    if (segment.length) segments.push(segment);
    const paths = segments.filter(points => points.length > 1).map(points => `<path class="trend-line" d="${points.map((point, index) => `${index ? "L" : "M"}${point.x.toFixed(2)} ${point.y.toFixed(2)}`).join(" ")}" fill="none" stroke="var(--green)" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>`).join("");
    const dots = coords.map((point, index) => point.y === null ? "" : `<circle data-point="${escapeHTML(series[index].date)}" cx="${point.x.toFixed(2)}" cy="${point.y.toFixed(2)}" r="${index === activeIndex ? 5 : 3.5}" fill="var(--green)"${index === activeIndex ? ' stroke="var(--surface)" stroke-width="2"' : ""}/>`).join("");
    const missingCount = series.filter(point => !isEnergy(point.energy)).length;
    const title = english ? "Last 7 days" : "最近 7 日";
    const selectedCaption = english ? `${selected.date} · recorded energy` : `${selected.date} · 已记录热量`;
    const missing = english ? `${missingCount} ${missingCount === 1 ? "day has" : "days have"} no record; gaps are not zero.` : `${missingCount} 天无记录；缺口不按 0 计算。`;
    const semantics = english ? "Fictional preview. Recorded energy does not confirm a complete day." : "虚构预览。已记录热量不代表整天已记全。";
    const points = series.map((point, index) => {
      const energy = isEnergy(point.energy) ? format(point.energy) + " kcal" : english ? "No record" : "无记录";
      const day = Number(point.date.slice(8)), month = Number(point.date.slice(5, 7));
      return `<button class="trend-point${index === activeIndex ? " selected" : ""}" type="button" data-trend-date="${escapeHTML(point.date)}" aria-pressed="${index === activeIndex}" aria-label="${escapeHTML(point.date + (english ? ", recorded energy: " : "，已记录热量：") + energy)}"><span>${month}/${day}</span><strong>${isEnergy(point.energy) ? format(point.energy) : "—"}</strong><small>${isEnergy(point.energy) ? "kcal" : english ? "No record" : "无记录"}</small></button>`;
    }).join("");
    return `<section class="trend-card card" aria-label="${title}"><div class="card-label"><span>${title}</span><span>${english ? "Recorded kcal" : "已记录 kcal"}</span></div><div class="trend-reading"><strong class="trend-value" id="trend-value"${selectedEnergy === null ? "" : ` data-value="${selectedEnergy}"`}>${selectedEnergy === null ? "—" : format(selectedEnergy)}</strong><span>${selectedEnergy === null ? english ? "No record" : "无记录" : "kcal"}</span></div><p class="trend-selected-caption">${selectedCaption}</p><svg class="trend-chart" viewBox="0 0 360 136" role="img" aria-label="${escapeHTML(title + (english ? ": gaps indicate missing records." : "：断点表示没有记录。"))}"><path d="M24 24H336M24 68H336M24 112H336" stroke="var(--divider)" stroke-width="1"/>${paths}${dots}</svg><div class="trend-points" aria-label="${english ? "Choose a date" : "选择日期"}">${points}</div><p class="trend-summary card-caption">${missing}<br>${semantics}</p></section>`;
  }

  const api = { buildSevenDaySeries, recordingStreak, nearestPointIndex, nearestTrendIndex, renderTrend };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.ShiHengTrends = api;
})();

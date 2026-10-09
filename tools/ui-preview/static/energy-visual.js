/* Optional browser-only energy visualization. Not hydration or nutrition policy. */
(() => {
  "use strict";
  const finite = value => typeof value === "number" && Number.isFinite(value);
  const MODES = Object.freeze(["ring", "water"]);

  function normalizePreferences(value) {
    const source = value && typeof value === "object" && !Array.isArray(value) ? value : {};
    return {
      language: source.language === "en" ? "en" : "zh",
      reduceMotion: source.reduceMotion === true,
      reduceTransparency: source.reduceTransparency === true,
      energyVisualMode: MODES.includes(source.energyVisualMode) ? source.energyVisualMode : "ring"
    };
  }

  function waterFillState(intake, budget, hasRecords = true) {
    if (!hasRecords) return { level: 0, excess: 0, neutral: true, reason: "noRecords" };
    if (!finite(intake) || intake < 0) return { level: 0, excess: 0, neutral: true, reason: "invalidIntake" };
    if (budget === null || budget === undefined) return { level: 0, excess: 0, neutral: true, reason: "missingBudget" };
    if (!finite(budget) || budget <= 0) return { level: 0, excess: 0, neutral: true, reason: "invalidBudget" };
    if (intake === 0) return { level: 0, excess: 0, neutral: true, reason: "zeroIntake" };
    // Compare first so a tiny budget cannot produce Infinity in the geometry.
    return { level: intake >= budget ? 1 : intake / budget, excess: Math.max(0, intake - budget), neutral: false, reason: intake > budget ? "over" : intake === budget ? "exact" : "partial" };
  }

  function waveGeometry(level) {
    if (!finite(level) || level < 0 || level > 1) throw new RangeError("Water level must be 0...1");
    const height = level * 168;
    const y = 182 - height;
    // Small waves stay inside the vessel at both extremes. Full/empty are flat.
    const amplitude = Math.min(3, height / 2, (168 - height) / 2);
    const path = `M-182 ${y} Q-140 ${y - amplitude} -98 ${y} T-14 ${y} T70 ${y} T154 ${y} T238 ${y} T322 ${y} T406 ${y} L406 500 L-182 500 Z`;
    return { y, height, amplitude, path };
  }

  function waterSVG(level) {
    const wave = waveGeometry(level);
    // One water card is rendered at a time. IDs are local to this preview SVG.
    return `<svg class="water-svg" viewBox="0 0 196 196" aria-hidden="true"><defs><clipPath id="energy-water-clip"><circle cx="98" cy="98" r="82"/></clipPath></defs><circle class="water-vessel-base" cx="98" cy="98" r="82"/><g clip-path="url(#energy-water-clip)"><g class="water-fill" ${level === 0 ? 'visibility="hidden"' : ""}><rect class="water-body" x="14" y="${wave.y}" width="168" height="${500 - wave.y}"/><path class="water-wave water-wave-back" d="${wave.path}"/><path class="water-wave water-wave-front" d="${wave.path}"/></g></g><circle class="water-vessel-outline" cx="98" cy="98" r="82"/></svg>`;
  }

  const api = Object.freeze({ MODES, normalizePreferences, waterFillState, waveGeometry, waterSVG });
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.ShiHengEnergyVisual = api;
})();

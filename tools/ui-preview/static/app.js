/* Design-only simulation. No SwiftData, health store, camera, or AI connection. */
(() => {
  "use strict";
  const STORAGE_KEY = "shiheng-design-preview-v1";
  const DEMO_DATE = "2026-10-07";
  const DEFAULT_GOALS = { energy: 2000, protein: 140, carbohydrate: 210, fat: 60, saturatedFat: 15, fibre: 30 };
  const COLOR_NAMES = {
    green: "进度绿色", yellow: "接近黄色", red: "达到红色",
    lightBackground: "浅色背景", lightSurface: "浅色卡片", darkBackground: "深色背景", darkSurface: "深色卡片"
  };
  const FIXTURES = {
    normal: { energy: 1420, protein: 100, carbohydrate: 165, fat: 40, saturatedFat: 8, fibre: 18 },
    near: { energy: 1840, protein: 140, carbohydrate: 200, fat: 53, saturatedFat: 13, fibre: 28 },
    full: { energy: 2000, protein: 148, carbohydrate: 210, fat: 60, saturatedFat: 15, fibre: 30 },
    over: { energy: 2120, protein: 160, carbohydrate: 230, fat: 66, saturatedFat: 16, fibre: 32 }
  };
  // Fictional values for interaction testing, not food-table data or dietary advice.
  const DEMO_FOODS = [
    { id: "beef-rice", name: "牛肉青椒饭（演示）", energy: 160, protein: 10, carbohydrate: 16, fat: 6, saturatedFat: 2, fibre: 2 },
    { id: "tomato-egg", name: "番茄炒蛋（演示）", energy: 120, protein: 7, carbohydrate: 5, fat: 8, saturatedFat: 2, fibre: 1 },
    { id: "chicken", name: "鸡肉饭（演示）", energy: 150, protein: 12, carbohydrate: 15, fat: 5, saturatedFat: 1, fibre: 1 },
    { id: "oats", name: "燕麦片（演示）", energy: 380, protein: 13, carbohydrate: 62, fat: 7, saturatedFat: 1, fibre: 8 }
  ];
  const clone = value => JSON.parse(JSON.stringify(value));
  const finite = value => typeof value === "number" && Number.isFinite(value);
  const format = value => new Intl.NumberFormat("zh-CN", { maximumFractionDigits: 1 }).format(value);
  const formatDifference = value => value > 0 && value < .1 ? "不足 0.1" : format(value);
  const escapeHTML = value => String(value).replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
  function validateConfig(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return false;
    const fields = ["version", "theme", "colors", "warningPercent", "radius", "density"];
    if (Object.keys(value).length !== fields.length || !fields.every(key => Object.hasOwn(value, key))) return false;
    if (value.version !== 1 || !["light", "dark"].includes(value.theme)) return false;
    if (!value.colors || typeof value.colors !== "object" || Array.isArray(value.colors)) return false;
    if (Object.keys(value.colors).length !== Object.keys(COLOR_NAMES).length) return false;
    if (!Object.keys(COLOR_NAMES).every(key => /^#[0-9a-f]{6}$/i.test(value.colors[key]))) return false;
    return Number.isInteger(value.warningPercent) && value.warningPercent >= 50 && value.warningPercent <= 99
      && Number.isInteger(value.radius) && value.radius >= 12 && value.radius <= 32
      && finite(value.density) && value.density >= .85 && value.density <= 1.15;
  }
  function nutritionStatus(intake, target, kind, warningPercent = 80, hasRecords = true) {
    if (!hasRecords || !finite(intake) || intake < 0) return { color: "neutral", progress: 0, label: "尚无可汇总记录", icon: "empty" };
    if (target === null || target === undefined) return { color: "neutral", progress: 0, label: "尚未设置目标", icon: "empty" };
    if (!finite(target) || target < 0 || (kind === "budget" && target === 0)) return { color: "neutral", progress: 0, label: "目标无法计算", icon: "empty" };
    const ratio = target === 0 ? 1 : intake / target;
    const progress = Math.min(1, ratio);
    if (kind === "minimum") return { color: intake >= target ? "green" : "neutral", progress, label: intake >= target ? "最低目标已达到" : `距离最低目标还差 ${formatDifference(target - intake)}`, icon: intake >= target ? "check" : "empty" };
    if (kind === "maximum") {
      if (intake > target) return { color: "red", progress, label: `超出上限 ${formatDifference(intake - target)}`, icon: "alert" };
      if (intake === target) return { color: "yellow", progress, label: "已达上限，尚未超出", icon: "alert" };
      if (ratio >= .8) return { color: "yellow", progress, label: `接近上限，还余 ${formatDifference(target - intake)}`, icon: "alert" };
      return { color: "green", progress, label: `距上限剩余 ${formatDifference(target - intake)}`, icon: "check" };
    }
    // Proposed visual policy ONLY. Production FoodDecisionCore v1 is unchanged.
    if (intake > target) return { color: "red", progress, label: `超出预算 ${formatDifference(intake - target)}`, icon: "alert" };
    if (intake === target) return { color: "red", progress, label: "已达预算，尚未超出", icon: "check" };
    if (ratio >= warningPercent / 100) return { color: "yellow", progress, label: `接近预算，还余 ${formatDifference(target - intake)}`, icon: "alert" };
    return { color: "green", progress, label: `预算剩余 ${formatDifference(target - intake)}`, icon: "check" };
  }
  function portionNutrition(food, grams) {
    if (!food || !finite(grams) || grams <= 0 || grams > 5000) return null;
    const values = {};
    for (const key of Object.keys(DEFAULT_GOALS)) values[key] = food[key] * grams / 100;
    return values;
  }
  function luminance(hex) {
    const rgb = hex.slice(1).match(/.{2}/g).map(channel => parseInt(channel, 16) / 255)
      .map(channel => channel <= .04045 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4);
    return .2126 * rgb[0] + .7152 * rgb[1] + .0722 * rgb[2];
  }
  function contrast(a, b) { const values = [luminance(a), luminance(b)].sort((x, y) => y - x); return (values[0] + .05) / (values[1] + .05); }
  function mixColor(a, b, amount) {
    const channels = hex => hex.slice(1).match(/.{2}/g).map(channel => parseInt(channel, 16));
    const start = channels(a), end = channels(b);
    return "#" + start.map((channel, index) => Math.round(channel + (end[index] - channel) * amount).toString(16).padStart(2, "0")).join("");
  }
  function readableColor(color, surface) {
    if (contrast(color, surface) >= 4.5) return color;
    const destination = luminance(surface) > .18 ? 0 : 255;
    const channels = color.slice(1).match(/.{2}/g).map(channel => parseInt(channel, 16));
    for (let step = 1; step <= 20; step += 1) {
      const mixed = "#" + channels.map(channel => Math.round(channel + (destination - channel) * step / 20).toString(16).padStart(2, "0")).join("");
      if (contrast(mixed, surface) >= 4.5) return mixed;
    }
    return destination === 0 ? "#000000" : "#FFFFFF";
  }
  if (typeof module !== "undefined" && module.exports) module.exports = { validateConfig, nutritionStatus, portionNutrition, readableColor, contrast, escapeHTML };
  if (typeof document === "undefined") return;

  const $ = selector => document.querySelector(selector);
  const motion = window.ShiHengMotion;
  const trends = window.ShiHengTrends;
  const energyVisual = window.ShiHengEnergyVisual;
  const localize = () => { window.ShiHengI18n?.translateDOM(document.body, state.language); document.title = state.language === "en" ? "ShiHeng · Design studio" : "食衡 · UI 调色工作台"; };
  const systemReduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  const reduceMotion = () => state.reduceMotion || systemReduced.matches;
  const iconPaths = {
    today: '<circle cx="12" cy="12" r="8"/><path d="M12 4a8 8 0 0 1 8 8" stroke-width="3"/>',
    scan: '<path d="M8 3H4a1 1 0 0 0-1 1v4m13-5h4a1 1 0 0 1 1 1v4M3 16v4a1 1 0 0 0 1 1h4m8 0h4a1 1 0 0 0 1-1v-4M7 12h10"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 10h18m-14 4h2m3 0h2m3 0h1m-11 4h2m3 0h2"/>',
    settings: '<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3" fill="currentColor" stroke="none"/><circle cx="15" cy="17" r="3" fill="currentColor" stroke="none"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    food: '<path d="M5 3v6m3-6v6M3 3v5a3 3 0 0 0 6 0M6 11v10m12-18c-4 2-4 7-4 9h4m0-9v18"/>',
    check: '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
    alert: '<path d="m12 3 10 17H2L12 3Z"/><path d="M12 8v5m0 3h.01"/>',
    empty: '<circle cx="12" cy="12" r="9" stroke-dasharray="2 3"/>',
    history: '<path d="M3 11a9 9 0 1 1 2 7M3 4v7h7M12 7v5l3 2"/>',
    camera: '<rect x="3" y="6" width="18" height="15" rx="3"/><path d="m8 6 2-3h4l2 3"/><circle cx="12" cy="13" r="4"/>',
    edit: '<path d="m15 3 6 6-11 11-7 1 1-7L15 3Z"/>',
    chevron: '<path d="m9 5 7 7-7 7"/>',
    moon: '<path d="M20 15a9 9 0 0 1-11-11 9 9 0 1 0 11 11Z"/>'
  };
  const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name] || iconPaths.empty}</svg>`;
  let config, initialConfig, currentSheet = null, toastTimer, pageAnimation;
  let morphAnimation = null, morphOrigin = null, morphDestination = null;
  let trendScrollTimer, previousTrendValue = null, waterAnimation = null;
  const state = {
    page: "today", preset: "normal", goals: clone(DEFAULT_GOALS), totals: clone(FIXTURES.normal), hasRecords: true,
    hasGoal: true, meals: [], scanResult: false, calendarMonth: new Date(2026, 9, 1), selectedDate: DEMO_DATE,
    trendDate: DEMO_DATE, language: "zh", reduceMotion: false, reduceTransparency: false, energyVisualMode: "ring", pageScroll: {}
  };
  function message(text, error = false) { $("#workbench-message").textContent = text; $("#workbench-message").classList.toggle("error", error); localize(); }
  function toast(text) { clearTimeout(toastTimer); $("#phone-toast").textContent = text; $("#phone-toast").hidden = false; localize(); toastTimer = setTimeout(() => { $("#phone-toast").hidden = true; }, 2700); }
  function saveDesign() { try { localStorage.setItem(STORAGE_KEY, JSON.stringify(config)); } catch { $("#storage-note").textContent = "此浏览器不允许本地保存；请导出 JSON 保留方案。"; } }
  function statusTextColor(status) {
    return status.color === "neutral" ? "var(--secondary)" : readableColor(config.colors[status.color], config.colors[config.theme === "light" ? "lightSurface" : "darkSurface"]);
  }
  function applyAppearance() {
    const phone = $("#phone"); phone.dataset.theme = config.theme;
    const page = config.colors[config.theme === "light" ? "lightBackground" : "darkBackground"];
    const surface = config.colors[config.theme === "light" ? "lightSurface" : "darkSurface"];
    for (const name of ["green", "yellow", "red"]) {
      phone.style.setProperty(`--${name}`, config.colors[name]); $("#legend-" + name).style.background = config.colors[name];
    }
    phone.style.setProperty("--page", page); phone.style.setProperty("--surface", surface);
    phone.style.setProperty("--radius", config.radius + "px"); phone.style.setProperty("--density", config.density);
    const pageInk = readableColor(luminance(page) > .18 ? "#18251F" : "#F3F5F2", page);
    const surfaceInk = readableColor(luminance(surface) > .18 ? "#18251F" : "#F3F5F2", surface);
    phone.style.setProperty("--ink", pageInk);
    phone.style.setProperty("--secondary", readableColor(luminance(page) > .18 ? "#647168" : "#A4AFA7", page));
    phone.style.setProperty("--surface-ink", surfaceInk);
    phone.style.setProperty("--surface-secondary", readableColor(luminance(surface) > .18 ? "#647168" : "#A4AFA7", surface));
    phone.style.setProperty("--track", mixColor(surface, surfaceInk, .11));
    phone.style.setProperty("--divider", mixColor(surface, surfaceInk, .10));
    phone.style.setProperty("--glass", mixColor(surface, surfaceInk, .025));
    phone.style.setProperty("--action-ink", readableColor("#102c19", config.colors.green));
    phone.dataset.motion = reduceMotion() ? "reduce" : "full";
    if (reduceMotion()) { waterAnimation?.cancel(); waterAnimation = null; }
    phone.dataset.transparency = state.reduceTransparency ? "reduce" : "full";
    $("#light-mode").setAttribute("aria-pressed", String(config.theme === "light")); $("#dark-mode").setAttribute("aria-pressed", String(config.theme === "dark"));
    for (const button of document.querySelectorAll("[data-energy-mode]")) button.setAttribute("aria-pressed", String(button.dataset.energyMode === state.energyVisualMode));
    for (const button of document.querySelectorAll(".primary-button")) button.style.color = readableColor("#102c19", config.colors.green);
  }
  function syncControls() {
    $("#color-controls").innerHTML = Object.entries(COLOR_NAMES).map(([key, label]) => `<div class="color-row"><label for="color-${key}">${label}</label><div><input class="color-hex" id="hex-${key}" type="text" maxlength="7" value="${config.colors[key]}" aria-label="${label}十六进制值" data-color="${key}" spellcheck="false"><input id="color-${key}" type="color" value="${config.colors[key]}" aria-label="${label}" data-color="${key}"></div></div>`).join("");
    $("#radius").value = config.radius; $("#radius-value").textContent = config.radius + " px";
    $("#density").value = Math.round(config.density * 100); $("#density-value").textContent = Math.round(config.density * 100) + "%";
    $("#warning").value = config.warningPercent; $("#warning-value").textContent = config.warningPercent + "%";
    syncIntakeControls(); applyAppearance();
  }
  function syncIntakeControls() {
    $("#intake").value = Math.round(state.totals.energy); $("#goal").value = state.hasGoal ? state.goals.energy : "";
    $("#intake-slider").max = Math.max(3000, state.goals.energy * 1.5, state.totals.energy);
    $("#intake-slider").value = state.totals.energy;
    $("#intake-value").textContent = state.hasRecords && state.hasGoal ? Math.round(state.totals.energy / state.goals.energy * 100) + "%" : "—";
    for (const button of document.querySelectorAll("[data-preset]")) button.classList.toggle("active", button.dataset.preset === state.preset);
  }
  function fixtureMeals(total) {
    const first = Math.round(total * .25), second = Math.round(total * .5);
    return [
      { id: "demo-1", name: "燕麦与酸奶", time: "08:10", energy: first, evidence: "演示" },
      { id: "demo-2", name: "牛肉青椒饭", time: "12:30", energy: second, evidence: "演示" },
      { id: "demo-3", name: "番茄鸡蛋与水果", time: "16:00", energy: total - first - second, evidence: "演示" }
    ];
  }
  function setPreset(name) {
    state.preset = name; state.hasRecords = name !== "empty"; state.hasGoal = name !== "noGoal";
    state.goals = clone(DEFAULT_GOALS); state.totals = clone(FIXTURES[name] || FIXTURES.normal);
    if (!state.hasRecords) for (const key of Object.keys(state.totals)) state.totals[key] = 0;
    state.meals = state.hasRecords ? fixtureMeals(state.totals.energy) : [];
    syncIntakeControls(); renderPhone();
  }
  function heading(title, subtitle, action = "") { return `<div class="page-heading"><div><h2>${title}</h2><p>${subtitle}</p></div>${action}</div>`; }
  function energyCard() {
    if (state.energyVisualMode === "water") return waterEnergyCard();
    if (!state.hasRecords) return `<section class="card empty-energy"><strong>今天尚未记录</strong><p>记下第一餐后，再查看已记录摄入与预算余量。</p></section>`;
    const status = nutritionStatus(state.totals.energy, state.hasGoal ? state.goals.energy : null, "budget", config.warningPercent);
    const circumference = 2 * Math.PI * 82;
    const color = status.color === "neutral" ? "var(--secondary)" : config.colors[status.color];
    return `<section class="card energy-card"><div class="card-label"><span>已记录热量</span><span>${state.meals.length} 餐 · 演示</span></div>
      <div class="energy-ring" role="img" aria-label="已记录 ${format(state.totals.energy)} 千卡，${status.label}${/\d$/.test(status.label) ? "千卡" : ""}">
        <svg viewBox="0 0 196 196"><circle class="ring-track" cx="98" cy="98" r="82"/><circle class="ring-progress" cx="98" cy="98" r="82" stroke="${color}" stroke-dasharray="${circumference}" stroke-dashoffset="${circumference * (1 - status.progress)}" ${status.progress === 0 ? 'visibility="hidden"' : ""}/></svg>
        <div class="ring-number"><strong>${format(state.totals.energy)}</strong><span>kcal</span></div>
      </div>
      <div class="energy-status" style="color:${statusTextColor(status)}">${icon(status.icon)}<span>${status.label}${/\d$/.test(status.label) ? " kcal" : ""}</span></div>
      <div class="budget-row"><span>今日预算</span><span>${state.hasGoal ? format(state.goals.energy) + " kcal" : "尚未设置"}</span></div>
    </section>`;
  }
  function waterEnergyCard() {
    const budget = state.hasGoal ? state.goals.energy : null;
    const fill = energyVisual.waterFillState(state.totals.energy, budget, state.hasRecords);
    const status = nutritionStatus(state.totals.energy, budget, "budget", config.warningPercent, state.hasRecords);
    const color = fill.neutral ? "var(--track)" : config.colors[status.color];
    const reading = state.hasRecords ? format(state.totals.energy) : "—";
    const caption = state.hasRecords ? `${state.meals.length} 餐 · 演示` : "尚无可汇总记录";
    const statusColor = fill.neutral ? "var(--secondary)" : statusTextColor(status);
    return `<section class="card energy-card water-energy-card"><div class="card-label"><span>已记录热量</span><span>${caption}</span></div>
      <div class="energy-ring energy-water" data-water-level="${fill.level}" data-water-reason="${fill.reason}" style="--water-color:${color}" role="img" aria-label="${state.hasRecords ? '已记录 ' + reading + ' 千卡' : '今天尚未记录'}，${status.label}${/\d$/.test(status.label) ? '千卡' : ''}">
        ${energyVisual.waterSVG(fill.level)}
        <div class="ring-number"><div class="water-number-card"><strong>${reading}</strong><span>kcal</span></div></div>
      </div>
      <div class="energy-status" style="color:${statusColor}">${icon(status.icon)}<span>${status.label}${/\d$/.test(status.label) ? ' kcal' : ''}</span></div>
      <div class="budget-row"><span>今日预算</span><span>${state.hasGoal ? format(state.goals.energy) + ' kcal' : '尚未设置'}</span></div>
      <p class="card-caption water-caption">水位代表已记录热量，不代表整天已记全。</p>
    </section>`;
  }
  function nutrientRow(key, label, kind) {
    const target = state.hasGoal ? state.goals[key] : null;
    const status = nutritionStatus(state.totals[key], target, kind, config.warningPercent, state.hasRecords);
    const color = status.color === "neutral" ? "var(--secondary)" : config.colors[status.color];
    const unit = /\d$/.test(status.label) ? " g" : "";
    return `<div class="nutrient"><div class="nutrient-label"><span>${label}</span><span>${state.hasRecords ? format(state.totals[key]) : "—"}${target !== null ? " / " + format(target) : ""} g</span></div>
      <div class="track" role="img" aria-label="${label}：${status.label}${unit}"><span style="width:${status.progress * 100}%;background:${color}"></span></div>
      <div class="nutrient-note" style="color:${statusTextColor(status)}">${icon(status.icon)}<span>${status.label}${unit}</span></div></div>`;
  }
  function mealRows(meals) {
    return meals.map(meal => `<article class="meal-accordion"><button class="meal-row" type="button" data-meal="${meal.id}" aria-expanded="false" aria-controls="details-${meal.id}"><span class="meal-icon">${icon("food")}</span><span class="meal-copy"><strong data-user-content>${escapeHTML(mealDisplayName(meal))}</strong><span>${meal.time} · ${escapeHTML(meal.evidence)}</span></span><span class="meal-value">${format(meal.energy)}<small>kcal</small></span><span class="meal-chevron">${icon("chevron")}</span></button><div id="details-${meal.id}" class="meal-expansion" hidden></div></article>`).join("");
  }
  function mealDisplayName(meal) { return meal.id.startsWith("demo-") ? window.ShiHengI18n.translate(meal.name, state.language) : meal.name; }
  function todayPage() {
    return heading("今日", "10 月 7 日，星期三 · 演示日期")
      + energyCard()
      + `<section class="card">${nutrientRow("protein", "蛋白质", "minimum")}${nutrientRow("carbohydrate", "碳水", "budget")}${nutrientRow("fat", "脂肪", "budget")}</section>`
      + `<section class="card">${nutrientRow("saturatedFat", "饱和脂肪", "maximum")}${nutrientRow("fibre", "纤维", "minimum")}</section>`
      + `<h3 class="section-title">今日餐食<span>${state.meals.length} 餐</span></h3><section class="card">${state.meals.length ? mealRows(state.meals) : '<p class="screen-note">还没有餐食记录。</p>'}</section>`
      + `<p class="screen-note">只表示已记录的摄入，不代表今天所有餐食都已记全。</p>`;
  }
  function scanPage() {
    return heading("扫描", "包装上的信息，变成自己的食物")
      + `<div class="scan-window">${icon("scan")}<p>包装标签预览区域</p></div><button class="primary-button" type="button" data-action="scan">${icon("camera")}${state.scanResult ? "重新模拟扫描" : "模拟扫描标签"}</button><p class="screen-note">不调用相机或模型；下方展示固定示例。</p>`
      + (state.scanResult ? `<section class="card"><span class="mock-badge">示例结果 · 未核对</span><h3>原味燕麦片</h3><div class="result-status" style="color:${readableColor(config.colors.yellow, config.colors[config.theme === "light" ? "lightSurface" : "darkSurface"])}">${icon("alert")}需要人工核对</div><p class="card-caption">没有真实配料、认证或药物信息，不提供购买与安全结论。</p><div class="key-value"><span>计量基准</span><span>每 100 g</span></div><div class="key-value"><span>热量</span><span>380 kcal</span></div><div class="key-value"><span>蛋白质 / 碳水 / 脂肪</span><span>13 / 62 / 7 g</span></div><button class="secondary-phone-button" type="button" data-action="scan-record">按克数模拟记录</button></section>` : `<section class="card"><h3>把营养表变成常用食物</h3><p class="card-caption">正式扫描与自定义食品仍待开发。这里先确认页面布局与记录流程。</p></section>`);
  }
  function calendarData(date) {
    if (date === DEMO_DATE) return state.hasRecords ? { energy: state.totals.energy, meals: state.meals, complete: false } : null;
    const fixtures = { "2026-10-01": [1780, true], "2026-10-02": [1920, false], "2026-10-03": [2140, true], "2026-10-05": [1660, true], "2026-10-06": [1870, false] };
    if (!fixtures[date]) return null;
    const [energy, complete] = fixtures[date]; return { energy, complete, meals: fixtureMeals(energy) };
  }
  function dateKey(date) { return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`; }
  function calendarPage() {
    const start = new Date(state.calendarMonth.getFullYear(), state.calendarMonth.getMonth(), 1);
    const offset = (start.getDay() + 6) % 7; const cells = [];
    for (let index = 0; index < 42; index += 1) {
      const date = new Date(start.getFullYear(), start.getMonth(), 1 - offset + index), key = dateKey(date), data = calendarData(key);
      const outside = date.getMonth() !== start.getMonth();
      cells.push(`<button type="button" class="calendar-day ${outside ? "outside" : ""} ${key === state.selectedDate ? "selected" : ""}" data-date="${key}" aria-label="${key}，${data ? format(data.energy) + ' 千卡，' + (data.complete ? '示例完整日' : '未确认完整') : '没有记录'}" aria-pressed="${key === state.selectedDate}"><span>${date.getDate()}</span><small>${data ? format(Math.round(data.energy)) : "—"}</small></button>`);
    }
    const data = calendarData(state.selectedDate);
    const series = trends.buildSevenDaySeries(DEMO_DATE, calendarData);
    const streak = trends.recordingStreak(DEMO_DATE, calendarData);
    return heading("趋势", "看见每一天，而不是只看平均值")
      + trends.renderTrend(series, state.trendDate, state.language)
      + `<section class="card streak-card"><span class="streak-icon">${icon("history")}</span><div><strong>连续记录 <span>${streak.count}</span> 天</strong><p class="card-caption">不奖励少吃，只鼓励坚持记录。</p><p class="card-caption">${streak.includesToday ? "包括今天" : "截至昨天；今天还可以接上"} · 演示</p></div></section>`
      + `<section class="card"><div class="month-navigation"><button type="button" data-action="previous-month" aria-label="上个月">‹</button><strong>${start.getFullYear()} 年 ${start.getMonth() + 1} 月</strong><button type="button" data-action="next-month" aria-label="下个月">›</button></div><div class="calendar-grid">${["一", "二", "三", "四", "五", "六", "日"].map(day => `<span class="weekday">${day}</span>`).join("")}${cells.join("")}</div><div class="calendar-key"><span>数字：已记录 kcal</span><span>—：没有记录，不是 0</span></div></section><h3 class="section-title">${state.selectedDate.slice(5).replace("-", " 月 ")} 日<span>${data ? format(Math.round(data.energy)) + " kcal" : "无记录"}</span></h3><section class="card">${data ? `<p class="card-caption">${data.complete ? "示例完整日" : "尚未确认整天记全"} · 虚构数据</p>${mealRows(data.meals)}` : '<p class="screen-note">这一天没有记录，不纳入真实平均计算。</p>'}</section><p class="screen-note">日历、日级确认与历史目标查询在正式 App 中尚未交付；这里只是设计演示。</p>`;
  }
  function settingsPage() {
    return heading("设置", "你的目标，你的节奏") + `<section class="card"><button class="setting-row" type="button" data-action="goals"><span>每日营养目标</span><span>${state.hasGoal ? format(state.goals.energy) + " kcal" : "未设置"} ›</span></button><button class="setting-row" type="button" data-action="toggle-theme"><span>外观</span><span>${config.theme === "light" ? "浅色" : "深色"} ›</span></button><button class="setting-row" type="button" data-action="entry"><span>常用餐预览</span><span>复用示例 ›</span></button></section>
      <section class="card"><label class="setting-row language-picker" for="language"><span>语言</span><select id="language" aria-label="语言"><option value="zh" ${state.language === "zh" ? "selected" : ""}>中文</option><option value="en" ${state.language === "en" ? "selected" : ""}>English</option></select></label><label class="setting-row motion-preference"><span>减少动态效果</span><input type="checkbox" id="reduce-motion" ${reduceMotion() ? "checked" : ""}></label><label class="setting-row motion-preference"><span>减少透明度</span><input type="checkbox" id="reduce-transparency" ${state.reduceTransparency ? "checked" : ""}></label><p class="card-caption">跟随系统减少动态效果；也可以在这里开启。</p></section>
      <section class="card"><h3>本地设计沙盒</h3><p class="card-caption">食物与数值只用于交互测试。没有登录、云同步、照片上传或真实扫描。</p><div class="key-value"><span>设计版本</span><span>Calm Precision · 02</span></div><div class="key-value"><span>热量变黄起点</span><span>${config.warningPercent}% · 拟议</span></div><div class="key-value"><span>达到热量预算</span><span>红色 · 尚未超出</span></div></section><p class="screen-note">配色可在外侧面板导出，未来用于 SwiftUI 改版。原型不会自动改写正式项目的规则或数据。</p>`;
  }
  function renderPhone(resetScroll = false, transitioning = false) {
    const scroller = $("#phone-content"), previous = scroller.scrollTop;
    const previousWaterLevel = $(".energy-water")?.dataset.waterLevel;
    clearTimeout(trendScrollTimer);
    scroller.innerHTML = ({ today: todayPage, scan: scanPage, calendar: calendarPage, settings: settingsPage })[state.page]();
    scroller.scrollTop = resetScroll ? state.pageScroll[state.page] || 0 : previous;
    $("#phone-toolbar").innerHTML = `<span class="toolbar-title">ShiHeng <small>演示</small></span><button type="button" class="toolbar-budget" data-action="budget" aria-label="调整每日热量预算"><span>今日预算</span><strong>${state.hasGoal ? format(state.goals.energy) + ' kcal' : '尚未设置'} ${icon("edit")}</strong></button>`;
    for (const button of document.querySelectorAll("[data-page]")) {
      if (button.dataset.page === state.page) button.setAttribute("aria-current", "page"); else button.removeAttribute("aria-current");
    }
    $(".tab-bar").style.setProperty("--tab-index", ["today", "scan", "calendar", "settings"].indexOf(state.page));
    applyAppearance();
    const water = $(".energy-water"), waterFill = water?.querySelector(".water-fill");
    waterAnimation?.cancel(); waterAnimation = null;
    if (waterFill && previousWaterLevel !== undefined && !reduceMotion() && waterFill.animate) {
      const displacement = (Number(water.dataset.waterLevel) - Number(previousWaterLevel)) * 168;
      if (displacement !== 0) waterAnimation = waterFill.animate([{ transform: `translateY(${displacement}px)` }, { transform: "translateY(0px)" }], { duration: motion.TOKENS.duration, easing: motion.TOKENS.easing });
    }
    localize();
    pageAnimation?.cancel();
    if (transitioning && scroller.animate) pageAnimation = scroller.animate(reduceMotion() ? [{ opacity: .4 }, { opacity: 1 }] : [{ opacity: .25, transform: "translateY(6px)" }, { opacity: 1, transform: "translateY(0)" }], { duration: reduceMotion() ? motion.TOKENS.fade : motion.TOKENS.duration, easing: motion.TOKENS.easing });
    bindTrend();
  }
  function backgroundInert(inert) {
    for (const element of [$("#phone-content"), $("#phone-toolbar"), $(".tab-bar")]) element.inert = inert;
    $(".morph-trigger").inert = inert;
  }
  function relativeRect(element) {
    const bounds = element.getBoundingClientRect(), parent = $("#phone-screen").getBoundingClientRect();
    return { left: bounds.left - parent.left, top: bounds.top - parent.top, width: bounds.width, height: bounds.height };
  }
  async function settleMorph() {
    const container = $("#record-morph"), content = $(".morph-content");
    const first = !container.classList.contains("is-open");
    if (first) morphOrigin = relativeRect(container);
    const origin = relativeRect(container), width = $("#phone-screen").clientWidth - 24;
    // Intrinsic form height, capped by available space. Inner content scrolls, not the viewport.
    content.hidden = false; container.classList.add("is-open"); container.classList.remove("is-settled", "is-closing");
    Object.assign(container.style, { left: origin.left + "px", top: origin.top + "px", width: width + "px", height: origin.height + "px", right: "auto", bottom: "auto" });
    const contentHeight = content.querySelector(".sheet-body").scrollHeight + content.querySelector(".sheet-header").offsetHeight + 18;
    const height = Math.min(contentHeight, $("#phone-screen").clientHeight - 82);
    morphDestination = { left: 12, top: $("#phone-screen").clientHeight - height - 18, width, height };
    const frames = motion.morphFrames(first ? morphOrigin : origin, morphDestination);
    Object.assign(container.style, frames[1]);
    morphAnimation?.cancel();
    const snapshot = currentSheet;
    if (container.animate) {
      morphAnimation = container.animate(reduceMotion() ? [{ opacity: .4 }, { opacity: 1 }] : frames, { duration: reduceMotion() ? motion.TOKENS.fade : motion.TOKENS.duration, easing: motion.TOKENS.easing });
      try { await morphAnimation.finished; } catch { return; }
    }
    if (snapshot !== currentSheet || snapshot.closing) return;
    container.classList.add("is-settled"); content.inert = false; snapshot.host.querySelector("button")?.focus();
  }
  function openSheet(kind, html, saveLabel = "", onSave = null, draft = null, morph = false) {
    if (currentSheet?.closing) return;
    const previousFocus = currentSheet?.previousFocus || document.activeElement;
    const host = morph ? $(".morph-content") : $("#sheet-layer");
    currentSheet = { kind, onSave, draft, baseline: draft ? JSON.stringify(draft) : null, previousFocus, dirty: false, host, morph, closing: false };
    const body = `<div class="sheet-header"><button type="button" data-sheet-action="cancel">取消</button><h2 id="sheet-title">${kind}</h2>${saveLabel ? `<button type="button" data-sheet-action="save">${saveLabel}</button>` : '<span></span>'}</div><div class="sheet-body"><div id="discard-guard" class="discard-guard" hidden><p>有尚未保存的输入。要继续编辑吗？</p><div><button class="secondary-phone-button" type="button" data-sheet-action="continue">继续编辑</button><button class="secondary-phone-button danger-text" type="button" data-sheet-action="discard">放弃修改</button></div></div>${html}<p id="form-error" class="form-error" role="alert" hidden></p></div>`;
    host.innerHTML = morph ? body : `<section class="sheet" role="dialog" aria-modal="true" aria-labelledby="sheet-title">${body}</section>`;
    if (morph) {
      let index = 0;
      for (const item of host.querySelector(".sheet-body").children) {
        if (["discard-guard", "form-error"].includes(item.id)) continue;
        const rows = item.querySelectorAll(".form-row");
        if (rows.length) { item.classList.add("reveal-surface"); for (const row of rows) row.style.setProperty("--item-index", index++); }
        else item.style.setProperty("--reveal-index", index++);
      }
    }
    host.hidden = false; backgroundInert(true); applyAppearance(); localize();
    if (morph) {
      $(".morph-trigger").setAttribute("aria-expanded", "true");
      host.setAttribute("role", "dialog"); host.setAttribute("aria-modal", "true"); host.setAttribute("aria-labelledby", "sheet-title"); host.inert = true;
      $("#morph-backdrop").hidden = false; $("#morph-backdrop").classList.add("is-visible"); settleMorph();
    } else host.querySelector("button").focus();
  }
  async function closeSheet(force = false) {
    if (!currentSheet || currentSheet.closing) return;
    if (!force && currentSheet.dirty) { $("#discard-guard").hidden = false; $("#discard-guard").scrollIntoView({ block: "nearest" }); $("[data-sheet-action=continue]").focus(); return; }
    const sheet = currentSheet, focus = sheet.previousFocus; sheet.closing = true;
    if (sheet.morph) {
      const container = $("#record-morph"), currentRect = relativeRect(container); container.classList.remove("is-settled"); container.classList.add("is-closing"); sheet.host.inert = true;
      $("#morph-backdrop").classList.remove("is-visible"); morphAnimation?.cancel();
      if (container.animate) {
        morphAnimation = container.animate(reduceMotion() ? [{ opacity: .3 }, { opacity: 1 }] : motion.morphFrames(morphOrigin, currentRect), { duration: reduceMotion() ? motion.TOKENS.fade : motion.TOKENS.duration, easing: motion.TOKENS.easing, direction: reduceMotion() ? "normal" : "reverse" });
        try { await morphAnimation.finished; } catch { /* A preference change may cancel motion; still close safely. */ }
      }
      container.classList.remove("is-open", "is-closing"); container.removeAttribute("style"); sheet.host.hidden = true; sheet.host.removeAttribute("role"); sheet.host.removeAttribute("aria-modal"); sheet.host.inert = false;
      $(".morph-trigger").setAttribute("aria-expanded", "false");
      $("#morph-backdrop").hidden = true;
    } else sheet.host.hidden = true;
    sheet.host.innerHTML = ""; currentSheet = null; backgroundInert(false);
    if (focus?.isConnected) focus.focus(); else $(".morph-trigger").focus();
  }
  function formError(text) { $("#form-error").textContent = text; $("#form-error").hidden = false; localize(); }
  function openEntryChooser() {
    openSheet("记录一餐", `<button class="choice-button" type="button" data-sheet-action="blank">${icon("edit")}<span><strong>空白记录</strong><small>选择一个演示食物，再输入重量</small></span></button><button class="choice-button" type="button" data-sheet-action="reuse">${icon("history")}<span><strong>常用牛肉青椒饭</strong><small>350 g · 改一下重量即可</small></span></button><p class="screen-note">这是简化的交互演示，不会存入正式 App。</p>`, "", null, null, true);
  }
  function openMealEditor(foodId = "beef-rice", grams = "", name = null) {
    name ??= window.ShiHengI18n.translate("午餐", state.language);
    const draft = { name, foodId, grams: String(grams) };
    const options = DEMO_FOODS.map(food => `<option value="${food.id}" ${food.id === foodId ? "selected" : ""}>${food.name}</option>`).join("");
    openSheet("记录一餐", `<section class="card"><label class="form-row" for="meal-name">餐食名称<input id="meal-name" name="name" maxlength="60" value="${escapeHTML(name)}" autocomplete="off"></label><label class="form-row" for="meal-food">演示食物<select id="meal-food" name="foodId">${options}</select></label><label class="form-row" for="meal-grams">我吃的重量（g）<input id="meal-grams" name="grams" type="number" min="1" max="5000" step="1" value="${escapeHTML(grams)}" inputmode="decimal" placeholder="例如 350"></label></section><section class="card"><h3>本餐预览</h3><p id="meal-preview" class="meal-preview-value">— <small>kcal</small></p><p id="meal-macros" class="card-caption">输入重量后计算演示值。</p></section><p class="screen-note">演示营养按每 100 g 换算；不是食品库数据。保存只更新此次网页会话。</p>`, "保存", () => {
      const amount = Number(draft.grams), food = DEMO_FOODS.find(item => item.id === draft.foodId), values = portionNutrition(food, amount);
      if (!draft.name.trim() || !values) { formError("请填写餐名，并输入大于 0、不超过 5000 g 的有效重量。"); return; }
      if (state.totals.energy + values.energy > 10000) { formError("示例总摄入上限为 10000 kcal，请先切换到空记录再试。"); return; }
      for (const key of Object.keys(state.totals)) state.totals[key] += values[key];
      state.meals.push({ id: "added-" + Date.now(), name: draft.name.trim(), time: "18:30", energy: values.energy, evidence: "网页模拟", foodId: draft.foodId, grams: amount });
      state.hasRecords = true; state.preset = "custom"; state.page = "today"; closeSheet(true); syncIntakeControls(); renderPhone(true); toast("已加入模拟记录，圆环与营养条已重算。");
    }, draft, true);
    updateMealPreview();
  }
  function updateMealPreview() {
    const draft = currentSheet?.draft; if (!draft || !$("#meal-preview")) return;
    const values = portionNutrition(DEMO_FOODS.find(food => food.id === draft.foodId), Number(draft.grams));
    $("#meal-preview").innerHTML = `${values ? format(values.energy) : "—"} <small>kcal</small>`;
    $("#meal-macros").textContent = values ? `蛋白质 ${format(values.protein)} g · 碳水 ${format(values.carbohydrate)} g · 脂肪 ${format(values.fat)} g` : "输入重量后计算演示值。";
    localize();
  }
  function openGoals() {
    const draft = { energy: String(state.goals.energy), protein: String(state.goals.protein), carbohydrate: String(state.goals.carbohydrate), fat: String(state.goals.fat), saturatedFat: String(state.goals.saturatedFat), fibre: String(state.goals.fibre) };
    const names = { energy: "热量预算（kcal）", protein: "蛋白质最低目标（g）", carbohydrate: "碳水预算（g）", fat: "脂肪预算（g）", saturatedFat: "饱和脂肪上限（g）", fibre: "纤维最低目标（g）" };
    openSheet("演示目标", `<section class="card">${Object.entries(names).map(([key, label]) => `<label class="form-row" for="goal-${key}">${label}<input id="goal-${key}" name="${key}" type="number" min="${key === "energy" ? 1 : 0}" max="${key === "energy" ? 10000 : 1000}" step="1" value="${draft[key]}" inputmode="decimal"></label>`).join("")}</section><p class="screen-note">这里预填的是虚构样例，不是系统给你的营养建议。正式 App 的目标须由本人明确确认。</p>`, "应用", () => {
      const values = Object.fromEntries(Object.entries(draft).map(([key, value]) => [key, Number(value)]));
      if (Object.entries(values).some(([key, value]) => !draft[key].trim() || !finite(value) || value < (key === "energy" ? 1 : 0) || value > (key === "energy" ? 10000 : 1000))) { formError("请填写范围内的有效数字；热量须大于 0。"); return; }
      state.goals = values; state.hasGoal = true; state.preset = "custom"; closeSheet(true); syncIntakeControls(); renderPhone(); toast("演示目标已更新。");
    }, draft);
  }
  function openBudget() {
    const draft = { energy: state.hasGoal ? String(state.goals.energy) : "" };
    openSheet("今日热量预算", `<section class="card"><label class="form-row" for="goal-energy">热量预算（kcal）<input id="goal-energy" name="energy" type="number" min="1" max="10000" value="${draft.energy}" inputmode="decimal"></label></section><p class="screen-note">只调整演示热量预算，其他营养目标不变。</p>`, "应用", () => {
      const energy = Number(draft.energy);
      if (!draft.energy.trim() || !finite(energy) || energy <= 0 || energy > 10000) { formError("请填写范围内的有效数字；热量须大于 0。"); return; }
      state.goals.energy = energy; state.hasGoal = true; state.preset = "custom"; closeSheet(true); syncIntakeControls(); renderPhone(); toast("演示目标已更新。");
    }, draft);
  }
  function toggleMealDetails(id) {
    const list = state.page === "calendar" ? calendarData(state.selectedDate)?.meals || [] : state.meals;
    const meal = list.find(item => item.id === id); if (!meal) return;
    const button = document.querySelector(`[data-meal="${id}"]`), row = button.closest(".meal-accordion"), expansion = row.querySelector(".meal-expansion");
    if (row.classList.contains("expanded")) { collapseMeal(row); return; }
    const currentHeight = expansion.hidden ? 0 : expansion.getBoundingClientRect().height;
    for (const other of document.querySelectorAll(".meal-accordion.expanded")) collapseMeal(other);
    expansion.innerHTML = `<div class="meal-details"><div class="detail-image"><span class="food-illustration" aria-hidden="true">${icon("food")}</span><small>示意图</small></div><div class="detail-copy"><h4 data-user-content>${escapeHTML(mealDisplayName(meal))}</h4><p>虚构示意，不是原餐真实配方。</p><div class="key-value"><span>已记录热量</span><span>${format(meal.energy)} kcal</span></div><div class="key-value"><span>演示份量</span><span>${meal.grams ? format(meal.grams) + ' g' : '—'}</span></div><button class="secondary-phone-button" type="button" data-action="reuse-meal" data-reuse-id="${meal.id}">复用这餐</button></div><div class="detail-tags"><span>${escapeHTML(meal.evidence)}</span><span>按你实际吃的量记录</span></div></div>`;
    expansion.hidden = false; expansion.inert = true; row.classList.add("expanded"); row.classList.remove("collapsing"); button.setAttribute("aria-expanded", "true");
    localize();
    const targetHeight = expansion.scrollHeight;
    expansion.style.height = targetHeight + "px";
    row._motion?.cancel();
    row._motion = expansion.animate([{ height: currentHeight + "px" }, { height: targetHeight + "px" }], { duration: reduceMotion() ? 1 : motion.TOKENS.duration, easing: motion.TOKENS.easing });
    row._motion.finished.then(() => { if (row.classList.contains("expanded")) { row.classList.add("settled"); expansion.inert = false; expansion.style.height = "auto"; } }).catch(() => {});
  }
  function collapseMeal(row) {
    const expansion = row.querySelector(".meal-expansion"), height = expansion.getBoundingClientRect().height;
    row._motion?.cancel(); row.classList.remove("expanded", "settled"); row.classList.add("collapsing");
    row.querySelector("[data-meal]").setAttribute("aria-expanded", "false"); expansion.inert = true;
    expansion.style.height = "0px";
    row._motion = expansion.animate([{ height: "0px" }, { height: height + "px" }], { duration: reduceMotion() ? 1 : motion.TOKENS.duration, easing: motion.TOKENS.easing, direction: "reverse" });
    row._motion.finished.then(() => { if (!row.classList.contains("expanded")) { expansion.hidden = true; row.classList.remove("collapsing"); } }).catch(() => {});
  }
  function reuseMeal(id) {
    const list = state.page === "calendar" ? calendarData(state.selectedDate)?.meals || [] : state.meals;
    const meal = list.find(item => item.id === id); if (!meal) return;
    const foodId = meal.foodId || ({ "demo-1": "oats", "demo-2": "beef-rice", "demo-3": "tomato-egg" })[id];
    const food = DEMO_FOODS.find(item => item.id === foodId);
    openMealEditor(foodId, meal.grams || Math.round(meal.energy / food.energy * 100), mealDisplayName(meal));
  }
  function bindTrend() {
    const strip = $(".trend-points"); if (!strip) return;
    const buttons = [...strip.querySelectorAll("[data-trend-date]")];
    const selected = buttons.find(button => button.dataset.trendDate === state.trendDate) || buttons.at(-1);
    strip.scrollLeft = selected.offsetLeft - strip.offsetLeft + selected.offsetWidth / 2 - strip.clientWidth / 2;
    const metric = $("#trend-value"), next = metric?.hasAttribute("data-value") ? Number(metric.dataset.value) : null;
    if (next !== null) motion.animateCounter(metric, next, previousTrendValue ?? next, reduceMotion(), state.language === "en" ? "en-GB" : "zh-CN");
    previousTrendValue = next;
    strip.addEventListener("scroll", () => {
      clearTimeout(trendScrollTimer);
      trendScrollTimer = setTimeout(() => {
        if (!strip.isConnected) return;
        const centers = buttons.map(button => button.offsetLeft - strip.offsetLeft + button.offsetWidth / 2);
        const index = trends.nearestPointIndex(centers, strip.scrollLeft + strip.clientWidth / 2);
        if (index >= 0 && buttons[index].dataset.trendDate !== state.trendDate) selectTrend(buttons[index].dataset.trendDate);
      }, 140);
    }, { passive: true });
    strip.addEventListener("keydown", event => {
      const index = buttons.indexOf(event.target); if (index < 0) return;
      let nextIndex = index;
      if (event.key === "ArrowRight") nextIndex = Math.min(6, index + 1);
      else if (event.key === "ArrowLeft") nextIndex = Math.max(0, index - 1);
      else if (event.key === "Home") nextIndex = 0;
      else if (event.key === "End") nextIndex = 6;
      else return;
      event.preventDefault(); selectTrend(buttons[nextIndex].dataset.trendDate, true);
    });
    const chart = $(".trend-chart");
    let pointer = null;
    chart.addEventListener("pointerdown", event => { pointer = { x: event.clientX, date: state.trendDate }; chart.setPointerCapture(event.pointerId); });
    chart.addEventListener("pointerup", event => {
      if (!pointer) return;
      const delta = event.clientX - pointer.x;
      let index;
      if (Math.abs(delta) > 20) index = Math.max(0, Math.min(6, buttons.findIndex(button => button.dataset.trendDate === pointer.date) - Math.round(delta / 48)));
      else { const rect = chart.getBoundingClientRect(); index = Math.max(0, Math.min(6, Math.round(((event.clientX - rect.left) / rect.width * 360 - 24) / 52))); }
      pointer = null; selectTrend(buttons[index].dataset.trendDate);
    });
    chart.addEventListener("pointercancel", () => { pointer = null; });
  }
  function selectTrend(date, focus = false) {
    state.trendDate = date; state.selectedDate = date; renderPhone();
    if (focus) document.querySelector(`[data-trend-date="${date}"]`)?.focus({ preventScroll: true });
  }
  function savePreferences() {
    try { localStorage.setItem("shiheng-preview-preferences", JSON.stringify(energyVisual.normalizePreferences(state))); } catch { /* Session settings still work. */ }
  }
  function changeIntake(value) {
    if (!finite(value) || value < 0 || value > 10000) return false;
    const ratio = value / FIXTURES.normal.energy;
    for (const key of Object.keys(state.totals)) state.totals[key] = key === "energy" ? value : FIXTURES.normal[key] * ratio;
    state.hasRecords = true; state.meals = fixtureMeals(value); state.preset = "custom"; syncIntakeControls(); renderPhone(); return true;
  }
  document.addEventListener("click", event => {
    const button = event.target.closest("button"); if (!button || !config) return;
    if (currentSheet?.closing) return;
    if (button.dataset.page) { if (currentSheet || button.dataset.page === state.page) return; state.pageScroll[state.page] = $("#phone-content").scrollTop; state.page = button.dataset.page; renderPhone(true, true); }
    if (button.dataset.preset) { setPreset(button.dataset.preset); }
    if (energyVisual.MODES.includes(button.dataset.energyMode)) { state.energyVisualMode = button.dataset.energyMode; savePreferences(); renderPhone(); }
    if (button.dataset.meal) toggleMealDetails(button.dataset.meal);
    if (button.dataset.trendDate) selectTrend(button.dataset.trendDate, true);
    if (button.dataset.date) { state.selectedDate = button.dataset.date; if (trends.buildSevenDaySeries(DEMO_DATE, calendarData).some(point => point.date === state.selectedDate)) state.trendDate = state.selectedDate; renderPhone(); }
    const action = button.dataset.action;
    if (action === "entry") { if (currentSheet) return; openMealEditor(); }
    if (action === "reuse-meal") reuseMeal(button.dataset.reuseId);
    if (action === "goals") openGoals();
    if (action === "budget") openBudget();
    if (action === "scan") { state.scanResult = true; renderPhone(); toast("已载入固定样例，没有上传或识别照片。"); }
    if (action === "scan-record") openMealEditor("oats", "50", "燕麦片");
    if (action === "toggle-theme") { config.theme = config.theme === "light" ? "dark" : "light"; saveDesign(); renderPhone(); }
    if (action === "previous-month" || action === "next-month") { state.calendarMonth = new Date(state.calendarMonth.getFullYear(), state.calendarMonth.getMonth() + (action === "next-month" ? 1 : -1), 1); renderPhone(); }
    const sheetAction = button.dataset.sheetAction;
    if (sheetAction === "cancel") closeSheet();
    if (sheetAction === "discard") closeSheet(true);
    if (sheetAction === "continue") { $("#discard-guard").hidden = true; currentSheet?.host.querySelector("input")?.focus(); }
    if (sheetAction === "blank") openMealEditor();
    if (sheetAction === "reuse") openMealEditor("beef-rice", "350", "牛肉青椒饭");
    if (sheetAction === "save") { document.activeElement.blur(); currentSheet?.onSave?.(); }
  });
  function updateDraft(event) {
    if (!currentSheet?.draft || !event.target.name) return;
    currentSheet.draft[event.target.name] = event.target.value;
    currentSheet.dirty = JSON.stringify(currentSheet.draft) !== currentSheet.baseline || [...currentSheet.host.querySelectorAll("input")].some(input => input.validity.badInput); updateMealPreview();
  }
  for (const host of [$("#sheet-layer"), $(".morph-content")]) for (const event of ["input", "change"]) host.addEventListener(event, updateDraft);
  $("#morph-backdrop").addEventListener("click", () => closeSheet());
  document.addEventListener("change", event => {
    if (event.target.id === "language") { state.language = event.target.value === "en" ? "en" : "zh"; document.documentElement.lang = state.language === "en" ? "en" : "zh-CN"; savePreferences(); renderPhone(); }
    if (event.target.id === "reduce-motion") { state.reduceMotion = event.target.checked; savePreferences(); renderPhone(); }
    if (event.target.id === "reduce-transparency") { state.reduceTransparency = event.target.checked; savePreferences(); renderPhone(); }
  });
  systemReduced.addEventListener("change", () => { applyAppearance(); pageAnimation?.cancel(); if (currentSheet?.morph) { morphAnimation?.cancel(); $("#record-morph").classList.add("is-settled"); currentSheet.host.inert = false; } });
  document.addEventListener("keydown", event => {
    if (!currentSheet) return;
    if (event.key === "Escape") { event.preventDefault(); closeSheet(); }
    if (event.key === "Enter" && event.target.matches("input")) { event.preventDefault(); event.target.blur(); $("[data-sheet-action=save]")?.focus(); }
    if (event.key === "Tab") {
      const focusable = [...currentSheet.host.querySelectorAll("button:not(:disabled), input, select")].filter(element => element.getClientRects().length && !element.closest("[inert]"));
      if (!focusable.length) { event.preventDefault(); return; }
      if (!currentSheet.host.contains(document.activeElement)) { event.preventDefault(); (event.shiftKey ? focusable.at(-1) : focusable[0]).focus(); return; }
      if (event.shiftKey && document.activeElement === focusable[0]) { event.preventDefault(); focusable.at(-1).focus(); }
      if (!event.shiftKey && document.activeElement === focusable.at(-1)) { event.preventDefault(); focusable[0].focus(); }
    }
  });
  for (const theme of ["light", "dark"]) $("#" + theme + "-mode").addEventListener("click", () => { config.theme = theme; saveDesign(); renderPhone(); });
  $("#color-controls").addEventListener("input", event => {
    if (!event.target.dataset.color) return;
    const key = event.target.dataset.color, value = event.target.value.toUpperCase();
    if (!/^#[0-9A-F]{6}$/.test(value)) { event.target.setAttribute("aria-invalid", "true"); return; }
    event.target.removeAttribute("aria-invalid"); config.colors[key] = value;
    $("#hex-" + key).value = value; $("#color-" + key).value = value;
    saveDesign(); renderPhone();
    if (currentSheet) applyAppearance();
  });
  for (const field of ["radius", "density", "warning"]) $("#" + field).addEventListener("input", event => {
    const value = Number(event.target.value);
    if (field === "radius") { config.radius = value; $("#radius-value").textContent = value + " px"; }
    if (field === "density") { config.density = value / 100; $("#density-value").textContent = value + "%"; }
    if (field === "warning") { config.warningPercent = value; $("#warning-value").textContent = value + "%"; }
    saveDesign(); renderPhone();
  });
  $("#intake").addEventListener("input", event => { if (!event.target.value.trim() || !changeIntake(Number(event.target.value))) message("摄入演示值须为 0–10000 kcal。", true); else message(""); });
  $("#intake").addEventListener("blur", syncIntakeControls);
  $("#intake-slider").addEventListener("input", event => { changeIntake(Number(event.target.value)); });
  $("#goal").addEventListener("input", event => {
    const value = Number(event.target.value); if (!event.target.value.trim() || !finite(value) || value < 1 || value > 10000) { message("预算演示值须为 1–10000 kcal；可用“未设目标”查看空目标。", true); return; }
    state.goals.energy = value; state.hasGoal = true; state.preset = "custom"; syncIntakeControls(); renderPhone(); message("");
  });
  $("#goal").addEventListener("blur", syncIntakeControls);
  $("#export-design").addEventListener("click", () => {
    const link = document.createElement("a"); link.href = "/api/design-export?config=" + encodeURIComponent(JSON.stringify(config)); link.download = "ShiHeng-design-v1.json";
    document.body.append(link); link.click(); link.remove(); message("已请求下载配色 JSON，不包含模拟餐食。");
  });
  $("#import-design").addEventListener("change", async event => {
    const file = event.target.files[0]; if (!file) return;
    try {
      if (file.size > 8192) throw new Error("方案文件不能超过 8 KiB。");
      // Send the raw JSON to the loopback server so duplicate fields are rejected.
      const response = await fetch("/api/validate-design", { method: "POST", headers: { "Content-Type": "application/json" }, body: await file.text() });
      const result = await response.json(); if (!response.ok || !result.valid || !validateConfig(result.config)) throw new Error("方案格式或字段无效；原方案未改变。");
      config = result.config; saveDesign(); syncControls(); renderPhone(); message("方案已导入，手机预览已更新。");
    } catch (error) { message(error.message || "导入失败，原方案未改变。", true); }
    event.target.value = "";
  });
  $("#reset-design").addEventListener("click", () => { config = clone(initialConfig); saveDesign(); syncControls(); renderPhone(); message("已恢复初始配色。模拟记录不受影响。"); });
  function setControlsOpen(open) {
    $("#design-controls").classList.toggle("open", open); $("#toggle-controls").setAttribute("aria-expanded", String(open));
    if (open) $("#close-controls").focus(); else $("#toggle-controls").focus();
  }
  $("#toggle-controls").addEventListener("click", () => setControlsOpen(!$("#design-controls").classList.contains("open")));
  $("#close-controls").addEventListener("click", () => setControlsOpen(false));
  async function boot() {
    try {
      const response = await fetch("/api/preview-config"); if (!response.ok) throw new Error("config unavailable");
      const defaults = await response.json(); if (!validateConfig(defaults)) throw new Error("invalid config");
      initialConfig = clone(defaults); config = clone(defaults);
      try { Object.assign(state, energyVisual.normalizePreferences(JSON.parse(localStorage.getItem("shiheng-preview-preferences") || "{}"))); } catch { /* Invalid preference cannot corrupt design or meal state. */ }
      document.documentElement.lang = state.language === "en" ? "en" : "zh-CN";
      try { const cached = localStorage.getItem(STORAGE_KEY); if (cached) { const parsed = JSON.parse(cached); if (validateConfig(parsed)) config = parsed; else message("浏览器内的旧方案无效，已使用初始方案。"); } } catch { message("无法读取浏览器方案，已使用初始方案。"); }
      for (const element of document.querySelectorAll("[data-icon]")) element.innerHTML = icon(element.dataset.icon);
      $(".morph-trigger").innerHTML = icon("plus") + '<span class="fab-label">记录一餐</span>';
      state.meals = fixtureMeals(state.totals.energy); syncControls(); renderPhone();
    } catch {
      $("#phone-content").innerHTML = '<p class="form-error">本地服务未能载入。请重启 Flask 服务后刷新页面。</p>'; message("预览未载入，请检查本地服务。", true);
      for (const input of document.querySelectorAll(".controls input, .controls button")) input.disabled = true;
    }
  }
  boot();
})();

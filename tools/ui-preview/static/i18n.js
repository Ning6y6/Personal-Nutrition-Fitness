/* Preview-only language adapter. User inputs, JSON data, and native app files stay untouched. */
(() => {
  "use strict";
  const phrases = {
    "只调整演示热量预算，其他营养目标不变。": "Only the demo energy budget changes. Other nutrient targets stay the same.",
    "衡": "衡", "食衡": "ShiHeng", "调色工作台": "Design studio", "食衡 · UI 调色工作台": "ShiHeng · Design studio",
    "温和精确 · Calm Precision": "Calm Precision", "本地原型 · 虚构数据": "Local prototype · Fictional data",
    "调色": "Customize", "设计调整": "Design controls", "完成调色，返回预览": "Done · Back to preview",
    "01 / 外观": "01 / Appearance", "02 / 热量状态": "02 / Energy state", "03 / 保留方案": "03 / Save your design",
    "实时预览": "Live preview", "外观模式": "Appearance mode", "浅色": "Light", "深色": "Dark", "外观": "Appearance",
    "卡片圆角": "Card radius", "内容间距": "Content spacing", "示例状态": "Demo states",
    "进度绿色": "Progress green", "接近黄色": "Approaching yellow", "达到红色": "Reached red",
    "浅色背景": "Light background", "浅色卡片": "Light cards", "深色背景": "Dark background", "深色卡片": "Dark cards",
    "有余量": "Room left", "接近预算": "Near budget", "刚好达到": "Exactly reached", "超过预算": "Over budget",
    "没有记录": "No records", "未设目标": "No target", "已记录 kcal": "Logged kcal", "热量预算 kcal": "Energy budget kcal",
    "模拟摄入": "Demo intake", "变黄起点": "Yellow threshold",
    "仅演示拟议配色：预算未到变黄线为绿，接近为黄，达到或超过为红。下限营养素不套用此规则。": "Proposed preview colors only: green below the warning threshold, yellow near budget, red at or above budget. Minimum nutrient goals use a different rule.",
    "导出配色 JSON": "Export design JSON", "导入方案": "Import design", "恢复初始方案": "Reset design",
    "配色仅保存在此浏览器。模拟餐食刷新后重置。": "Design is saved only in this browser. Demo meals reset on refresh.",
    "此浏览器不允许本地保存；请导出 JSON 保留方案。": "This browser cannot save locally. Export JSON to keep your design.",
    "手机交互预览": "Interactive phone preview", "风格预览": "Style preview",
    "点手机内的按钮试流程；改左侧参数看变化。": "Try the phone buttons, or adjust the controls to see changes.",
    "示意画布 · 非 iOS 模拟器": "Illustrative canvas · Not an iOS simulator", "正在载入本地预览…": "Loading local preview…",
    "主页面": "Main pages", "今日": "Today", "扫描": "Scan", "日历": "Calendar", "设置": "Settings", "趋势": "Trends",
    "已达 / 超出": "Reached / Over", "颜色之外，始终显示状态文字": "Status is always expressed in words, not just color",
    "尚无可汇总记录": "No records to summarize", "尚未设置目标": "No target set", "目标无法计算": "Target cannot be calculated",
    "最低目标已达到": "Minimum goal reached", "已达上限，尚未超出": "At the limit, not over", "已达预算，尚未超出": "Budget reached, not over",
    "不足 0.1": "Less than 0.1", "今天尚未记录": "Nothing logged today",
    "记下第一餐后，再查看已记录摄入与预算余量。": "Log your first meal to see recorded intake and remaining budget.",
    "已记录热量": "Logged energy", "今日预算": "Today's budget", "今日热量预算": "Today's energy budget", "尚未设置": "Not set",
    "点击调整": "Tap to adjust", "调整演示目标": "Adjust demo targets", "调整今日预算": "Adjust today's budget",
    "记录一餐": "Log a meal", "关闭": "Close", "关闭记录面板": "Close meal panel", "打开记录面板": "Open meal panel",
    "蛋白质": "Protein", "碳水": "Carbs", "碳水化合物": "Carbohydrate", "脂肪": "Fat", "饱和脂肪": "Saturated fat", "纤维": "Fibre", "热量": "Energy",
    "今日餐食": "Today's meals", "还没有餐食记录。": "No meals logged yet.",
    "只表示已记录的摄入，不代表今天所有餐食都已记全。": "This is recorded intake only. It does not mean every meal today has been logged.",
    "包装上的信息，变成自己的食物": "Turn a food label into your own food entry", "包装标签预览区域": "Food label preview area",
    "重新模拟扫描": "Run demo scan again", "模拟扫描标签": "Demo label scan",
    "不调用相机或模型；下方展示固定示例。": "No camera or model is used. The result below is a fixed example.",
    "示例结果 · 未核对": "Demo result · Unchecked", "原味燕麦片": "Plain rolled oats", "需要人工核对": "Needs manual review",
    "没有真实配料、认证或药物信息，不提供购买与安全结论。": "No real ingredients, certifications, or medication information is available. No purchase or safety verdict is provided.",
    "计量基准": "Nutrition basis", "每 100 g": "Per 100 g", "蛋白质 / 碳水 / 脂肪": "Protein / Carbs / Fat",
    "按克数模拟记录": "Log demo grams", "把营养表变成常用食物": "Turn nutrition facts into a saved food",
    "正式扫描与自定义食品仍待开发。这里先确认页面布局与记录流程。": "Real scanning and custom foods are not implemented. This preview tests layout and the recording flow.",
    "看见每一天，而不是只看平均值": "See each day, not just an average", "上个月": "Previous month", "下个月": "Next month",
    "一": "Mon", "二": "Tue", "三": "Wed", "四": "Thu", "五": "Fri", "六": "Sat", "日": "Sun",
    "数字：已记录 kcal": "Numbers: logged kcal", "—：没有记录，不是 0": "—: no records, not zero", "无记录": "No records",
    "示例完整日": "Demo complete day", "未确认完整": "Completeness unconfirmed", "尚未确认整天记全": "Full-day coverage not confirmed", "虚构数据": "Fictional data",
    "这一天没有记录，不纳入真实平均计算。": "No records for this day. It is not included in real averages.",
    "日历、日级确认与历史目标查询在正式 App 中尚未交付；这里只是设计演示。": "The native calendar, day confirmation, and historical targets are not delivered. This is a design demo only.",
    "你的目标，你的节奏": "Your targets. Your pace.", "每日营养目标": "Daily nutrition targets", "未设置": "Not set",
    "常用餐预览": "Saved meal preview", "复用示例": "Try reuse", "本地设计沙盒": "Local design sandbox",
    "食物与数值只用于交互测试。没有登录、云同步、照片上传或真实扫描。": "Foods and numbers are for interaction testing only. There is no login, cloud sync, photo upload, or real scanning.",
    "设计版本": "Design version", "热量变黄起点": "Energy warning threshold", "达到热量预算": "Energy budget reached", "拟议": "Proposed", "红色 · 尚未超出": "Red · Not over yet",
    "配色可在外侧面板导出，未来用于 SwiftUI 改版。原型不会自动改写正式项目的规则或数据。": "Export your design from the outer controls for a future SwiftUI redesign. This prototype never changes native rules or data.",
    "取消": "Cancel", "保存": "Save", "应用": "Apply", "有尚未保存的输入。要继续编辑吗？": "You have unsaved changes. Continue editing?",
    "继续编辑": "Keep editing", "放弃修改": "Discard changes", "空白记录": "Start from scratch", "选择一个演示食物，再输入重量": "Choose a demo food, then enter its weight",
    "常用牛肉青椒饭": "Saved beef & pepper rice", "350 g · 改一下重量即可": "350 g · Just adjust the weight",
    "这是简化的交互演示，不会存入正式 App。": "This simplified demo does not save to the native app.",
    "餐食名称": "Meal name", "演示食物": "Demo food", "我吃的重量（g）": "Weight I ate (g)", "例如 350": "e.g. 350",
    "本餐预览": "Meal preview", "输入重量后计算演示值。": "Enter a weight to calculate demo nutrition.",
    "演示营养按每 100 g 换算；不是食品库数据。保存只更新此次网页会话。": "Demo nutrition scales from values per 100 g, not a food database. Saving only updates this browser session.",
    "请填写餐名，并输入大于 0、不超过 5000 g 的有效重量。": "Enter a meal name and a valid weight greater than 0 and no more than 5000 g.",
    "示例总摄入上限为 10000 kcal，请先切换到空记录再试。": "The demo supports up to 10000 kcal. Switch to no records before trying again.",
    "已加入模拟记录，圆环与营养条已重算。": "Demo meal added. The ring and nutrient bars have updated.",
    "牛肉青椒饭（演示）": "Beef & pepper rice (demo)", "番茄炒蛋（演示）": "Tomato & eggs (demo)", "鸡肉饭（演示）": "Chicken rice (demo)", "燕麦片（演示）": "Rolled oats (demo)",
    "燕麦与酸奶": "Oats & yoghurt", "牛肉青椒饭": "Beef & pepper rice", "番茄鸡蛋与水果": "Tomato, eggs & fruit", "燕麦片": "Rolled oats", "午餐": "Lunch", "演示": "Demo", "网页模拟": "Web demo",
    "演示目标": "Demo targets", "热量预算（kcal）": "Energy budget (kcal)", "蛋白质最低目标（g）": "Protein minimum (g)", "碳水预算（g）": "Carb budget (g)", "脂肪预算（g）": "Fat budget (g)", "饱和脂肪上限（g）": "Saturated fat limit (g)", "纤维最低目标（g）": "Fibre minimum (g)",
    "这里预填的是虚构样例，不是系统给你的营养建议。正式 App 的目标须由本人明确确认。": "These prefilled values are fictional examples, not nutrition advice. Native app targets require your explicit confirmation.",
    "请填写范围内的有效数字；热量须大于 0。": "Enter valid numbers within the allowed range. Energy must be greater than 0.",
    "演示目标已更新。": "Demo targets updated.", "餐食详情": "Meal details", "复用为新一餐": "Reuse as a new meal", "复用这餐": "Reuse this meal",
    "复用为牛肉青椒饭演示模板；不是原记录的精确食材映射。": "Reuses a beef & pepper rice demo template, not an exact ingredient mapping of the original meal.",
    "已载入固定样例，没有上传或识别照片。": "Fixed demo loaded. No photos were uploaded or analyzed.",
    "摄入演示值须为 0–10000 kcal。": "Demo intake must be 0–10000 kcal.", "预算演示值须为 1–10000 kcal；可用“未设目标”查看空目标。": "Demo budget must be 1–10000 kcal. Use “No target” to preview an unset target.",
    "已请求下载配色 JSON，不包含模拟餐食。": "Design JSON download requested. It contains no demo meals.", "方案文件不能超过 8 KiB。": "Design files must not exceed 8 KiB.",
    "方案格式或字段无效；原方案未改变。": "Invalid design format or fields. Your original design is unchanged.", "方案已导入，手机预览已更新。": "Design imported. The phone preview has updated.", "导入失败，原方案未改变。": "Import failed. Your original design is unchanged.",
    "已恢复初始配色。模拟记录不受影响。": "Original design restored. Demo records are unchanged.", "浏览器内的旧方案无效，已使用初始方案。": "The saved browser design is invalid. Using the original design.",
    "无法读取浏览器方案，已使用初始方案。": "Cannot read the saved browser design. Using the original design.", "本地服务未能载入。请重启 Flask 服务后刷新页面。": "The local service could not load. Restart Flask and refresh this page.", "预览未载入，请检查本地服务。": "Preview not loaded. Check the local service.",
    "最近七日": "Last seven days", "最近 7 日": "Last 7 days", "连续记录": "Logging streak", "天": "days", "不奖励少吃，只鼓励坚持记录。": "Consistency counts, not eating less.",
    "演示日期": "Demo date", "语言": "Language", "中文": "中文", "English": "English", "减少动态效果": "Reduce motion", "跟随系统": "Follow system", "减少透明度": "Reduce transparency",
    "关闭动态效果": "Disable motion", "开启": "On", "关闭效果": "Off", "自动": "Automatic", "开启 · 本地预览": "On · Local preview", "关闭 · 本地预览": "Off · Local preview",
    "最近七日已记录热量": "Logged energy · Last seven days", "最近七日 · 虚构数据": "Last seven days · Fictional data", "横向滑动查看每天的记录": "Swipe sideways to explore each day", "滑动查看每天的记录": "Swipe to explore each day",
    "记录习惯，比完美更重要": "Consistency over perfection", "记录比完美更重要": "Consistency over perfection", "连续记录天数": "Consecutive logging days", "每一天都算数": "Every logged day counts",
    "热量记录趋势": "Logged energy trend", "七日热量趋势": "Seven-day energy trend", "每日已记录热量": "Daily logged energy", "选择日期": "Select date", "查看这天的餐食": "View this day's meals",
    "一周的节奏，慢慢看清楚": "Find your rhythm, one week at a time", "看见记录，也看见坚持": "See your records. See your consistency.", "演示数据，不用于真实平均或达标判断。": "Demo data only; not used for real averages or goal assessment.",
    "绘制中的折线表示已记录热量，不代表完整日摄入。": "The line shows logged energy, not necessarily complete-day intake.", "只鼓励记录，不奖励少吃。": "Celebrate logging, not eating less.", "今天": "Today", "昨天": "Yesterday",
    "图示": "Illustration", "营养": "Nutrition", "标签": "Tags", "餐食": "Meals", "重量": "Weight", "已记录": "Logged", "未记录": "Not logged", "已展开": "Expanded", "已收起": "Collapsed",
    "包括今天": "Including today", "截至昨天": "Through yesterday", "今天还可以接上": "You can continue today", "截至昨天；今天还可以接上": "Through yesterday; you can continue today",
    "跟随系统减少动态效果；也可以在这里开启。": "Follows your system's reduced-motion setting. You can also enable it here.",
    "调整每日热量预算": "Adjust daily energy budget", "虚构示意，不是原餐真实配方。": "Fictional illustration, not the original meal's actual recipe.",
    "点击行标题收起": "Tap the row title to collapse", "选择食物，输入重量": "Choose a food and enter its weight", "直接记录": "Quick log", "记录成功": "Meal logged",
    "示意图": "Illustration", "记录方式": "Recording method", "示意食材": "Illustrative ingredients", "演示份量": "Demo portion",
    "图、文字和标签分阶段展开": "Illustration, details and tags appear in stages", "按你实际吃的量记录": "Log the amount you actually ate", "快速复用": "Quick reuse",
    "本地预览": "Local preview", "未保存的输入": "Unsaved changes", "图表支持左右滑动或方向键选择日期。": "Swipe sideways or use the arrow keys to select a day.",
    "虚构预览。已记录热量不代表整天已记全。": "Fictional preview. Recorded energy does not confirm a complete day.", "断点表示没有记录。": "Gaps indicate missing records.",
    "热量显示方式": "Energy visualization", "圆环": "Ring", "水位圆圈": "Water fill",
    "水位仅表示已记录热量与预算的比例，不是饮水记录；超过预算后水位封顶，实际超出量照常显示。": "Water level shows logged energy relative to the budget, not hydration. The visual caps at full; actual excess remains visible.",
    "水位代表已记录热量，不代表整天已记全。": "Water level shows logged energy, not a confirmed complete day."
  };
  const monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
  const shortMonths = monthNames.map(month => month.slice(0, 3));
  const weekdays = { 一: "Monday", 二: "Tuesday", 三: "Wednesday", 四: "Thursday", 五: "Friday", 六: "Saturday", 日: "Sunday", 天: "Sunday" };
  const statuses = {
    "距离最低目标还差": "To minimum goal:", "超出上限": "Over the limit by", "接近上限，还余": "Near the limit; remaining",
    "距上限剩余": "Below the limit by", "超出预算": "Over budget by", "接近预算，还余": "Near budget; remaining", "预算剩余": "Budget remaining"
  };
  const textSources = new WeakMap();
  const attributeSources = new WeakMap();
  const isEnglish = language => /^en(?:-|$)/i.test(String(language || ""));

  function translate(text, language = "zh") {
    if (typeof text !== "string" || !isEnglish(language)) return text;
    const core = text.trim();
    if (!core) return text;
    const leading = text.match(/^\s*/)[0], trailing = text.match(/\s*$/)[0];
    let result;
    if (Object.hasOwn(phrases, core)) result = phrases[core];
    else {
      const status = Object.keys(statuses).find(prefix => core.startsWith(prefix + " "));
      if (status && /^(?:不足 0\.1|[\d,.]+)(?:\s*(?:g|kcal|千卡))?$/.test(core.slice(status.length + 1))) {
        result = statuses[status] + " " + core.slice(status.length + 1).replace("不足 0.1", "less than 0.1").replace("千卡", "kcal");
      } else if (/^\d+ 餐(?: · (?:演示|网页模拟))?$/.test(core)) {
        result = core.replace(/^(\d+) 餐/, (_, count) => `${count} ${count === "1" ? "meal" : "meals"}`).replace("演示", "Demo").replace("网页模拟", "Web demo");
      } else if (/^\d+ 天$/.test(core)) {
        result = core.replace(/^(\d+) 天$/, (_, count) => `${count} ${count === "1" ? "day" : "days"}`);
      } else if (/^\d+ 天无记录；缺口不按 0 计算。$/.test(core)) {
        result = core.replace(/^(\d+) 天无记录；缺口不按 0 计算。$/, (_, count) => `${count} ${count === "1" ? "day has" : "days have"} no record; gaps are not zero.`);
      } else if (/^\d{4} 年 \d{1,2} 月$/.test(core)) {
        result = core.replace(/^(\d{4}) 年 (\d{1,2}) 月$/, (_, year, month) => Number(month) >= 1 && Number(month) <= 12 ? `${monthNames[Number(month) - 1]} ${year}` : core);
      } else if (/^\d{1,2} 月 \d{1,2} 日(?:，星期[一二三四五六日天])?(?: · 演示日期)?$/.test(core)) {
        result = core.replace(/^(\d{1,2}) 月 (\d{1,2}) 日(?:，星期([一二三四五六日天]))?( · 演示日期)?$/, (_, month, day, weekday, demo) => {
          if (Number(month) < 1 || Number(month) > 12) return core;
          return `${weekday ? weekdays[weekday] + ", " : ""}${Number(day)} ${shortMonths[Number(month) - 1]}${demo ? " · Demo date" : ""}`;
        });
      } else if (/^\d{4}-\d{2}-\d{2}，.+$/.test(core)) {
        result = core.replace(/^(\d{4})-(\d{2})-(\d{2})，(.+)$/, (_, year, month, day, details) => {
          if (Number(month) < 1 || Number(month) > 12) return core;
          return `${Number(day)} ${shortMonths[Number(month) - 1]} ${year}, ${translate(details, language)}`;
        });
      } else if (/^已记录 [\d,.]+ 千卡，.+$/.test(core)) {
        result = core.replace(/^已记录 ([\d,.]+) 千卡，(.+)$/, (_, value, details) => `Logged ${value} kcal, ${translate(details.replace(/千卡$/, " kcal"), language)}`);
      } else if (/^[\d,.]+ 千卡，.+$/.test(core)) {
        result = core.replace(/^([\d,.]+) 千卡，(.+)$/, (_, value, details) => `${value} kcal, ${translate(details, language)}`);
      } else if (/^(蛋白质 [\d,.]+ g · 碳水 [\d,.]+ g · 脂肪 [\d,.]+ g)$/.test(core)) {
        result = core.replace("蛋白质", "Protein").replace("碳水", "Carbs").replace("脂肪", "Fat");
      } else if (core.includes(" · ")) {
        result = core.split(" · ").map(part => translate(part, language)).join(" · ");
      } else if (/ ›$/.test(core)) {
        result = translate(core.slice(0, -2), language) + " ›";
      } else if (core.endsWith("十六进制值")) {
        result = translate(core.slice(0, -"十六进制值".length), language) + " hex value";
      } else if (core.includes("：")) {
        const index = core.indexOf("：");
        const label = core.slice(0, index), detail = core.slice(index + 1);
        result = Object.hasOwn(phrases, label) ? `${translate(label, language)}: ${translate(detail, language)}` : core;
      } else result = core;
    }
    return leading + result + trailing;
  }

  function translatedSource(current, records, key, language) {
    let record = records.get(key);
    // New render text becomes the source. Repeated translation never translates its own output.
    if (!record || current !== record.last) record = { source: current, last: current };
    const next = translate(record.source, language);
    record.last = next; records.set(key, record);
    return next;
  }

  function translateDOM(root, language = "zh") {
    if (!root) return;
    function visit(node) {
      if (node.nodeType === 3) {
        const next = translatedSource(node.nodeValue || "", textSources, node, language);
        if (node.nodeValue !== next) node.nodeValue = next;
        return;
      }
      if (![1, 9, 11].includes(node.nodeType)) return;
      if (node.nodeType === 1) {
        const tag = String(node.tagName || "").toLowerCase();
        if (["script", "style", "textarea", "code", "pre"].includes(tag) || node.hasAttribute?.("data-i18n-skip") || node.hasAttribute?.("data-user-content")) return;
        let records = attributeSources.get(node);
        if (!records) { records = new Map(); attributeSources.set(node, records); }
        for (const attribute of ["aria-label", "aria-valuetext", "title", "placeholder"]) {
          if (!node.hasAttribute?.(attribute)) continue;
          const current = node.getAttribute(attribute);
          const next = translatedSource(current, records, attribute, language);
          if (current !== next) node.setAttribute(attribute, next);
        }
        // Do not touch input values or serialized data attributes. Placeholders above are UI, not data.
        if (tag === "input") return;
      }
      for (const child of node.childNodes || []) visit(child);
    }
    visit(root);
  }

  const api = Object.freeze({ translate, translateDOM });
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.ShiHengI18n = api;
})();

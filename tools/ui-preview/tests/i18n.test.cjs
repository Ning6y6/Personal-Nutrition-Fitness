const { test } = require("node:test");
const assert = require("node:assert/strict");
const { translate, translateDOM } = require("../static/i18n.js");

test("core navigation and future motion labels have both language states", () => {
  for (const [source, expected] of [["今日", "Today"], ["扫描", "Scan"], ["趋势", "Trends"], ["设置", "Settings"], ["记录一餐", "Log a meal"], ["减少动态效果", "Reduce motion"], ["减少透明度", "Reduce transparency"], ["语言", "Language"], ["不奖励少吃，只鼓励坚持记录。", "Consistency counts, not eating less."]]) {
    assert.equal(translate(source, "en"), expected);
    assert.equal(translate(source, "en-GB"), expected);
    assert.equal(translate(source, "zh-CN"), source);
  }
});
test("budget maximum and minimum nutrition semantics remain distinct in English", () => {
  assert.equal(translate("距离最低目标还差 40 g", "en"), "To minimum goal: 40 g");
  assert.equal(translate("预算剩余 2,000 kcal", "en"), "Budget remaining 2,000 kcal");
  assert.equal(translate("接近预算，还余 160 kcal", "en"), "Near budget; remaining 160 kcal");
  assert.equal(translate("超出上限 不足 0.1 g", "en"), "Over the limit by less than 0.1 g");
  assert.equal(translate("已达预算，尚未超出", "en"), "Budget reached, not over");
  assert.equal(translate("最低目标已达到", "en"), "Minimum goal reached");
});
test("dynamic counters, macros and dates are localized without modifying numeric values", () => {
  assert.equal(translate("1 餐 · 演示", "en"), "1 meal · Demo");
  assert.equal(translate("3 餐 · 演示", "en"), "3 meals · Demo");
  assert.equal(translate("1 天", "en"), "1 day");
  assert.equal(translate("3 天", "en"), "3 days");
  assert.equal(translate("1 天无记录；缺口不按 0 计算。", "en"), "1 day has no record; gaps are not zero.");
  assert.equal(translate("2 天无记录；缺口不按 0 计算。", "en"), "2 days have no record; gaps are not zero.");
  assert.equal(translate("蛋白质 35 g · 碳水 56 g · 脂肪 21 g", "en"), "Protein 35 g · Carbs 56 g · Fat 21 g");
  assert.equal(translate("2026 年 10 月", "en"), "October 2026");
  assert.equal(translate("10 月 7 日，星期三 · 演示日期", "en"), "Wednesday, 7 Oct · Demo date");
  assert.equal(translate("10 月 07 日", "en"), "7 Oct");
  assert.equal(translate("2026-10-07，1,420 千卡，未确认完整", "en"), "7 Oct 2026, 1,420 kcal, Completeness unconfirmed");
  assert.equal(translate("7 Oct 2026", "en"), "7 Oct 2026");
  assert.equal(translate("2026 年 99 月", "en"), "2026 年 99 月");
});
test("dynamic accessible nutrition label and design picker label localize", () => {
  assert.equal(translate("已记录 1,420 千卡，预算剩余 580千卡", "en"), "Logged 1,420 kcal, Budget remaining 580 kcal");
  assert.equal(translate("蛋白质：距离最低目标还差 40 g", "en"), "Protein: To minimum goal: 40 g");
  assert.equal(translate("进度绿色十六进制值", "en"), "Progress green hex value");
  assert.equal(translate("浅色 ›", "en"), "Light ›");
});
test("whitespace and unknown user strings remain intact", () => {
  assert.equal(translate("  今日\n", "en"), "  Today\n");
  assert.equal(translate("我的家常晚饭 <script>", "en"), "我的家常晚饭 <script>");
  assert.equal(translate("  ", "en"), "  ");
  assert.equal(translate("今日", "invalid"), "今日");
});
test("new inline details, morph panel, motion and trend prose is localized", () => {
  for (const [source, expected] of [
    ["截至昨天；今天还可以接上 · 演示", "Through yesterday; you can continue today · Demo"],
    ["跟随系统减少动态效果；也可以在这里开启。", "Follows your system's reduced-motion setting. You can also enable it here."],
    ["虚构示意，不是原餐真实配方。", "Fictional illustration, not the original meal's actual recipe."],
    ["点击行标题收起", "Tap the row title to collapse"],
    ["图、文字和标签分阶段展开", "Illustration, details and tags appear in stages"],
    ["按你实际吃的量记录", "Log the amount you actually ate"],
    ["调整每日热量预算", "Adjust daily energy budget"],
    ["未保存的输入", "Unsaved changes"],
    ["图表支持左右滑动或方向键选择日期。", "Swipe sideways or use the arrow keys to select a day."]
  ]) assert.equal(translate(source, "en"), expected);
});

class TextNode { constructor(value) { this.nodeType = 3; this.nodeValue = value; } }
class Element {
  constructor(tag, children = [], attributes = {}) { this.nodeType = 1; this.tagName = tag.toUpperCase(); this.childNodes = children; this.attributes = { ...attributes }; }
  hasAttribute(name) { return Object.hasOwn(this.attributes, name); }
  getAttribute(name) { return this.attributes[name]; }
  setAttribute(name, value) { this.attributes[name] = value; }
}
test("DOM translation is reversible and idempotent for text and accessibility attributes", () => {
  const label = new TextNode("今日");
  const root = new Element("button", [label], { "aria-label": "调整演示目标", title: "今日预算" });
  translateDOM(root, "en");
  assert.equal(label.nodeValue, "Today"); assert.equal(root.getAttribute("aria-label"), "Adjust demo targets");
  translateDOM(root, "en"); assert.equal(label.nodeValue, "Today");
  translateDOM(root, "zh"); assert.equal(label.nodeValue, "今日"); assert.equal(root.getAttribute("aria-label"), "调整演示目标");
  translateDOM(root, "en"); assert.equal(label.nodeValue, "Today");
});
test("new render text and attributes replace the source, then restore to the new source", () => {
  const label = new TextNode("预算剩余 580 kcal"); const root = new Element("p", [label], { "aria-label": "今日预算" });
  translateDOM(root, "en");
  label.nodeValue = "超出预算 120 kcal"; root.setAttribute("aria-label", "记录一餐");
  translateDOM(root, "en"); assert.equal(label.nodeValue, "Over budget by 120 kcal"); assert.equal(root.getAttribute("aria-label"), "Log a meal");
  translateDOM(root, "zh"); assert.equal(label.nodeValue, "超出预算 120 kcal"); assert.equal(root.getAttribute("aria-label"), "记录一餐");
});
test("DOM translation never edits form values, scripts, styles, serialized data or user content", () => {
  const input = new Element("input", [], { placeholder: "例如 350", value: "午餐", "data-config": '{"餐名":"午餐"}' });
  const source = new TextNode("今日"), user = new TextNode("牛肉青椒饭");
  const root = new Element("div", [input, new Element("script", [source]), new Element("p", [user], { "data-user-content": "" })]);
  translateDOM(root, "en");
  assert.equal(input.getAttribute("placeholder"), "e.g. 350"); assert.equal(input.getAttribute("value"), "午餐");
  assert.equal(input.getAttribute("data-config"), '{"餐名":"午餐"}'); assert.equal(source.nodeValue, "今日"); assert.equal(user.nodeValue, "牛肉青椒饭");
  translateDOM(root, "zh"); assert.equal(input.getAttribute("placeholder"), "例如 350");
});

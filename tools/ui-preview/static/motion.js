/* Shared prototype choreography; no iOS or nutrition policy dependencies. */
(() => {
  "use strict";
  const TOKENS = Object.freeze({ duration: 480, fade: 180, stagger: 1000 / 60 * 4, easing: "cubic-bezier(.22,1,.36,1)" });
  function frame(rect, radius) {
    return { left: `${rect.left}px`, top: `${rect.top}px`, width: `${rect.width}px`, height: `${rect.height}px`, borderRadius: `${radius}px` };
  }
  function morphFrames(origin, destination, radius = 26) { return [frame(origin, origin.width / 2), frame(destination, radius)]; }
  function digitOffsets(from, to) {
    if (![from, to].every(value => Number.isInteger(value) && value >= 0 && value <= 9)) throw new RangeError("Digits must be 0...9");
    return { from, to: to < from ? to + 10 : to };
  }
  function animateCounter(element, next, previous = next, reduced = false, locale = "zh-CN") {
    if (!element || !Number.isFinite(next)) return;
    const value = Math.max(0, Math.round(next)), old = Math.max(0, Math.round(previous));
    const formatter = new Intl.NumberFormat(locale);
    element.setAttribute("aria-label", formatter.format(value));
    if (reduced || !element.animate) { element.textContent = formatter.format(value); return; }
    const text = formatter.format(value), digits = String(old).padStart(String(value).length, "0").slice(-String(value).length);
    element.replaceChildren(); element.classList.add("counter-digits");
    let index = 0;
    for (const character of text) {
      const column = document.createElement("span"); column.setAttribute("aria-hidden", "true");
      if (!/\d/.test(character)) { column.textContent = character; element.append(column); continue; }
      column.className = "counter-column";
      const strip = document.createElement("span"); strip.className = "counter-strip";
      for (let digit = 0; digit < 20; digit++) { const row = document.createElement("span"); row.textContent = String(digit % 10); strip.append(row); }
      column.append(strip); element.append(column);
      const offsets = digitOffsets(Number(digits[index++]), Number(character));
      strip.style.transform = `translateY(-${offsets.to * 1.16}em)`;
      strip.animate([{ transform: `translateY(-${offsets.from * 1.16}em)` }, { transform: `translateY(-${offsets.to * 1.16}em)` }], { duration: TOKENS.duration, easing: TOKENS.easing });
    }
  }
  const api = { TOKENS, morphFrames, digitOffsets, animateCounter };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.ShiHengMotion = api;
})();

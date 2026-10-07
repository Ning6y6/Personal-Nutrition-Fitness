const { test } = require("node:test");
const assert = require("node:assert/strict");
const { TOKENS, morphFrames, digitOffsets } = require("../static/motion.js");
test("one 480 ms curve and four-frame stagger", () => {
  assert.equal(TOKENS.duration, 480); assert.equal(TOKENS.easing, "cubic-bezier(.22,1,.36,1)");
  assert.ok(Math.abs(TOKENS.stagger - 66.6667) < .001);
});
test("same frame pair supports forward and reversed container morph", () => {
  const frames = morphFrames({ left: 250, top: 600, width: 58, height: 58 }, { left: 12, top: 80, width: 306, height: 578 });
  assert.deepEqual(frames[0], { left: "250px", top: "600px", width: "58px", height: "58px", borderRadius: "29px" });
  assert.equal(frames[1].borderRadius, "26px"); assert.equal(frames[1].height, "578px");
  assert.deepEqual([...frames].reverse().reverse(), frames);
});
test("odometer rolls adjacent digits without negative wrapping", () => {
  assert.deepEqual(digitOffsets(8, 2), { from: 8, to: 12 });
  assert.deepEqual(digitOffsets(2, 8), { from: 2, to: 8 });
  for (const args of [[-1, 2], [0, 10], [1.5, 2]]) assert.throws(() => digitOffsets(...args), RangeError);
});

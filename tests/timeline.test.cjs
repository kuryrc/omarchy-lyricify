const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const T = vm.createContext({});
vm.runInContext(fs.readFileSync('core/Timeline.js', 'utf8'), T);
const fixture = JSON.parse(fs.readFileSync('fixtures/demo.json', 'utf8'));

test('fixture is a consistent, bounded timeline', () => assert.equal(T.validate(fixture), true));
test('line lookup respects start, end, gaps and backward seeks', () => {
  for (const [position, expected] of [[0,-1],[1000,0],[6499,0],[6500,-1],[7000,1],[34000,-1],[13000,2],[1000,0]])
    assert.equal(T.activeIndex(fixture.lines, position), expected);
});
test('word highlights pause through real gaps and reset on seek', () => {
  const words = [{startMs:1000,endMs:1500},{startMs:2000,endMs:3000}];
  assert.equal(T.highlightWidth(words,[],2500),0);
  for (const [position, expected] of [[0,0],[1000,0],[1250,25],[1700,50],[2500,100],[3000,150],[1100,10]])
    assert.equal(T.highlightWidth(words,[50,150],position), expected);
});
test('short breaths hold finished text, while intros and long gaps show track information', () => {
  assert.equal(T.activeIndex(fixture.lines,6600),-1);
  assert.equal(T.displayIndex(fixture.lines,6600),0);
  assert.equal(T.displayIndex(fixture.lines,0),-1);
  assert.equal(T.displayIndex(fixture.lines,33900),-1);
  assert.equal(T.displayIndex([{startMs:0,endMs:1000},{startMs:4000,endMs:5000}],2000),-1);
});
test('plain lines do not acquire invented word timestamps', () => {
  assert.equal(fixture.lines[3].words.length, 0);
  assert.equal(T.scrollTarget(600,300,0,0,5000,false), 0);
  assert.equal(T.scrollTarget(600,300,0,5000,5000,false), 300);
});
test('long-line viewport stays bounded at both ends', () => {
  assert.equal(T.scrollTarget(200,300,150,0,5000,true), 0);
  assert.equal(T.scrollTarget(900,300,900,0,5000,true), 600);
  assert.equal(T.scrollTarget(900,300,10,0,5000,true), 0);
});
test('viewport following is frame-rate independent', () => {
  const half = T.approach(T.approach(0,100,1/120,9),100,1/120,9);
  assert.ok(Math.abs(half - T.approach(0,100,1/60,9)) < 1e-9);
});
test('placement keeps the island inside screen bounds', () => {
  for (const screen of [640,1280,2560]) for (const offset of [-3000,0,430,3000]) {
    const p=T.placement(screen,520,offset);
    assert.ok(p.x >=16 && p.x+p.width<=screen-16);
  }
});
test('center snap has a release band and clamps dragged positions to the screen', () => {
  for (const offset of [-16,0,16]) assert.equal(T.dragPlacement(2560,520,offset,false).offset,0);
  assert.equal(T.dragPlacement(2560,520,20,false).offset,20);
  assert.equal(T.dragPlacement(2560,520,28,true).offset,0);
  assert.equal(T.dragPlacement(2560,520,29,true).offset,29);
  assert.equal(T.dragPlacement(2560,520,-29,true).offset,-29);
  assert.equal(T.dragPlacement(2560,520,99999,false).offset,1004);
  assert.equal(T.dragPlacement(2560,520,-99999,false).offset,-1004);
});
test('invalid and overlapping time data is rejected', () => {
  const copy=structuredClone(fixture); copy.lines[1].startMs=4000;
  assert.equal(T.validate(copy), false);
  const broken=structuredClone(fixture); broken.lines[0].words[0].text='wrong';
  assert.equal(T.validate(broken), false);
});
test('frame statistics have bounded buckets and label their scope', () => {
  const s=T.newStats(); s.warmup=0;
  for(let i=0;i<99;i++) T.sample(s,1000/60,60);
  T.sample(s,60,60);
  const report=T.statsReport(s);
  assert.equal(report.samples,100); assert.equal(report.p95Ms,16.7);
  assert.equal(report.maxMs,60); assert.equal(report.overBudget,1);
  assert.equal(report.kind,'qt-animation-callback');
});

const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const labels = vm.createContext({});
vm.runInContext(fs.readFileSync('core/I18n.js', 'utf8'), labels);

test('lyric errors explain parse, timeout and rate-limit failures in both languages', () => {
  for (const [code, english, chinese] of [
    ['invalid_lyrics', /parsed/, /解析/],
    ['timeout', /timed out/, /超时/],
    ['rate_limited', /rate-limiting/, /请求受限/],
  ]) {
    assert.match(labels.lyricStatus('en', 'error', code), english);
    assert.match(labels.lyricStatus('zh_CN', 'error', code), chinese);
  }
});
test('stale error details cannot replace loading or ready status', () => {
  for (const status of ['loading', 'ready', 'disabled']) {
    assert.equal(labels.lyricStatus('en', status, 'invalid_lyrics'), labels.status('en', status));
  }
});
test('unknown lyric errors use a general explanation without exposing raw values', () => {
  assert.equal(labels.lyricStatus('en', 'error', 'original-unknown-fixture'), labels.status('en', 'error'));
});

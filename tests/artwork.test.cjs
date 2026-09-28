const {test} = require('node:test');
const assert = require('node:assert/strict');
const {source} = require('../core/Artwork.js');
test('remote cover opt-in is independent; local images stay available', () => {
  assert.equal(source('https://example.invalid/cover.png', false), '');
  assert.equal(source('https://example.invalid/cover.png', true), 'https://example.invalid/cover.png');
  assert.equal(source('file:///tmp/original.png', false), 'file:///tmp/original.png');
  for (const url of ['http://example.invalid/cover', 'data:image/svg+xml,big', 'javascript:invalid', null])
    assert.equal(source(url, true), '');
});

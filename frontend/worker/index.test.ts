import assert from 'node:assert/strict'
import test from 'node:test'
import { positiveLimit } from './index.ts'

test('API limits reject bad values and cap large requests', () => {
  assert.equal(positiveLimit(null), 50)
  assert.equal(positiveLimit('-1'), 50)
  assert.equal(positiveLimit('12'), 12)
  assert.equal(positiveLimit('999'), 100)
})

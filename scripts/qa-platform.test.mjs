import test from 'node:test'
import assert from 'node:assert/strict'

import { shouldRunLinuxOnlyQa } from './qa-platform.mjs'

test('shouldRunLinuxOnlyQa returns true on linux', () => {
  assert.equal(shouldRunLinuxOnlyQa('linux'), true)
})

test('shouldRunLinuxOnlyQa returns false on non-linux platforms', () => {
  assert.equal(shouldRunLinuxOnlyQa('win32'), false)
  assert.equal(shouldRunLinuxOnlyQa('darwin'), false)
})

import { describe, expect, it } from 'vitest'

import {
  parseArgs,
  parseConsoleDurations,
  parseNUnitDurations,
  stripAnsi,
} from './pester-duration-report.mjs'

describe('pester duration report', () => {
  it('解析 lane、artifact 和 Top N 参数', () => {
    expect(
      parseArgs([
        '--command',
        'pnpm test:pwsh:all',
        '--nunit',
        'host.xml',
        '--json',
        'duration.json',
        '--lane',
        'host',
        '--top',
        '5',
      ]),
    ).toEqual({
      filePath: null,
      command: 'pnpm test:pwsh:all',
      nunitPath: 'host.xml',
      jsonPath: 'duration.json',
      lane: 'host',
      top: 5,
    })
  })

  it('移除 ANSI 并区分 host 与 linux 文件耗时', () => {
    const parsed = parseConsoleDurations(
      '\u001b[32m[host] [+] C:\\repo\\tests\\A.Tests.ps1 2.5s (2 tests)\u001b[0m\n' +
        '[linux] [+] /repo/tests/B.Tests.ps1 750ms (1 test)\n' +
        'Discovery found 12 tests in 1.2s\nTests completed in 3.4s\n' +
        'Code Coverage result processed in 500ms',
    )

    expect(stripAnsi('\u001b[31mfailed\u001b[0m')).toBe('failed')
    expect(
      parsed.files.map(({ lane, durationMs }) => ({ lane, durationMs })),
    ).toEqual([
      { lane: 'host', durationMs: 2500 },
      { lane: 'linux', durationMs: 750 },
    ])
    expect(parsed.phases).toEqual({
      discoveryMs: 1200,
      runMs: 3400,
      coverageMs: 500,
    })
  })

  it('从 NUnit3 提取文件和 test-case Top N', () => {
    const parsed = parseNUnitDurations(
      '<test-run>' +
        '<test-suite type="Assembly" fullname="C:&amp;\\A.Tests.ps1" duration="4.2" result="Failed">' +
        '<test-case fullname="suite.fast" classname="suite" duration="0.1" result="Passed" />' +
        '<test-case fullname="suite.slow" classname="suite" duration="3.5" result="Failed" />' +
        '</test-suite></test-run>',
      'host',
    )

    expect(parsed.files[0]).toMatchObject({
      lane: 'host',
      path: 'C:&\\A.Tests.ps1',
      durationMs: 4200,
      result: 'Failed',
    })
    expect(parsed.testCases.map((testCase) => testCase.name)).toEqual([
      'suite.slow',
      'suite.fast',
    ])
  })

  it('无耗时行时返回空集合而不抛错', () => {
    expect(
      parseConsoleDurations('command failed before Pester started'),
    ).toEqual({
      files: [],
      phases: { discoveryMs: null, runMs: null, coverageMs: null },
    })
  })
})

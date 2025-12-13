import * as path from 'node:path'
import { describe, expect, it } from 'vitest'
import { JsonComparator } from '../src/comparator'
import { OutputFormatter } from '../src/formatter'
import { FileParser } from '../src/parser'
import { DiffType, OutputFormat } from '../src/types'

describe('CLI 集成行为（模块拼接模拟）', () => {
  const dataDir = path.join(__dirname, 'data')
  const file1 = path.join(dataDir, 'test1.json')
  const file2 = path.join(dataDir, 'test2.json')

  it('默认不显示 UNCHANGED，显示统计信息', async () => {
    const parser = new FileParser()
    const [a, b] = await Promise.all([
      parser.parseFile(file1),
      parser.parseFile(file2),
    ])
    const comparator = new JsonComparator({ maxDepth: 10 })
    const diffs = comparator.compare([a, b])

    const filtered = diffs.filter((d) => d.type !== DiffType.UNCHANGED)
    const formatter = new OutputFormatter(false)
    const out = formatter.format(
      filtered,
      OutputFormat.TABLE,
      [file1, file2],
      true,
    )

    expect(out).toContain('Summary:')
    expect(out).not.toContain('UNCHANGED')
  })

  it('JSON 输出包含 files 与 summary（不含 total 字段）', async () => {
    const parser = new FileParser()
    const [a, b] = await Promise.all([
      parser.parseFile(file1),
      parser.parseFile(file2),
    ])
    const comparator = new JsonComparator({ maxDepth: 10 })
    const diffs = comparator.compare([a, b])

    const formatter = new OutputFormatter(false)
    const out = formatter.format(diffs, OutputFormat.JSON, [file1, file2], true)
    const parsed = JSON.parse(out)

    expect(parsed.files).toEqual([file1, file2])
    expect(parsed).toHaveProperty('differences')
    expect(parsed).toHaveProperty('summary')
    expect(parsed.summary).not.toHaveProperty('total')
    expect(parsed.summary).toHaveProperty('added')
    expect(parsed.summary).toHaveProperty('removed')
    expect(parsed.summary).toHaveProperty('modified')
    expect(parsed.summary).toHaveProperty('unchanged')
  })

  it('忽略数组顺序时能正确处理重复元素', async () => {
    const a = { list: [1, 1, 2, 3] }
    const b = { list: [1, 2, 2, 3] }
    const comparator = new JsonComparator({ ignoreArrayOrder: true })
    const diffs = comparator.compare([a, b])

    const removed = diffs.filter((d) => d.type === DiffType.REMOVED)
    const added = diffs.filter((d) => d.type === DiffType.ADDED)

    expect(removed.length).toBe(1)
    expect(added.length).toBe(1)
  })
})

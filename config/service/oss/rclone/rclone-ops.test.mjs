import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import {
  buildRemoteDefinitions,
  listRemoteNames,
  parseArgs,
  renderRcloneConfig,
  resolveEnvPlaceholders,
  resolveOptionWithConfig,
} from './rclone-ops.mjs'

describe('rclone-ops JSON 配置生成逻辑', () => {
  it('能从 JSON remotes 数组生成任意 remote', () => {
    const remotes = buildRemoteDefinitions({
      remotes: [
        {
          name: 'cloud-main',
          type: 's3',
          provider: 'Other',
          access_key_id: 'main-id',
          secret_access_key: 'main-secret',
          endpoint: 'https://s3.example.com',
        },
        {
          name: 'archive',
          type: 's3',
          provider: 'Other',
          access_key_id: 'archive-id',
          secret_access_key: 'archive-secret',
          endpoint: 'http://127.0.0.1:9000',
          force_path_style: 'true',
        },
      ],
    })

    assert.deepEqual(
      remotes.map((remote) => remote.name),
      ['cloud-main', 'archive'],
    )
    assert.equal(remotes[0].provider, 'Other')
    assert.equal(remotes[1].force_path_style, 'true')
  })

  it('能替换 JSON 字符串中的环境变量占位符', () => {
    process.env.CLOUD_MAIN_ACCESS_KEY_ID = 'env-main-id'

    assert.equal(
      resolveEnvPlaceholders(
        '${CLOUD_MAIN_ACCESS_KEY_ID}',
        'remotes[0].access_key_id',
      ),
      'env-main-id',
    )
  })

  it('缺少环境变量占位符时抛出清晰错误', () => {
    delete process.env.CLOUD_MAIN_ACCESS_KEY_ID

    assert.throws(
      () =>
        resolveEnvPlaceholders(
          '${CLOUD_MAIN_ACCESS_KEY_ID}',
          'remotes[0].access_key_id',
        ),
      /环境变量未设置: CLOUD_MAIN_ACCESS_KEY_ID/,
    )
  })

  it('拒绝旧平铺配置格式', () => {
    assert.throws(
      () =>
        buildRemoteDefinitions({
          RCLONE_REMOTE_NAMES: 'cloud-main',
          RCLONE_REMOTE_CLOUD_MAIN_TYPE: 's3',
        }),
      /旧平铺格式已不支持/,
    )
  })

  it('拒绝缺少 remotes 数组的 JSON 配置', () => {
    assert.throws(() => buildRemoteDefinitions({}), /配置缺少 remotes 数组/)
  })


  it('能从 JSON webui section 读取 RC 密码', () => {
    process.env.RCLONE_RC_PASS = 'json-rc-pass'

    assert.equal(
      resolveOptionWithConfig(
        new Map(),
        'pass',
        'UNUSED_RCLONE_RC_PASS',
        { webui: { pass: '${RCLONE_RC_PASS}' } },
        'webui',
        'pass',
        '',
      ),
      'json-rc-pass',
    )
  })

  it('能渲染并重新读取 remote 名称', () => {
    const config = renderRcloneConfig([
      { name: 'cloud-main', type: 's3', provider: 'Other' },
      { name: 'archive', type: 's3', provider: 'Other' },
    ])

    assert.deepEqual(listRemoteNames(config), ['cloud-main', 'archive'])
  })

  it('能解析透传参数与布尔 flag', () => {
    const parsed = parseArgs(['sync', 'a', 'b', '--run', '--', '--progress'])

    assert.equal(parsed.command, 'sync')
    assert.deepEqual(parsed.positional, ['a', 'b'])
    assert.equal(parsed.flags.get('run'), true)
    assert.deepEqual(parsed.passthrough, ['--progress'])
  })
})

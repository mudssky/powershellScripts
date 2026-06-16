import type { Diagnostic, LaunchPlan, OutputFormat } from './types.js'

/**
 * 格式化计划输出。
 *
 * @param plan 启动计划。
 * @param format 输出格式。
 * @returns 输出文本。
 */
export function formatPlan(plan: LaunchPlan, format: OutputFormat): string {
  if (format === 'json') {
    return JSON.stringify(plan, null, 2)
  }

  const lines = [
    `Project: ${plan.projectRoot}`,
    `Session: ${plan.session}`,
    `Attach: ${plan.attachCommand}`,
    '',
    'Services:',
  ]

  if (plan.services.length === 0) {
    lines.push('  (none selected)')
  } else {
    for (const service of plan.services) {
      lines.push(
        `  - ${service.name} [${service.source}] ${service.displayCommand}`,
      )
      if (service.ports.length > 0) {
        lines.push(`    ports: ${service.ports.join(', ')}`)
      }
      if (service.prepare.length > 0) {
        lines.push(`    prepare: ${service.prepare.join(' && ')}`)
      }
      if (Object.keys(service.displayEnv).length > 0) {
        lines.push(`    env: ${JSON.stringify(service.displayEnv)}`)
      }
    }
  }

  if (plan.ignored.length > 0) {
    lines.push('', 'Ignored/unknown modules:')
    for (const ignored of plan.ignored) {
      lines.push(`  - ${ignored.name}: ${ignored.reason}`)
    }
  }

  if (plan.diagnostics.length > 0) {
    lines.push('', 'Diagnostics:')
    lines.push(
      ...formatDiagnostics(plan.diagnostics).map((line) => `  ${line}`),
    )
  }

  return lines.join('\n')
}

/**
 * 格式化诊断列表。
 *
 * @param diagnostics 诊断列表。
 * @returns 文本行。
 */
export function formatDiagnostics(diagnostics: Diagnostic[]): string[] {
  return diagnostics.map((diagnostic) => {
    const target = diagnostic.target ? ` [${diagnostic.target}]` : ''
    const detail = diagnostic.detail ? `: ${diagnostic.detail.trim()}` : ''
    return `${diagnostic.level.toUpperCase()} ${diagnostic.code}${target} ${diagnostic.message}${detail}`
  })
}

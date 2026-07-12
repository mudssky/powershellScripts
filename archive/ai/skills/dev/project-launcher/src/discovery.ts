import { existsSync } from 'node:fs'
import { readdir, readFile } from 'node:fs/promises'
import { basename, join, relative, resolve } from 'node:path'
import { exists } from './config.js'
import type {
  DiscoveryResult,
  IgnoredModule,
  ProjectLauncherConfig,
  ProjectServiceConfig,
  ReloadMode,
  ServiceCandidate,
} from './types.js'

const LIBRARY_HINTS = [
  'common',
  'model',
  'models',
  'sdk',
  'client',
  'starter',
  'bom',
  'core',
  'domain',
  'shared',
  'lib',
  'libs',
]

/**
 * 发现项目中的可运行服务候选。
 *
 * @param projectRoot 项目根目录。
 * @param config 已加载配置。
 * @returns 服务候选和被忽略模块。
 */
export async function discoverProject(
  projectRoot: string,
  config: ProjectLauncherConfig = {},
): Promise<DiscoveryResult> {
  const servicesFromConfig = (config.services ?? []).map((service) =>
    serviceFromConfig(projectRoot, service),
  )
  const discovered = await discoverBuildServices(projectRoot, config)

  return {
    projectRoot,
    buildTool: discovered.buildTool,
    services: mergeServiceCandidates([
      ...servicesFromConfig,
      ...discovered.services,
    ]),
    ignored: discovered.ignored,
  }
}

/**
 * 把显式配置转换为启动候选。
 *
 * @param projectRoot 项目根目录。
 * @param service 显式服务配置。
 * @returns 服务候选。
 */
export function serviceFromConfig(
  projectRoot: string,
  service: ProjectServiceConfig,
): ServiceCandidate {
  const cwd = resolve(projectRoot, service.cwd ?? '.')
  const ports = normalizePorts(service)

  return {
    name: service.name,
    cwd,
    command: service.command,
    source: 'config',
    port: service.port ?? ports[0],
    ports,
    prepare: normalizePrepare(service.prepare),
    env: service.env ?? {},
    reload: service.reload ?? 'auto',
    reloadCommand: service.reloadCommand,
    allowParallelBuild: service.allowParallelBuild ?? false,
    confidence: 'high',
    reasons: ['显式配置服务'],
  }
}

/**
 * 创建一次性命令服务候选。
 *
 * @param projectRoot 项目根目录。
 * @param input 一次性命令参数。
 * @returns 服务候选。
 */
export function serviceFromCommand(
  projectRoot: string,
  input: { name: string; command: string; port?: number; reload?: ReloadMode },
): ServiceCandidate {
  return {
    name: input.name,
    cwd: projectRoot,
    command: input.command,
    source: 'command',
    port: input.port,
    ports: input.port ? [input.port] : [],
    prepare: [],
    env: {},
    reload: input.reload ?? 'auto',
    allowParallelBuild: false,
    confidence: 'high',
    reasons: ['CLI 一次性命令'],
  }
}

/**
 * 根据构建文件发现服务。
 *
 * @param projectRoot 项目根目录。
 * @param config 已加载配置。
 * @returns 构建工具、服务候选和被忽略模块。
 */
async function discoverBuildServices(
  projectRoot: string,
  config: ProjectLauncherConfig,
): Promise<Pick<DiscoveryResult, 'buildTool' | 'services' | 'ignored'>> {
  if (await exists(join(projectRoot, 'pom.xml'))) {
    return discoverMavenServices(projectRoot, config)
  }

  if (
    (await exists(join(projectRoot, 'build.gradle'))) ||
    (await exists(join(projectRoot, 'build.gradle.kts'))) ||
    (await exists(join(projectRoot, 'settings.gradle'))) ||
    (await exists(join(projectRoot, 'settings.gradle.kts')))
  ) {
    return discoverGradleServices(projectRoot, config)
  }

  return { services: [], ignored: [] }
}

/**
 * 发现 Maven 服务模块。
 *
 * @param projectRoot 项目根目录。
 * @param config 已加载配置。
 * @returns Maven 服务候选。
 */
async function discoverMavenServices(
  projectRoot: string,
  config: ProjectLauncherConfig,
): Promise<Pick<DiscoveryResult, 'buildTool' | 'services' | 'ignored'>> {
  const rootPom = await readText(join(projectRoot, 'pom.xml'))
  const modules = parseMavenModules(rootPom)
  const targets =
    modules.length > 0
      ? modules.map((module) => resolve(projectRoot, module))
      : [projectRoot]
  const services: ServiceCandidate[] = []
  const ignored: IgnoredModule[] = []

  for (const target of targets) {
    const moduleName = basename(target)
    const pomPath = join(target, 'pom.xml')
    if (!(await exists(pomPath))) {
      ignored.push({
        name: moduleName,
        path: target,
        reason: '模块缺少 pom.xml',
      })
      continue
    }

    const pom = await readText(pomPath)
    const appMain = await findSpringBootMain(target)
    const hasSpringPlugin = /spring-boot-maven-plugin/.test(pom)
    const packaging = parsePomPackaging(pom)
    const isAggregator = packaging === 'pom'
    const libraryLike = isLibraryLike(moduleName)

    if (isAggregator || (libraryLike && !hasSpringPlugin && !appMain)) {
      ignored.push({
        name: moduleName,
        path: target,
        reason: isAggregator
          ? 'Maven aggregator/parent 模块'
          : '疑似 library 模块',
      })
      continue
    }

    if (hasSpringPlugin || appMain || modules.length === 0) {
      const moduleSelector = modules.length > 0 ? ` -pl ${moduleName}` : ''
      services.push({
        name: sanitizeServiceName(moduleName),
        cwd: projectRoot,
        command: `${mavenExecutable(projectRoot)} spring-boot:run${moduleSelector}`,
        source: 'maven',
        modulePath: target,
        ports: [],
        prepare: [
          `${mavenExecutable(projectRoot)}${moduleSelector} -am compile`.trim(),
        ],
        env: profileEnv(config),
        reload: config.defaults?.reload ?? 'auto',
        allowParallelBuild: config.defaults?.allowParallelBuild ?? false,
        confidence: hasSpringPlugin || appMain ? 'high' : 'medium',
        reasons: [
          hasSpringPlugin ? '存在 Spring Boot Maven 插件' : '单模块 Maven 项目',
          appMain ? '存在 @SpringBootApplication' : '',
        ].filter(Boolean),
      })
    } else {
      ignored.push({
        name: moduleName,
        path: target,
        reason: '未发现可运行 main 或 Spring Boot 插件',
      })
    }
  }

  return { buildTool: 'maven', services, ignored }
}

/**
 * 发现 Gradle 服务模块。
 *
 * @param projectRoot 项目根目录。
 * @param config 已加载配置。
 * @returns Gradle 服务候选。
 */
async function discoverGradleServices(
  projectRoot: string,
  config: ProjectLauncherConfig,
): Promise<Pick<DiscoveryResult, 'buildTool' | 'services' | 'ignored'>> {
  const settings =
    (await readOptionalText(join(projectRoot, 'settings.gradle'))) ??
    (await readOptionalText(join(projectRoot, 'settings.gradle.kts'))) ??
    ''
  const modules = parseGradleIncludes(settings)
  const targets =
    modules.length > 0
      ? modules.map((module) => resolve(projectRoot, module.replace(/:/g, '/')))
      : [projectRoot]
  const services: ServiceCandidate[] = []
  const ignored: IgnoredModule[] = []

  for (const target of targets) {
    const moduleName = basename(target)
    const buildPath =
      ((await exists(join(target, 'build.gradle'))) &&
        join(target, 'build.gradle')) ||
      ((await exists(join(target, 'build.gradle.kts'))) &&
        join(target, 'build.gradle.kts'))

    if (!buildPath) {
      ignored.push({
        name: moduleName,
        path: target,
        reason: '模块缺少 Gradle build 文件',
      })
      continue
    }

    const build = await readText(buildPath)
    const appMain = await findSpringBootMain(target)
    const hasBootRun = /org\.springframework\.boot|bootRun/.test(build)
    const hasRun = /application\b|mainClass|tasks\.run\b/.test(build)
    const libraryLike = isLibraryLike(moduleName)

    if (libraryLike && !hasBootRun && !hasRun && !appMain) {
      ignored.push({
        name: moduleName,
        path: target,
        reason: '疑似 library 模块',
      })
      continue
    }

    if (hasBootRun || hasRun || appMain || modules.length === 0) {
      const gradleTask =
        modules.length > 0
          ? `:${relative(projectRoot, target).replace(/\//g, ':')}:`
          : ''
      const taskName = hasBootRun || appMain ? 'bootRun' : 'run'
      services.push({
        name: sanitizeServiceName(moduleName),
        cwd: projectRoot,
        command:
          `${gradleExecutable(projectRoot)} ${gradleTask}${taskName}`.trim(),
        source: 'gradle',
        modulePath: target,
        ports: [],
        prepare: [
          `${gradleExecutable(projectRoot)} ${gradleTask}classes`.trim(),
        ],
        env: profileEnv(config),
        reload: config.defaults?.reload ?? 'auto',
        reloadCommand: undefined,
        allowParallelBuild: config.defaults?.allowParallelBuild ?? false,
        confidence: hasBootRun || hasRun || appMain ? 'high' : 'medium',
        reasons: [
          hasBootRun ? '存在 bootRun/Spring Boot 插件' : '',
          hasRun ? '存在 application/run 线索' : '',
          appMain ? '存在 @SpringBootApplication' : '',
        ].filter(Boolean),
      })
    } else {
      ignored.push({
        name: moduleName,
        path: target,
        reason: '未发现可运行 Gradle task',
      })
    }
  }

  return { buildTool: 'gradle', services, ignored }
}

/**
 * 解析 Maven modules。
 *
 * @param pom pom.xml 文本。
 * @returns 模块路径列表。
 */
export function parseMavenModules(pom: string): string[] {
  const modulesBlock = pom.match(/<modules>([\s\S]*?)<\/modules>/)
  if (!modulesBlock) {
    return []
  }

  return [...modulesBlock[1].matchAll(/<module>(.*?)<\/module>/g)]
    .map((match) => match[1].trim())
    .filter(Boolean)
}

/**
 * 解析 pom packaging。
 *
 * @param pom pom.xml 文本。
 * @returns packaging 值。
 */
export function parsePomPackaging(pom: string): string {
  return pom.match(/<packaging>(.*?)<\/packaging>/)?.[1]?.trim() ?? 'jar'
}

/**
 * 解析 Gradle include 声明。
 *
 * @param settings settings.gradle 文本。
 * @returns 子项目路径列表。
 */
export function parseGradleIncludes(settings: string): string[] {
  const modules: string[] = []
  for (const match of settings.matchAll(/include\s*\(?\s*([^\n)]+)/g)) {
    const segment = match[1]
    for (const entry of segment.matchAll(/['"](:?[\w.-][\w.:-]*)['"]/g)) {
      modules.push(entry[1].replace(/^:/, '').replace(/:/g, '/'))
    }
  }
  return [...new Set(modules)]
}

/**
 * 归一化服务名。
 *
 * @param name 原始名称。
 * @returns 适合 CLI 使用的名称。
 */
export function sanitizeServiceName(name: string): string {
  return name
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/[^A-Za-z0-9_.-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase()
}

/**
 * 判断模块名是否像库模块。
 *
 * @param name 模块名。
 * @returns 疑似库模块时为 true。
 */
export function isLibraryLike(name: string): boolean {
  const normalized = sanitizeServiceName(name)
  return LIBRARY_HINTS.some(
    (hint) => normalized === hint || normalized.endsWith(`-${hint}`),
  )
}

/**
 * 查找 Spring Boot main class 线索。
 *
 * @param moduleRoot 模块目录。
 * @returns 是否存在 Spring Boot main class。
 */
async function findSpringBootMain(moduleRoot: string): Promise<boolean> {
  const sourceRoot = join(moduleRoot, 'src', 'main')
  if (!(await exists(sourceRoot))) {
    return false
  }

  const files = await collectFiles(sourceRoot, 60)
  for (const file of files) {
    if (!/\.(java|kt)$/.test(file)) {
      continue
    }
    const content = await readText(file)
    if (
      content.includes('@SpringBootApplication') ||
      /public\s+static\s+void\s+main\s*\(/.test(content) ||
      /fun\s+main\s*\(/.test(content)
    ) {
      return true
    }
  }

  return false
}

/**
 * 收集目录下文件，带上限避免扫描过深。
 *
 * @param root 根目录。
 * @param limit 最大文件数量。
 * @returns 文件路径列表。
 */
async function collectFiles(root: string, limit: number): Promise<string[]> {
  const files: string[] = []
  const stack = [root]
  while (stack.length > 0 && files.length < limit) {
    const current = stack.pop()
    if (!current) {
      break
    }
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const path = join(current, entry.name)
      if (entry.isDirectory()) {
        stack.push(path)
      } else if (entry.isFile()) {
        files.push(path)
      }
      if (files.length >= limit) {
        break
      }
    }
  }
  return files
}

/**
 * 合并配置和发现候选，配置优先。
 *
 * @param candidates 候选列表。
 * @returns 去重后的候选。
 */
function mergeServiceCandidates(
  candidates: ServiceCandidate[],
): ServiceCandidate[] {
  const merged = new Map<string, ServiceCandidate>()
  for (const candidate of candidates) {
    if (!merged.has(candidate.name) || candidate.source === 'config') {
      merged.set(candidate.name, candidate)
    }
  }
  return [...merged.values()]
}

/**
 * 从配置构造 profile 环境。
 *
 * @param config 已加载配置。
 * @returns 环境变量。
 */
function profileEnv(config: ProjectLauncherConfig): Record<string, string> {
  const profile = config.defaults?.profile
  return profile ? { SPRING_PROFILES_ACTIVE: profile } : {}
}

/**
 * Maven 可执行命令，优先 wrapper。
 *
 * @param projectRoot 项目根目录。
 * @returns Maven 命令。
 */
function mavenExecutable(projectRoot: string): string {
  return existsSync(join(projectRoot, 'mvnw')) ? './mvnw' : 'mvn'
}

/**
 * Gradle 可执行命令，优先 wrapper。
 *
 * @param projectRoot 项目根目录。
 * @returns Gradle 命令。
 */
function gradleExecutable(projectRoot: string): string {
  return existsSync(join(projectRoot, 'gradlew')) ? './gradlew' : 'gradle'
}

/**
 * 读取文本文件。
 *
 * @param filePath 文件路径。
 * @returns 文件内容。
 */
async function readText(filePath: string): Promise<string> {
  return readFile(filePath, 'utf8')
}

/**
 * 尝试读取文本文件。
 *
 * @param filePath 文件路径。
 * @returns 文件内容或 undefined。
 */
async function readOptionalText(filePath: string): Promise<string | undefined> {
  try {
    return await readText(filePath)
  } catch {
    return undefined
  }
}

/**
 * 归一化端口配置。
 *
 * @param service 服务配置。
 * @returns 端口列表。
 */
function normalizePorts(service: ProjectServiceConfig): number[] {
  return [
    ...(typeof service.port === 'number' ? [service.port] : []),
    ...(service.ports ?? []),
  ].filter((value, index, array) => array.indexOf(value) === index)
}

/**
 * 归一化 prepare 配置。
 *
 * @param prepare prepare 字段。
 * @returns prepare 命令列表。
 */
function normalizePrepare(prepare?: string | string[]): string[] {
  if (!prepare) {
    return []
  }
  return Array.isArray(prepare) ? prepare : [prepare]
}

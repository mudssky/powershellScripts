#!/usr/bin/env node
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { basename, dirname, extname, join, resolve } from "node:path";
import { EventEmitter } from "events";
import { homedir } from "node:os";

//#region ../../../../node_modules/.pnpm/cac@6.7.14/node_modules/cac/dist/index.mjs
function toArr(any) {
	return any == null ? [] : Array.isArray(any) ? any : [any];
}
function toVal(out, key, val, opts) {
	var x, old = out[key], nxt = !!~opts.string.indexOf(key) ? val == null || val === true ? "" : String(val) : typeof val === "boolean" ? val : !!~opts.boolean.indexOf(key) ? val === "false" ? false : val === "true" || (out._.push((x = +val, x * 0 === 0) ? x : val), !!val) : (x = +val, x * 0 === 0) ? x : val;
	out[key] = old == null ? nxt : Array.isArray(old) ? old.concat(nxt) : [old, nxt];
}
function mri2(args, opts) {
	args = args || [];
	opts = opts || {};
	var k, arr, arg, name, val, out = { _: [] };
	var i = 0, j = 0, idx = 0, len = args.length;
	const alibi = opts.alias !== void 0;
	const strict = opts.unknown !== void 0;
	const defaults = opts.default !== void 0;
	opts.alias = opts.alias || {};
	opts.string = toArr(opts.string);
	opts.boolean = toArr(opts.boolean);
	if (alibi) for (k in opts.alias) {
		arr = opts.alias[k] = toArr(opts.alias[k]);
		for (i = 0; i < arr.length; i++) (opts.alias[arr[i]] = arr.concat(k)).splice(i, 1);
	}
	for (i = opts.boolean.length; i-- > 0;) {
		arr = opts.alias[opts.boolean[i]] || [];
		for (j = arr.length; j-- > 0;) opts.boolean.push(arr[j]);
	}
	for (i = opts.string.length; i-- > 0;) {
		arr = opts.alias[opts.string[i]] || [];
		for (j = arr.length; j-- > 0;) opts.string.push(arr[j]);
	}
	if (defaults) for (k in opts.default) {
		name = typeof opts.default[k];
		arr = opts.alias[k] = opts.alias[k] || [];
		if (opts[name] !== void 0) {
			opts[name].push(k);
			for (i = 0; i < arr.length; i++) opts[name].push(arr[i]);
		}
	}
	const keys = strict ? Object.keys(opts.alias) : [];
	for (i = 0; i < len; i++) {
		arg = args[i];
		if (arg === "--") {
			out._ = out._.concat(args.slice(++i));
			break;
		}
		for (j = 0; j < arg.length; j++) if (arg.charCodeAt(j) !== 45) break;
		if (j === 0) out._.push(arg);
		else if (arg.substring(j, j + 3) === "no-") {
			name = arg.substring(j + 3);
			if (strict && !~keys.indexOf(name)) return opts.unknown(arg);
			out[name] = false;
		} else {
			for (idx = j + 1; idx < arg.length; idx++) if (arg.charCodeAt(idx) === 61) break;
			name = arg.substring(j, idx);
			val = arg.substring(++idx) || i + 1 === len || ("" + args[i + 1]).charCodeAt(0) === 45 || args[++i];
			arr = j === 2 ? [name] : name;
			for (idx = 0; idx < arr.length; idx++) {
				name = arr[idx];
				if (strict && !~keys.indexOf(name)) return opts.unknown("-".repeat(j) + name);
				toVal(out, name, idx + 1 < arr.length || val, opts);
			}
		}
	}
	if (defaults) {
		for (k in opts.default) if (out[k] === void 0) out[k] = opts.default[k];
	}
	if (alibi) for (k in out) {
		arr = opts.alias[k] || [];
		while (arr.length > 0) out[arr.shift()] = out[k];
	}
	return out;
}
const removeBrackets = (v) => v.replace(/[<[].+/, "").trim();
const findAllBrackets = (v) => {
	const ANGLED_BRACKET_RE_GLOBAL = /<([^>]+)>/g;
	const SQUARE_BRACKET_RE_GLOBAL = /\[([^\]]+)\]/g;
	const res = [];
	const parse = (match) => {
		let variadic = false;
		let value = match[1];
		if (value.startsWith("...")) {
			value = value.slice(3);
			variadic = true;
		}
		return {
			required: match[0].startsWith("<"),
			value,
			variadic
		};
	};
	let angledMatch;
	while (angledMatch = ANGLED_BRACKET_RE_GLOBAL.exec(v)) res.push(parse(angledMatch));
	let squareMatch;
	while (squareMatch = SQUARE_BRACKET_RE_GLOBAL.exec(v)) res.push(parse(squareMatch));
	return res;
};
const getMriOptions = (options) => {
	const result = {
		alias: {},
		boolean: []
	};
	for (const [index, option] of options.entries()) {
		if (option.names.length > 1) result.alias[option.names[0]] = option.names.slice(1);
		if (option.isBoolean) if (option.negated) {
			if (!options.some((o, i) => {
				return i !== index && o.names.some((name) => option.names.includes(name)) && typeof o.required === "boolean";
			})) result.boolean.push(option.names[0]);
		} else result.boolean.push(option.names[0]);
	}
	return result;
};
const findLongest = (arr) => {
	return arr.sort((a, b) => {
		return a.length > b.length ? -1 : 1;
	})[0];
};
const padRight = (str, length) => {
	return str.length >= length ? str : `${str}${" ".repeat(length - str.length)}`;
};
const camelcase = (input) => {
	return input.replace(/([a-z])-([a-z])/g, (_, p1, p2) => {
		return p1 + p2.toUpperCase();
	});
};
const setDotProp = (obj, keys, val) => {
	let i = 0;
	let length = keys.length;
	let t = obj;
	let x;
	for (; i < length; ++i) {
		x = t[keys[i]];
		t = t[keys[i]] = i === length - 1 ? val : x != null ? x : !!~keys[i + 1].indexOf(".") || !(+keys[i + 1] > -1) ? {} : [];
	}
};
const setByType = (obj, transforms) => {
	for (const key of Object.keys(transforms)) {
		const transform = transforms[key];
		if (transform.shouldTransform) {
			obj[key] = Array.prototype.concat.call([], obj[key]);
			if (typeof transform.transformFunction === "function") obj[key] = obj[key].map(transform.transformFunction);
		}
	}
};
const getFileName = (input) => {
	const m = /([^\\\/]+)$/.exec(input);
	return m ? m[1] : "";
};
const camelcaseOptionName = (name) => {
	return name.split(".").map((v, i) => {
		return i === 0 ? camelcase(v) : v;
	}).join(".");
};
var CACError = class extends Error {
	constructor(message) {
		super(message);
		this.name = this.constructor.name;
		if (typeof Error.captureStackTrace === "function") Error.captureStackTrace(this, this.constructor);
		else this.stack = new Error(message).stack;
	}
};
var Option = class {
	constructor(rawName, description, config) {
		this.rawName = rawName;
		this.description = description;
		this.config = Object.assign({}, config);
		rawName = rawName.replace(/\.\*/g, "");
		this.negated = false;
		this.names = removeBrackets(rawName).split(",").map((v) => {
			let name = v.trim().replace(/^-{1,2}/, "");
			if (name.startsWith("no-")) {
				this.negated = true;
				name = name.replace(/^no-/, "");
			}
			return camelcaseOptionName(name);
		}).sort((a, b) => a.length > b.length ? 1 : -1);
		this.name = this.names[this.names.length - 1];
		if (this.negated && this.config.default == null) this.config.default = true;
		if (rawName.includes("<")) this.required = true;
		else if (rawName.includes("[")) this.required = false;
		else this.isBoolean = true;
	}
};
const processArgs = process.argv;
const platformInfo = `${process.platform}-${process.arch} node-${process.version}`;
var Command = class {
	constructor(rawName, description, config = {}, cli) {
		this.rawName = rawName;
		this.description = description;
		this.config = config;
		this.cli = cli;
		this.options = [];
		this.aliasNames = [];
		this.name = removeBrackets(rawName);
		this.args = findAllBrackets(rawName);
		this.examples = [];
	}
	usage(text) {
		this.usageText = text;
		return this;
	}
	allowUnknownOptions() {
		this.config.allowUnknownOptions = true;
		return this;
	}
	ignoreOptionDefaultValue() {
		this.config.ignoreOptionDefaultValue = true;
		return this;
	}
	version(version, customFlags = "-v, --version") {
		this.versionNumber = version;
		this.option(customFlags, "Display version number");
		return this;
	}
	example(example) {
		this.examples.push(example);
		return this;
	}
	option(rawName, description, config) {
		const option = new Option(rawName, description, config);
		this.options.push(option);
		return this;
	}
	alias(name) {
		this.aliasNames.push(name);
		return this;
	}
	action(callback) {
		this.commandAction = callback;
		return this;
	}
	isMatched(name) {
		return this.name === name || this.aliasNames.includes(name);
	}
	get isDefaultCommand() {
		return this.name === "" || this.aliasNames.includes("!");
	}
	get isGlobalCommand() {
		return this instanceof GlobalCommand;
	}
	hasOption(name) {
		name = name.split(".")[0];
		return this.options.find((option) => {
			return option.names.includes(name);
		});
	}
	outputHelp() {
		const { name, commands } = this.cli;
		const { versionNumber, options: globalOptions, helpCallback } = this.cli.globalCommand;
		let sections = [{ body: `${name}${versionNumber ? `/${versionNumber}` : ""}` }];
		sections.push({
			title: "Usage",
			body: `  $ ${name} ${this.usageText || this.rawName}`
		});
		if ((this.isGlobalCommand || this.isDefaultCommand) && commands.length > 0) {
			const longestCommandName = findLongest(commands.map((command) => command.rawName));
			sections.push({
				title: "Commands",
				body: commands.map((command) => {
					return `  ${padRight(command.rawName, longestCommandName.length)}  ${command.description}`;
				}).join("\n")
			});
			sections.push({
				title: `For more info, run any command with the \`--help\` flag`,
				body: commands.map((command) => `  $ ${name}${command.name === "" ? "" : ` ${command.name}`} --help`).join("\n")
			});
		}
		let options = this.isGlobalCommand ? globalOptions : [...this.options, ...globalOptions || []];
		if (!this.isGlobalCommand && !this.isDefaultCommand) options = options.filter((option) => option.name !== "version");
		if (options.length > 0) {
			const longestOptionName = findLongest(options.map((option) => option.rawName));
			sections.push({
				title: "Options",
				body: options.map((option) => {
					return `  ${padRight(option.rawName, longestOptionName.length)}  ${option.description} ${option.config.default === void 0 ? "" : `(default: ${option.config.default})`}`;
				}).join("\n")
			});
		}
		if (this.examples.length > 0) sections.push({
			title: "Examples",
			body: this.examples.map((example) => {
				if (typeof example === "function") return example(name);
				return example;
			}).join("\n")
		});
		if (helpCallback) sections = helpCallback(sections) || sections;
		console.log(sections.map((section) => {
			return section.title ? `${section.title}:
${section.body}` : section.body;
		}).join("\n\n"));
	}
	outputVersion() {
		const { name } = this.cli;
		const { versionNumber } = this.cli.globalCommand;
		if (versionNumber) console.log(`${name}/${versionNumber} ${platformInfo}`);
	}
	checkRequiredArgs() {
		const minimalArgsCount = this.args.filter((arg) => arg.required).length;
		if (this.cli.args.length < minimalArgsCount) throw new CACError(`missing required args for command \`${this.rawName}\``);
	}
	checkUnknownOptions() {
		const { options, globalCommand } = this.cli;
		if (!this.config.allowUnknownOptions) {
			for (const name of Object.keys(options)) if (name !== "--" && !this.hasOption(name) && !globalCommand.hasOption(name)) throw new CACError(`Unknown option \`${name.length > 1 ? `--${name}` : `-${name}`}\``);
		}
	}
	checkOptionValue() {
		const { options: parsedOptions, globalCommand } = this.cli;
		const options = [...globalCommand.options, ...this.options];
		for (const option of options) {
			const value = parsedOptions[option.name.split(".")[0]];
			if (option.required) {
				const hasNegated = options.some((o) => o.negated && o.names.includes(option.name));
				if (value === true || value === false && !hasNegated) throw new CACError(`option \`${option.rawName}\` value is missing`);
			}
		}
	}
};
var GlobalCommand = class extends Command {
	constructor(cli) {
		super("@@global@@", "", {}, cli);
	}
};
var __assign = Object.assign;
var CAC = class extends EventEmitter {
	constructor(name = "") {
		super();
		this.name = name;
		this.commands = [];
		this.rawArgs = [];
		this.args = [];
		this.options = {};
		this.globalCommand = new GlobalCommand(this);
		this.globalCommand.usage("<command> [options]");
	}
	usage(text) {
		this.globalCommand.usage(text);
		return this;
	}
	command(rawName, description, config) {
		const command = new Command(rawName, description || "", config, this);
		command.globalCommand = this.globalCommand;
		this.commands.push(command);
		return command;
	}
	option(rawName, description, config) {
		this.globalCommand.option(rawName, description, config);
		return this;
	}
	help(callback) {
		this.globalCommand.option("-h, --help", "Display this message");
		this.globalCommand.helpCallback = callback;
		this.showHelpOnExit = true;
		return this;
	}
	version(version, customFlags = "-v, --version") {
		this.globalCommand.version(version, customFlags);
		this.showVersionOnExit = true;
		return this;
	}
	example(example) {
		this.globalCommand.example(example);
		return this;
	}
	outputHelp() {
		if (this.matchedCommand) this.matchedCommand.outputHelp();
		else this.globalCommand.outputHelp();
	}
	outputVersion() {
		this.globalCommand.outputVersion();
	}
	setParsedInfo({ args, options }, matchedCommand, matchedCommandName) {
		this.args = args;
		this.options = options;
		if (matchedCommand) this.matchedCommand = matchedCommand;
		if (matchedCommandName) this.matchedCommandName = matchedCommandName;
		return this;
	}
	unsetMatchedCommand() {
		this.matchedCommand = void 0;
		this.matchedCommandName = void 0;
	}
	parse(argv = processArgs, { run = true } = {}) {
		this.rawArgs = argv;
		if (!this.name) this.name = argv[1] ? getFileName(argv[1]) : "cli";
		let shouldParse = true;
		for (const command of this.commands) {
			const parsed = this.mri(argv.slice(2), command);
			const commandName = parsed.args[0];
			if (command.isMatched(commandName)) {
				shouldParse = false;
				const parsedInfo = __assign(__assign({}, parsed), { args: parsed.args.slice(1) });
				this.setParsedInfo(parsedInfo, command, commandName);
				this.emit(`command:${commandName}`, command);
			}
		}
		if (shouldParse) {
			for (const command of this.commands) if (command.name === "") {
				shouldParse = false;
				const parsed = this.mri(argv.slice(2), command);
				this.setParsedInfo(parsed, command);
				this.emit(`command:!`, command);
			}
		}
		if (shouldParse) {
			const parsed = this.mri(argv.slice(2));
			this.setParsedInfo(parsed);
		}
		if (this.options.help && this.showHelpOnExit) {
			this.outputHelp();
			run = false;
			this.unsetMatchedCommand();
		}
		if (this.options.version && this.showVersionOnExit && this.matchedCommandName == null) {
			this.outputVersion();
			run = false;
			this.unsetMatchedCommand();
		}
		const parsedArgv = {
			args: this.args,
			options: this.options
		};
		if (run) this.runMatchedCommand();
		if (!this.matchedCommand && this.args[0]) this.emit("command:*");
		return parsedArgv;
	}
	mri(argv, command) {
		const cliOptions = [...this.globalCommand.options, ...command ? command.options : []];
		const mriOptions = getMriOptions(cliOptions);
		let argsAfterDoubleDashes = [];
		const doubleDashesIndex = argv.indexOf("--");
		if (doubleDashesIndex > -1) {
			argsAfterDoubleDashes = argv.slice(doubleDashesIndex + 1);
			argv = argv.slice(0, doubleDashesIndex);
		}
		let parsed = mri2(argv, mriOptions);
		parsed = Object.keys(parsed).reduce((res, name) => {
			return __assign(__assign({}, res), { [camelcaseOptionName(name)]: parsed[name] });
		}, { _: [] });
		const args = parsed._;
		const options = { "--": argsAfterDoubleDashes };
		const ignoreDefault = command && command.config.ignoreOptionDefaultValue ? command.config.ignoreOptionDefaultValue : this.globalCommand.config.ignoreOptionDefaultValue;
		let transforms = Object.create(null);
		for (const cliOption of cliOptions) {
			if (!ignoreDefault && cliOption.config.default !== void 0) for (const name of cliOption.names) options[name] = cliOption.config.default;
			if (Array.isArray(cliOption.config.type)) {
				if (transforms[cliOption.name] === void 0) {
					transforms[cliOption.name] = Object.create(null);
					transforms[cliOption.name]["shouldTransform"] = true;
					transforms[cliOption.name]["transformFunction"] = cliOption.config.type[0];
				}
			}
		}
		for (const key of Object.keys(parsed)) if (key !== "_") {
			setDotProp(options, key.split("."), parsed[key]);
			setByType(options, transforms);
		}
		return {
			args,
			options
		};
	}
	runMatchedCommand() {
		const { args, options, matchedCommand: command } = this;
		if (!command || !command.commandAction) return;
		command.checkUnknownOptions();
		command.checkOptionValue();
		command.checkRequiredArgs();
		const actionArgs = [];
		command.args.forEach((arg, index) => {
			if (arg.variadic) actionArgs.push(args.slice(index));
			else actionArgs.push(args[index]);
		});
		actionArgs.push(options);
		return command.commandAction.apply(this, actionArgs);
	}
};
const cac = (name = "") => new CAC(name);

//#endregion
//#region src/config.ts
const DEFAULT_CONFIG_FILES = [
	"database-query.local.mjs",
	"database-query.local.js",
	"database-query.local.json",
	"database-query.config.mjs",
	"database-query.config.js",
	"database-query.config.json"
];
const GLOBAL_CONFIG_DIRECTORY_NAME = "database-query";
const DEFAULT_LIMIT = 50;
const DEFAULT_MAX_LIMIT = 1e3;
const DEFAULT_PERMISSION_LEVEL = "readonly";
const DEFAULT_OUTPUT_FORMAT = "text";
const DEFAULT_ALLOWED_ACTIONS = {
	postgres: ["sql"],
	mysql: ["sql"],
	sqlite: ["sql"],
	mongodb: [
		"list-collections",
		"count",
		"find"
	],
	redis: [
		"ping",
		"info",
		"scan",
		"type",
		"ttl",
		"get",
		"hget",
		"lrange"
	],
	milvus: [
		"list-collections",
		"describe-collection",
		"query",
		"search"
	]
};
const SECRET_FIELDS = [
	"password",
	"uri",
	"url",
	"token"
];
var ConfigError = class extends Error {
	exitCode;
	/**
	* 创建可控配置错误。
	*
	* @param message 错误消息。
	* @param exitCode 进程退出码。
	*/
	constructor(message, exitCode = 1) {
		super(message);
		this.exitCode = exitCode;
	}
};
/**
* 加载 database-query 配置。
*
* @param configPath 显式配置文件路径；未传时按项目级、全局默认文件名查找。
* @returns 已解析并替换环境变量占位符的配置。
*/
async function loadConfig(configPath) {
	const resolvedPath = configPath ? resolve(configPath) : findDefaultConfig();
	if (!resolvedPath) throw new ConfigError(`未找到配置文件。请提供 --config，或在当前目录、${getGlobalConfigDirectory()} 创建 ${DEFAULT_CONFIG_FILES.join(" / ")}。`);
	const extension = extname(resolvedPath);
	let rawConfig;
	if (extension === ".json") rawConfig = JSON.parse(readFileSync(resolvedPath, "utf8"));
	else if (extension === ".mjs" || extension === ".js") {
		const imported = await import(pathToFileURL(resolvedPath).href);
		rawConfig = imported.default ?? imported.config;
	} else throw new ConfigError(`不支持的配置格式: ${extension}`);
	const config = resolveEnvPlaceholders(rawConfig);
	validateConfig(config, resolvedPath);
	return {
		path: resolvedPath,
		config
	};
}
/**
* 解析默认配置查找路径，用于 CLI 向用户解释查找顺序。
*
* @param projectDirectory 项目级查找目录，默认使用当前工作目录。
* @returns 配置查找路径摘要。
*/
function getConfigSearchPaths(projectDirectory = process.cwd()) {
	const projectRoot = resolve(projectDirectory);
	const globalDirectory = getGlobalConfigDirectory();
	return {
		projectDirectory: projectRoot,
		globalDirectory,
		globalLocalConfigPath: getGlobalLocalConfigPath(),
		filenames: [...DEFAULT_CONFIG_FILES],
		projectCandidates: DEFAULT_CONFIG_FILES.map((file) => resolve(projectRoot, file)),
		globalCandidates: DEFAULT_CONFIG_FILES.map((file) => resolve(globalDirectory, file))
	};
}
/**
* 查找默认配置文件，不加载配置内容。
*
* @param projectDirectory 项目级查找目录，默认使用当前工作目录。
* @returns 命中的配置文件绝对路径；未找到返回 undefined。
*/
function findDefaultConfigPath(projectDirectory = process.cwd()) {
	return findConfigInDirectory(resolve(projectDirectory)) ?? findConfigInDirectory(getGlobalConfigDirectory());
}
/**
* 获取带默认值的全局策略。
*
* @param config database-query 配置。
* @returns 合并默认值后的策略。
*/
function getEffectiveDefaults(config) {
	const defaults = config.defaults ?? {};
	return {
		defaultInstance: defaults.defaultInstance,
		limit: defaults.limit ?? DEFAULT_LIMIT,
		maxLimit: defaults.maxLimit ?? DEFAULT_MAX_LIMIT,
		permissionLevel: defaults.permissionLevel ?? DEFAULT_PERMISSION_LEVEL,
		outputFormat: defaults.outputFormat ?? DEFAULT_OUTPUT_FORMAT,
		redactFields: defaults.redactFields ?? [...SECRET_FIELDS],
		allowedActions: mergeAllowedActions(defaults)
	};
}
/**
* 解析 instance、database、schema、collection 目标。
*
* @param config database-query 配置。
* @param options 目标选择参数。
* @returns 唯一确定的目标。
*/
function resolveTarget(config, options) {
	const defaults = getEffectiveDefaults(config);
	const instance = resolveByName(config.instances, options.instance, defaults.defaultInstance, "instance", (item) => item.id);
	const database = resolveOptionalDatabase(instance, instance.databases ?? [], options);
	return {
		instance,
		database,
		schema: resolveNamespace(database?.schemas ?? [], options.schema, database?.defaultSchema, "schema"),
		collection: resolveNamespace(database?.collections ?? [], options.collection, database?.defaultCollection, "collection")
	};
}
/**
* 创建脱敏上下文快照，供 agent 查询前读取。
*
* @param loaded 已加载配置。
* @param instanceId 可选实例过滤。
* @returns 脱敏上下文。
*/
function createContextSnapshot(loaded, instanceId) {
	const defaults = getEffectiveDefaults(loaded.config);
	const instances = instanceId ? [resolveByName(loaded.config.instances, instanceId, void 0, "instance", (item) => item.id)] : loaded.config.instances;
	return {
		configPath: loaded.path,
		defaults,
		instances: instances.map((instance) => createContextInstance(instance, defaults.allowedActions))
	};
}
/**
* 获取指定数据库类型允许的动作。
*
* @param config database-query 配置。
* @param instance 目标实例。
* @returns 动作名称列表。
*/
function getAllowedActions(config, instance) {
	const defaults = getEffectiveDefaults(config);
	return instance.allowedActions ?? defaults.allowedActions[instance.type] ?? [];
}
/**
* 将配置值中的 `${env:NAME}` 占位符替换为环境变量。
*
* @param value 待解析的任意配置值。
* @returns 替换后的配置值。
*/
function resolveEnvPlaceholders(value) {
	if (typeof value === "string") {
		const fullMatch = value.match(/^\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/);
		if (fullMatch) {
			const envValue = process.env[fullMatch[1]];
			if (envValue === void 0) throw new ConfigError(`缺少环境变量: ${fullMatch[1]}`);
			return envValue;
		}
		return value.replace(/\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}/g, (_match, name) => {
			const envValue = process.env[name];
			if (envValue === void 0) throw new ConfigError(`缺少环境变量: ${name}`);
			return envValue;
		});
	}
	if (Array.isArray(value)) return value.map((item) => resolveEnvPlaceholders(item));
	if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, resolveEnvPlaceholders(entry)]));
	return value;
}
/**
* 按项目级优先、全局兜底的顺序查找配置。
*
* @returns 找到的绝对路径；未找到返回 undefined。
*/
function findDefaultConfig() {
	return findDefaultConfigPath();
}
/**
* 在指定目录按默认文件名查找配置。
*
* @param directory 待查找配置的目录。
* @returns 找到的绝对路径；未找到返回 undefined。
*/
function findConfigInDirectory(directory) {
	for (const file of DEFAULT_CONFIG_FILES) {
		const candidate = resolve(directory, file);
		if (existsSync(candidate)) return candidate;
	}
}
/**
* 解析 agent 无关的用户级 database-query 配置目录。
*
* @returns XDG 规范下的 database-query 用户配置目录。
*/
function getGlobalConfigDirectory() {
	const xdgConfigHome = process.env.XDG_CONFIG_HOME?.trim();
	return resolve(xdgConfigHome ? xdgConfigHome : join(homedir(), ".config"), GLOBAL_CONFIG_DIRECTORY_NAME);
}
/**
* 获取默认全局本机私有配置文件路径。
*
* @returns XDG 用户配置目录下的 database-query.local.json 路径。
*/
function getGlobalLocalConfigPath() {
	return resolve(getGlobalConfigDirectory(), "database-query.local.json");
}
/**
* 进行轻量配置结构校验。
*
* @param config 待校验配置。
* @param configPath 配置文件路径，用于错误提示。
* @returns 无返回值。
*/
function validateConfig(config, configPath) {
	if (!config || typeof config !== "object") throw new ConfigError(`配置文件不是对象: ${configPath}`);
	if (!Array.isArray(config.instances) || config.instances.length === 0) throw new ConfigError("配置必须包含至少一个 instances[]。");
	const ids = /* @__PURE__ */ new Set();
	for (const instance of config.instances) {
		if (!instance.id || !instance.type) throw new ConfigError("每个 instance 必须包含 id 与 type。");
		if (ids.has(instance.id)) throw new ConfigError(`重复的 instance id: ${instance.id}`);
		ids.add(instance.id);
	}
}
/**
* 合并内置允许动作与配置允许动作。
*
* @param defaults 配置默认策略。
* @returns 每种数据库类型允许的动作列表。
*/
function mergeAllowedActions(defaults) {
	return {
		...DEFAULT_ALLOWED_ACTIONS,
		...defaults.allowedActions ?? {}
	};
}
/**
* 按显式值、默认值、单候选顺序解析唯一对象。
*
* @param items 候选对象。
* @param explicitName 显式名称。
* @param defaultName 默认名称。
* @param label 错误提示中的目标标签。
* @param getName 取名函数。
* @returns 唯一候选。
*/
function resolveByName(items, explicitName, defaultName, label, getName) {
	const wanted = explicitName ?? defaultName;
	if (wanted) {
		const found = items.find((item) => getName(item) === wanted);
		if (!found) throw new ConfigError(`未找到 ${label}: ${wanted}。可选值: ${items.map(getName).join(", ")}`);
		return found;
	}
	if (items.length === 1) return items[0];
	throw new ConfigError(`无法唯一确定 ${label}。请显式指定，可选值: ${items.map(getName).join(", ")}`);
}
/**
* 解析实例下的数据库目标。
*
* @param instance 目标实例。
* @param databases 候选数据库。
* @param options 目标选择参数。
* @returns 数据库目标；无数据库需求时返回 undefined。
*/
function resolveOptionalDatabase(instance, databases, options) {
	if (databases.length === 0) {
		const databaseName = options.database ?? instance.defaultDatabase;
		if (databaseName) return { name: databaseName };
		if (options.requireDatabase && instance.type !== "sqlite") throw new ConfigError(`instance ${instance.id} 需要 database。请提供 --database，或配置 defaultDatabase。`);
		return;
	}
	if (options.requireDatabase || options.database || instance.defaultDatabase) return resolveByName(databases, options.database, instance.defaultDatabase, "database", (item) => item.name);
	return databases.length === 1 ? databases[0] : void 0;
}
/**
* 解析 schema 或 collection 命名空间。
*
* @param values 候选命名空间。
* @param explicitName 显式名称。
* @param defaultName 默认名称。
* @param label 错误提示标签。
* @returns 命名空间名称；没有候选时返回 undefined。
*/
function resolveNamespace(values, explicitName, defaultName, label) {
	if (values.length === 0) {
		if (explicitName || defaultName) throw new ConfigError(`当前 database 未配置 ${label} 候选。`);
		return;
	}
	if (!explicitName && !defaultName && values.length > 1) return;
	return resolveByName(values, explicitName, defaultName, label, (item) => item);
}
/**
* 创建单个实例的脱敏上下文。
*
* @param instance 数据库实例。
* @param allowedActions 默认允许动作。
* @returns 脱敏后的实例上下文。
*/
function createContextInstance(instance, allowedActions) {
	return {
		id: instance.id,
		type: instance.type,
		environment: instance.environment,
		readonly: instance.readonly,
		defaultDatabase: instance.defaultDatabase,
		databases: instance.databases ?? [],
		allowedActions: instance.allowedActions ?? allowedActions[instance.type] ?? [],
		secretStatus: getSecretStatus(instance)
	};
}
/**
* 获取凭据字段可用性，不返回真实值。
*
* @param instance 数据库实例。
* @returns 凭据字段状态。
*/
function getSecretStatus(instance) {
	const status = {};
	for (const field of SECRET_FIELDS) if (field in instance) status[field] = instance[field] ? "present" : "missing";
	if (Object.keys(status).length === 0) status.none = "notRequired";
	return status;
}

//#endregion
//#region src/core.ts
const DDL_PATTERN = /\b(?:alter|create|drop|truncate|rename|reindex|vacuum\s+full|cluster|grant|revoke)\b/i;
const DML_PATTERN = /\b(?:insert|update|delete|merge|replace|upsert)\b/i;
const EXPORT_PATTERN = /\b(?:copy\s+.+\s+to|load\s+data|select\s+.+\s+into\s+outfile|into\s+dumpfile|\.dump|\.backup)\b/i;
const TRANSACTION_PATTERN = /\b(?:begin|commit|rollback|savepoint|lock\s+table|for\s+update|for\s+share)\b/i;
const DANGEROUS_FUNCTION_PATTERN = /\b(?:pg_sleep|pg_read_file|pg_write_file|pg_ls_dir|dblink|lo_import|lo_export|xp_cmdshell)\b/i;
/**
* 移除 SQL 注释与字符串字面量，便于执行保守的静态关键词检查。
*
* @param sql 原始 SQL 文本。
* @returns 归一化后的 SQL 文本，字符串内容会被占位符替换。
*/
function stripSqlNoise(sql) {
	let output = "";
	let index = 0;
	let inSingleQuote = false;
	let inDoubleQuote = false;
	let inLineComment = false;
	let inBlockComment = false;
	let dollarTag = null;
	while (index < sql.length) {
		const current = sql[index];
		const next = sql[index + 1];
		if (inLineComment) {
			if (current === "\n") {
				inLineComment = false;
				output += "\n";
			} else output += " ";
			index += 1;
			continue;
		}
		if (inBlockComment) {
			if (current === "*" && next === "/") {
				inBlockComment = false;
				output += "  ";
				index += 2;
			} else {
				output += current === "\n" ? "\n" : " ";
				index += 1;
			}
			continue;
		}
		if (dollarTag) {
			if (sql.startsWith(dollarTag, index)) {
				output += " ".repeat(dollarTag.length);
				index += dollarTag.length;
				dollarTag = null;
			} else {
				output += current === "\n" ? "\n" : " ";
				index += 1;
			}
			continue;
		}
		if (inSingleQuote) {
			if (current === "'" && next === "'") {
				output += "  ";
				index += 2;
			} else if (current === "'") {
				inSingleQuote = false;
				output += " ";
				index += 1;
			} else {
				output += current === "\n" ? "\n" : " ";
				index += 1;
			}
			continue;
		}
		if (inDoubleQuote) {
			if (current === "\"" && next === "\"") {
				output += "  ";
				index += 2;
			} else if (current === "\"") {
				inDoubleQuote = false;
				output += " ";
				index += 1;
			} else {
				output += current === "\n" ? "\n" : " ";
				index += 1;
			}
			continue;
		}
		if (current === "-" && next === "-") {
			inLineComment = true;
			output += "  ";
			index += 2;
			continue;
		}
		if (current === "/" && next === "*") {
			inBlockComment = true;
			output += "  ";
			index += 2;
			continue;
		}
		if (current === "'") {
			inSingleQuote = true;
			output += " ";
			index += 1;
			continue;
		}
		if (current === "\"") {
			inDoubleQuote = true;
			output += " ";
			index += 1;
			continue;
		}
		const dollarMatch = sql.slice(index).match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/);
		if (dollarMatch) {
			dollarTag = dollarMatch[0];
			output += " ".repeat(dollarTag.length);
			index += dollarTag.length;
			continue;
		}
		output += current;
		index += 1;
	}
	return output;
}
/**
* 按 SQL 分号拆分语句，忽略注释和字符串内部的分号。
*
* @param sql 原始 SQL 文本。
* @returns 非空 SQL 语句列表。
*/
function splitSqlStatements(sql) {
	return stripSqlNoise(sql).split(";").map((statement) => statement.trim()).filter(Boolean);
}
/**
* 判断 SQL 是否属于只读查询。
*
* @param statement 已归一化的单条 SQL。
* @returns 只读查询返回 true。
*/
function isReadonlyQuery(statement) {
	const compact = statement.trim().replace(/\s+/g, " ");
	return /^(?:with\b[\s\S]+\bselect\b|select\b|explain\b[\s\S]*\bselect\b)/i.test(compact);
}
/**
* 判断 SQL 是否显式包含结果限制。
*
* @param statement 已归一化的单条 SQL。
* @returns 包含 LIMIT / FETCH / TOP 时返回 true。
*/
function hasResultLimit(statement) {
	return /\blimit\s+\d+\b/i.test(statement) || /\bfetch\s+first\s+\d+\s+rows\b/i.test(statement) || /\btop\s+\d+\b/i.test(statement);
}
/**
* 提取 LIMIT 数值，便于限制过大的查询。
*
* @param statement 已归一化的单条 SQL。
* @returns LIMIT 数值；未设置时返回 null。
*/
function extractLimit(statement) {
	const match = statement.match(/\blimit\s+(\d+)\b/i);
	if (!match) return null;
	return Number.parseInt(match[1], 10);
}
/**
* 粗略识别语句类别，用于权限层级判断。
*
* @param statement 已归一化的单条 SQL。
* @returns 语句类别。
*/
function classifyStatement(statement) {
	if (EXPORT_PATTERN.test(statement)) return "export";
	if (DDL_PATTERN.test(statement)) return "ddl";
	if (DML_PATTERN.test(statement)) return "write";
	if (TRANSACTION_PATTERN.test(statement)) return "transaction";
	if (isReadonlyQuery(statement)) return "readonly";
	if (/^(?:explain|analyze|show|describe|pragma)\b/i.test(statement)) return "maintenance";
	return "unknown";
}
/**
* 检查 SQL 文本是否满足指定权限层级的安全策略。
*
* @param sql 原始 SQL 文本。
* @param options 检查选项。
* @returns 检查结果，包含是否通过、语句类别和风险列表。
*/
function checkSql(sql, options) {
	const normalizedStatements = splitSqlStatements(sql).map((statement) => statement.trim());
	const findings = [];
	if (normalizedStatements.length === 0) findings.push({
		code: "EMPTY_SQL",
		message: "SQL 内容为空。",
		severity: "block"
	});
	if (normalizedStatements.length > 1) findings.push({
		code: "MULTI_STATEMENT",
		message: "检测到多条 SQL 语句。请拆分后逐条检查和执行。",
		severity: "block"
	});
	const firstStatement = normalizedStatements[0] ?? "";
	const kind = firstStatement ? classifyStatement(firstStatement) : "unknown";
	if (firstStatement && DANGEROUS_FUNCTION_PATTERN.test(firstStatement)) findings.push({
		code: "DANGEROUS_FUNCTION",
		message: "检测到危险函数或扩展命令，请人工审查执行意图。",
		severity: "block"
	});
	if (firstStatement) addLevelFindings(findings, firstStatement, kind, options);
	if (options.level === "yolo" && findings.length === 0 && kind !== "readonly") findings.push({
		code: "YOLO_REVIEW",
		message: `${kind} 类型语句已进入 yolo 风险接管模式，执行前仍需用户显式确认。`,
		severity: "warn"
	});
	const effectiveFindings = options.level === "yolo" ? findings.map((finding) => ({
		...finding,
		severity: finding.code === "EMPTY_SQL" ? finding.severity : "warn"
	})) : findings;
	return {
		ok: effectiveFindings.every((finding) => finding.severity !== "block"),
		level: options.level,
		dialect: options.dialect,
		statementCount: normalizedStatements.length,
		kind,
		findings: effectiveFindings
	};
}
/**
* 根据权限层级追加语句类型相关的风险结论。
*
* @param findings 待写入的风险列表。
* @param statement 已归一化的单条 SQL。
* @param kind SQL 语句类别。
* @param options 检查选项。
* @returns 无返回值，结果写入 `findings`。
*/
function addLevelFindings(findings, statement, kind, options) {
	if (kind === "unknown") {
		findings.push({
			code: "UNKNOWN_STATEMENT",
			message: "无法确认语句类型。请人工确认后使用更高权限层级。",
			severity: options.level === "admin" ? "warn" : "block"
		});
		return;
	}
	if (kind === "readonly") {
		addReadonlyFindings(findings, statement, options);
		return;
	}
	if (options.level === "readonly") {
		findings.push({
			code: "READONLY_FORBIDDEN",
			message: `readonly 层级禁止执行 ${kind} 类型语句。`,
			severity: "block"
		});
		return;
	}
	if (options.level === "maintenance") {
		const allowed = kind === "maintenance" || kind === "transaction";
		findings.push({
			code: allowed ? "MAINTENANCE_REVIEW" : "MAINTENANCE_FORBIDDEN",
			message: allowed ? `${kind} 类型语句需要人工确认目标实例、数据库和影响范围。` : `maintenance 层级禁止执行 ${kind} 类型语句。`,
			severity: allowed ? "warn" : "block"
		});
		return;
	}
	if (options.level === "admin") findings.push({
		code: kind === "export" ? "ADMIN_EXPORT_REVIEW" : "ADMIN_REVIEW",
		message: `${kind} 类型语句需要用户显式确认目标实例、数据库、操作和影响范围。`,
		severity: kind === "export" ? "block" : "warn"
	});
}
/**
* 追加只读查询的结果集限制相关风险结论。
*
* @param findings 待写入的风险列表。
* @param statement 已归一化的单条 SQL。
* @param options 检查选项。
* @returns 无返回值，结果写入 `findings`。
*/
function addReadonlyFindings(findings, statement, options) {
	if (!hasResultLimit(statement)) {
		findings.push({
			code: "MISSING_LIMIT",
			message: "只读查询缺少 LIMIT / FETCH / TOP 限制，请限制结果集大小。",
			severity: options.level === "readonly" ? "block" : "warn"
		});
		return;
	}
	const limit = extractLimit(statement);
	if (limit !== null && limit > options.maxLimit) findings.push({
		code: "LIMIT_TOO_LARGE",
		message: `LIMIT ${limit} 超过当前上限 ${options.maxLimit}，请缩小结果集。`,
		severity: options.level === "readonly" ? "block" : "warn"
	});
}

//#endregion
//#region src/planner.ts
var PlanError = class extends Error {
	exitCode;
	/**
	* 创建执行计划错误。
	*
	* @param message 错误消息。
	* @param exitCode 进程退出码。
	*/
	constructor(message, exitCode = 1) {
		super(message);
		this.exitCode = exitCode;
	}
};
/**
* 为关系型数据库 SQL 执行创建底层 CLI 计划。
*
* @param target 已解析目标。
* @param options SQL 执行参数。
* @returns 执行计划。
*/
function createSqlExecutionPlan(target, options) {
	const databaseName = target.database?.name ?? target.instance.defaultDatabase;
	if (!databaseName && target.instance.type !== "sqlite") throw new PlanError("关系型执行需要可确定的 database。");
	if (target.instance.type === "postgres") return createPostgresPlan(target.instance, databaseName, options.sql);
	if (target.instance.type === "mysql") return createMysqlPlan(target.instance, databaseName, options.sql);
	if (target.instance.type === "sqlite") return createSqlitePlan(target.instance, options.sql);
	throw new PlanError(`实例类型不是关系型数据库: ${target.instance.type}`);
}
/**
* 为底层官方客户端创建凭据桥接计划。
*
* @param target 已解析目标。
* @param passthrough 透传给底层 CLI 的参数。
* @returns 执行计划。
*/
function createClientPlan(target, passthrough) {
	const databaseName = target.database?.name ?? target.instance.defaultDatabase;
	switch (target.instance.type) {
		case "postgres": return createPostgresPlan(target.instance, databaseName, void 0, passthrough);
		case "mysql": return createMysqlPlan(target.instance, databaseName, void 0, passthrough);
		case "sqlite": return createSqlitePlan(target.instance, void 0, passthrough);
		case "mongodb": return createMongoPlan(target.instance, databaseName, passthrough);
		case "redis": return createRedisPlan(target.instance, passthrough);
		case "milvus": return {
			tool: "node",
			args: [],
			displayArgs: [],
			env: {},
			displayEnv: {},
			summary: "Milvus 首版没有通用底层 CLI 桥接，请使用 exec 的 Milvus 只读动作或官方 SDK。"
		};
		default: return assertNever(target.instance.type);
	}
}
/**
* 为非 SQL 只读动作创建受控执行计划。
*
* @param config database-query 配置。
* @param target 已解析目标。
* @param options 动作参数。
* @returns 执行计划或 SDK 动作摘要。
*/
function createActionPlan(config, target, options) {
	const allowedActions = getAllowedActions(config, target.instance);
	if (!allowedActions.includes(options.action)) throw new PlanError(`动作 ${options.action} 不允许用于 ${target.instance.type}。允许动作: ${allowedActions.join(", ")}`);
	switch (target.instance.type) {
		case "mongodb": return createMongoActionPlan(target, options);
		case "redis": return createRedisActionPlan(target.instance, options);
		case "milvus": return createMilvusActionPlan(target, options);
		default: throw new PlanError(`${target.instance.type} 的 exec 动作请使用 --sql 或 --file。`);
	}
}
/**
* 格式化执行计划。
*
* @param plan 执行计划。
* @returns 可读的脱敏计划文本。
*/
function formatExecutionPlan(plan) {
	const command = [plan.tool, ...plan.displayArgs].filter(Boolean).join(" ");
	const lines = [`plan: ${plan.summary}`];
	if (command.trim()) lines.push(`command: ${command}`);
	const envEntries = Object.entries(plan.displayEnv);
	if (envEntries.length > 0) lines.push(`env: ${envEntries.map(([key, value]) => `${key}=${value}`).join(" ")}`);
	return lines.join("\n");
}
/**
* 判断数据库类型是否属于关系型 SQL 方言。
*
* @param type 数据库类型。
* @returns 属于 PostgreSQL/MySQL/SQLite 时返回 true。
*/
function isSqlDialect(type) {
	return type === "postgres" || type === "mysql" || type === "sqlite";
}
/**
* 限制执行动作使用的 limit。
*
* @param config database-query 配置。
* @param requested 用户请求的 limit。
* @returns 生效的 limit。
*/
function resolveLimit(config, requested) {
	const defaults = getEffectiveDefaults(config);
	const limit = requested ?? defaults.limit;
	if (limit > defaults.maxLimit) throw new PlanError(`limit ${limit} 超过配置上限 ${defaults.maxLimit}。`);
	return limit;
}
/**
* 创建 PostgreSQL CLI 计划。
*
* @param instance 数据库实例。
* @param databaseName 数据库名。
* @param sql 可选 SQL。
* @param passthrough 透传参数。
* @returns 执行计划。
*/
function createPostgresPlan(instance, databaseName, sql, passthrough = []) {
	if (!databaseName) throw new PlanError("PostgreSQL 需要 database。");
	const args = [
		...optionalPair("-h", instance.host),
		...optionalPair("-p", instance.port?.toString()),
		...optionalPair("-U", instance.username),
		"-d",
		databaseName,
		...passthrough,
		...optionalPair("-c", sql)
	];
	return {
		tool: "psql",
		args,
		displayArgs: args,
		env: instance.password ? { PGPASSWORD: instance.password } : {},
		displayEnv: instance.password ? { PGPASSWORD: "<redacted>" } : {},
		summary: `PostgreSQL ${instance.id}/${databaseName}`
	};
}
/**
* 创建 MySQL CLI 计划。
*
* @param instance 数据库实例。
* @param databaseName 数据库名。
* @param sql 可选 SQL。
* @param passthrough 透传参数。
* @returns 执行计划。
*/
function createMysqlPlan(instance, databaseName, sql, passthrough = []) {
	if (!databaseName) throw new PlanError("MySQL 需要 database。");
	const args = [
		...optionalPair("--host", instance.host),
		...optionalPair("--port", instance.port?.toString()),
		...optionalPair("--user", instance.username),
		"--database",
		databaseName,
		...passthrough,
		...optionalPair("--execute", sql)
	];
	return {
		tool: "mysql",
		args,
		displayArgs: args,
		env: instance.password ? { MYSQL_PWD: instance.password } : {},
		displayEnv: instance.password ? { MYSQL_PWD: "<redacted>" } : {},
		summary: `MySQL ${instance.id}/${databaseName}`
	};
}
/**
* 创建 SQLite CLI 计划。
*
* @param instance 数据库实例。
* @param sql 可选 SQL。
* @param passthrough 透传参数。
* @returns 执行计划。
*/
function createSqlitePlan(instance, sql, passthrough = []) {
	if (!instance.path) throw new PlanError("SQLite instance 必须配置 path。");
	const args = [
		instance.path,
		...passthrough,
		...optionalValue(sql)
	];
	return {
		tool: "sqlite3",
		args,
		displayArgs: args,
		env: {},
		displayEnv: {},
		summary: `SQLite ${instance.id}`
	};
}
/**
* 创建 MongoDB CLI 计划。
*
* @param instance 数据库实例。
* @param databaseName 数据库名。
* @param passthrough 透传参数。
* @returns 执行计划。
*/
function createMongoPlan(instance, databaseName, passthrough) {
	const uri = instance.uri ?? instance.url;
	if (!uri) throw new PlanError("MongoDB instance 必须配置 uri。");
	const args = [withDatabaseInUri(uri, databaseName), ...passthrough];
	return {
		tool: "mongosh",
		args,
		displayArgs: [redactUri(args[0]), ...passthrough],
		env: {},
		displayEnv: {},
		summary: `MongoDB ${instance.id}${databaseName ? `/${databaseName}` : ""}`
	};
}
/**
* 创建 Redis CLI 计划。
*
* @param instance 数据库实例。
* @param passthrough 透传参数。
* @returns 执行计划。
*/
function createRedisPlan(instance, passthrough) {
	if (!instance.url) throw new PlanError("Redis instance 必须配置 url。");
	return {
		tool: "redis-cli",
		args: [
			"-u",
			instance.url,
			...passthrough
		],
		displayArgs: [
			"-u",
			redactUri(instance.url),
			...passthrough
		],
		env: {},
		displayEnv: {},
		summary: `Redis ${instance.id}`
	};
}
/**
* 创建 MongoDB 只读动作计划。
*
* @param target 已解析目标。
* @param options 动作参数。
* @returns 执行计划。
*/
function createMongoActionPlan(target, options) {
	const databaseName = target.database?.name ?? target.instance.defaultDatabase;
	const limit = options.limit ?? 50;
	const collection = target.collection ?? options.key;
	let evalScript;
	if (options.action === "list-collections") evalScript = "db.getCollectionNames().join(\"\\n\")";
	else if (options.action === "count") {
		requireValue(collection, "MongoDB count 需要 collection 或 --key。");
		evalScript = `db.getCollection(${JSON.stringify(collection)}).countDocuments(${options.query ?? "{}"})`;
	} else if (options.action === "find") {
		requireValue(collection, "MongoDB find 需要 collection 或 --key。");
		evalScript = `JSON.stringify(db.getCollection(${JSON.stringify(collection)}).find(${options.query ?? "{}"}).limit(${limit}).toArray(), null, 2)`;
	} else throw new PlanError(`不支持的 MongoDB 动作: ${options.action}`);
	return createMongoPlan(target.instance, databaseName, [
		"--quiet",
		"--eval",
		evalScript
	]);
}
/**
* 创建 Redis 只读动作计划。
*
* @param instance Redis 实例。
* @param options 动作参数。
* @returns 执行计划。
*/
function createRedisActionPlan(instance, options) {
	return createRedisPlan(instance, buildRedisActionArgs(options.action.toUpperCase(), options));
}
/**
* 创建 Milvus SDK 动作摘要计划。
*
* @param target 已解析目标。
* @param options 动作参数。
* @returns SDK 执行摘要。
*/
function createMilvusActionPlan(target, options) {
	const address = target.instance.address ?? target.instance.uri;
	if (!address) throw new PlanError("Milvus instance 必须配置 address 或 uri。");
	return {
		tool: "node",
		args: [],
		displayArgs: [],
		env: {},
		displayEnv: target.instance.token ? { MILVUS_TOKEN: "<redacted>" } : {},
		summary: `Milvus ${target.instance.id} SDK action=${options.action} collection=${target.collection ?? options.key ?? "<none>"}`,
		sdk: {
			provider: "milvus",
			action: options.action,
			address,
			token: target.instance.token,
			collection: target.collection ?? options.key,
			query: options.query,
			vector: options.vector,
			limit: options.limit ?? 50
		}
	};
}
/**
* 构建 Redis 只读动作参数。
*
* @param action Redis 动作。
* @param options 动作参数。
* @returns redis-cli 参数。
*/
function buildRedisActionArgs(action, options) {
	switch (action) {
		case "PING":
		case "INFO": return [action];
		case "SCAN": return options.key ? [
			"SCAN",
			"0",
			"MATCH",
			options.key
		] : ["SCAN", "0"];
		case "TYPE":
		case "TTL":
		case "GET":
			requireValue(options.key, `${action} 需要 --key。`);
			return [action, options.key];
		case "HGET":
			requireValue(options.key, "HGET 需要 --key。");
			requireValue(options.field, "HGET 需要 --field。");
			return [
				action,
				options.key,
				options.field
			];
		case "LRANGE":
			requireValue(options.key, "LRANGE 需要 --key。");
			return [
				action,
				options.key,
				"0",
				String(Math.max((options.limit ?? 50) - 1, 0))
			];
		default: throw new PlanError(`不支持的 Redis 动作: ${action.toLowerCase()}`);
	}
}
/**
* 追加可选参数对。
*
* @param flag 参数名。
* @param value 参数值。
* @returns 参数数组。
*/
function optionalPair(flag, value) {
	return value ? [flag, value] : [];
}
/**
* 追加可选位置参数。
*
* @param value 参数值。
* @returns 参数数组。
*/
function optionalValue(value) {
	return value ? [value] : [];
}
/**
* 校验必填字符串。
*
* @param value 待校验值。
* @param message 缺失时报错消息。
* @returns 无返回值。
*/
function requireValue(value, message) {
	if (!value) throw new PlanError(message);
}
/**
* 将 database 写入 MongoDB URI。
*
* @param uri 原始 URI。
* @param databaseName 数据库名。
* @returns 带数据库路径的 URI。
*/
function withDatabaseInUri(uri, databaseName) {
	if (!databaseName) return uri;
	const parsed = new URL(uri);
	parsed.pathname = `/${databaseName}`;
	return parsed.toString();
}
/**
* 脱敏 URI 中的用户名密码。
*
* @param uri 原始 URI。
* @returns 脱敏 URI。
*/
function redactUri(uri) {
	try {
		const parsed = new URL(uri);
		if (parsed.username) parsed.username = "<redacted>";
		if (parsed.password) parsed.password = "<redacted>";
		return parsed.toString();
	} catch {
		return "<redacted-uri>";
	}
}
/**
* 穷尽类型检查。
*
* @param value 不应出现的值。
* @returns 永不返回。
*/
function assertNever(value) {
	throw new PlanError(`不支持的数据库类型: ${value}`);
}

//#endregion
//#region src/cli.ts
const DIALECTS = new Set([
	"postgres",
	"mysql",
	"sqlite"
]);
const LEVELS = new Set([
	"readonly",
	"maintenance",
	"admin",
	"yolo"
]);
const DEFAULT_STDOUT = console.log.bind(console);
const DEFAULT_STDERR = console.error.bind(console);
var CliError = class extends Error {
	exitCode;
	/**
	* 创建可控退出错误。
	*
	* @param message 错误消息。
	* @param exitCode 进程退出码。
	*/
	constructor(message, exitCode = 1) {
		super(message);
		this.exitCode = exitCode;
	}
};
/**
* 运行 database-query 统一 CLI。
*
* @param argv 进程参数，不包含 node 与脚本路径。
* @param io 输出抽象，便于测试时捕获 stdout/stderr。
* @returns 进程退出码。
*/
async function runCli(argv, io = defaultIo()) {
	try {
		const clientPassthrough = extractClientPassthrough(argv);
		const cli = createCli(io);
		cli.parse([
			"node",
			"database-query",
			...argv
		], { run: false });
		if (clientPassthrough) cli.options.__clientPassthrough = clientPassthrough;
		await cli.runMatchedCommand();
		return 0;
	} catch (error) {
		if (isHelpError(error)) return 0;
		if (error instanceof CliError || error instanceof ConfigError || error instanceof PlanError) {
			io.stderr(error.message);
			return error.exitCode;
		}
		io.stderr(error instanceof Error ? error.message : String(error));
		return 1;
	}
}
/**
* 格式化 SQL guard 检查结果。
*
* @param result 检查结果。
* @returns 面向 CLI 的文本报告。
*/
function formatResult(result) {
	const lines = [`SQL guard: ${result.ok ? "PASS" : "BLOCK"}`, `dialect=${result.dialect} level=${result.level} kind=${result.kind} statements=${result.statementCount}`];
	if (result.level === "yolo") lines.push("warning: yolo 层级只跳过静态阻断，危险操作执行仍需用户显式确认。");
	if (result.findings.length === 0) {
		lines.push("findings: none");
		return lines.join("\n");
	}
	lines.push("findings:");
	for (const finding of result.findings) lines.push(`- [${finding.severity}] ${finding.code}: ${finding.message}`);
	return lines.join("\n");
}
/**
* 创建 database-query CLI 定义。
*
* @param io 输出抽象。
* @returns 已配置的 cac CLI 实例。
*/
function createCli(io) {
	const cli = cac("database-query");
	cli.command("context", "输出脱敏数据库上下文。").option("--config <path>", "配置文件路径。").option("--instance <id>", "聚焦指定实例。").option("--format <format>", "输出格式：text 或 json。", { default: "text" }).action(async (options) => {
		const snapshot = createContextSnapshot(await loadConfig(options.config), options.instance);
		io.stdout(options.format === "json" ? JSON.stringify(snapshot, null, 2) : formatContext(snapshot));
	});
	cli.command("check-sql", "静态检查关系型 SQL。").option("--dialect <dialect>", "SQL 方言：postgres、mysql 或 sqlite。", { default: "postgres" }).option("--level <level>", "权限层级：readonly、maintenance、admin 或 yolo。", { default: "readonly" }).option("--sql <sql>", "直接传入 SQL 文本。").option("--file <path>", "从文件读取 SQL。").option("--max-limit <number>", "允许的最大 LIMIT。", { default: "1000" }).action((options) => {
		const result = runCheckSql(options);
		io.stdout(formatResult(result));
		if (!result.ok) throw new CliError("SQL guard 阻断执行。", 2);
	});
	cli.command("doctor", "检查底层客户端可用性。").action(async () => {
		io.stdout(await formatDoctor());
	});
	cli.command("config <action>", "输出配置文件查找路径或当前配置。").option("--config <path>", "显式配置文件路径。").option("--instance <id>", "目标实例。").option("--database <name>", "PostgreSQL 发现连接库。").option("--include <patterns>", "逗号分隔的库名 glob 白名单。").option("--exclude <patterns>", "逗号分隔的库名 glob 排除列表。").option("--write", "将发现结果写回本机 local JSON 配置。").option("--global", "强制读取并写回 XDG 全局 local JSON 配置。").option("--format <format>", "输出格式：text 或 json。", { default: "text" }).action(async (action, options) => {
		await runConfigCommand(action, options, io);
	});
	cli.command("init-config", "生成最小 database-query 配置模板。").option("--global", "写入 XDG 用户级全局配置路径。").option("--path <path>", "写入指定配置路径。").option("--print", "只打印模板，不写文件。").option("--force", "允许覆盖已有配置文件。").action(async (options) => {
		await runInitConfig(options, io);
	});
	cli.command("exec", "执行受控数据库动作。").option("--config <path>", "配置文件路径。").option("--instance <id>", "目标实例。").option("--database <name>", "目标数据库。").option("--schema <name>", "目标 schema。").option("--collection <name>", "目标 collection。").option("--sql <sql>", "关系型 SQL 文本。").option("--file <path>", "从文件读取关系型 SQL。").option("--level <level>", "SQL guard 权限层级。").option("--action <name>", "MongoDB/Redis/Milvus 只读动作。").option("--limit <number>", "动作 limit。").option("--key <key>", "Redis key 或 collection 名称。").option("--field <field>", "Redis hash field。").option("--query <json>", "MongoDB/Milvus 查询条件。").option("--vector <json>", "Milvus search 向量。").option("--verbose", "执行前打印脱敏执行计划。").option("--print-command", "只打印脱敏执行计划，不执行。").action(async (options) => {
		await runExec(options, io);
	});
	cli.command("client [...args]", "使用配置凭据启动底层官方客户端。", { allowUnknownOptions: true }).option("--config <path>", "配置文件路径。").option("--instance <id>", "目标实例。").option("--database <name>", "目标数据库。").option("--schema <name>", "目标 schema。").option("--collection <name>", "目标 collection。").option("--print-command", "只打印脱敏启动计划，不启动客户端。").action(async (args, options) => {
		await runClient(options.__clientPassthrough ?? args, options, io);
	});
	cli.help();
	return patchHelpOutput(cli, io);
}
/**
* 生成最小配置模板并按需写入文件。
*
* @param options CLI 选项。
* @param io 输出抽象。
* @returns 无返回值。
*/
async function runInitConfig(options, io) {
	const content = createMinimalConfigTemplate();
	if (options.print) {
		io.stdout(content);
		return;
	}
	const targetPath = resolveInitConfigPath(options);
	await mkdir(dirname(targetPath), {
		recursive: true,
		mode: 448
	});
	await writeFile(targetPath, content, {
		flag: options.force ? "w" : "wx",
		mode: 384
	}).catch((error) => {
		if (error.code === "EEXIST") throw new CliError(`配置文件已存在: ${targetPath}。如需覆盖请传 --force。`);
		throw error;
	});
	io.stdout(`created: ${targetPath}`);
}
/**
* 解析 init-config 的写入目标。
*
* @param options CLI 选项。
* @returns 配置文件绝对路径。
*/
function resolveInitConfigPath(options) {
	if (options.path && options.global) throw new CliError("--path 与 --global 只能选择一个。");
	if (options.path) return resolve(options.path);
	if (options.global) return getGlobalLocalConfigPath();
	throw new CliError("请传 --global、--path <path> 或 --print。");
}
/**
* 创建不含真实密钥的最小 database-query 配置模板。
*
* @returns 格式化 JSON 字符串。
*/
function createMinimalConfigTemplate() {
	return `${JSON.stringify({
		defaults: { defaultInstance: "local-postgres" },
		instances: [{
			id: "local-postgres",
			type: "postgres",
			environment: "local",
			host: "localhost",
			port: 5432,
			username: "${env:DB_LOCAL_POSTGRES_USER}",
			password: "${env:DB_LOCAL_POSTGRES_PASSWORD}",
			defaultDatabase: "app",
			readonly: true
		}, {
			id: "local-mysql",
			type: "mysql",
			environment: "local",
			host: "localhost",
			port: 3306,
			username: "${env:DB_LOCAL_MYSQL_USER}",
			password: "${env:DB_LOCAL_MYSQL_PASSWORD}",
			defaultDatabase: "app",
			readonly: true
		}]
	}, null, 2)}\n`;
}
/**
* 执行 check-sql 子命令。
*
* @param options CLI 选项。
* @returns 检查结果。
*/
function runCheckSql(options) {
	const normalizedOptions = {
		dialect: parseDialect(options.dialect ?? "postgres"),
		level: parseLevel(options.level ?? "readonly"),
		maxLimit: parsePositiveInteger(String(options.maxLimit ?? 1e3), "max-limit")
	};
	return checkSql(readSqlInput(options), normalizedOptions);
}
/**
* 执行受控 exec 子命令。
*
* @param options CLI 选项。
* @param io 输出抽象。
* @returns 无返回值。
*/
async function runExec(options, io) {
	const loaded = await loadConfig(options.config);
	const target = resolveTarget(loaded.config, {
		instance: options.instance,
		database: options.database,
		schema: options.schema,
		collection: options.collection,
		requireDatabase: Boolean(options.sql || options.file || options.action)
	});
	let plan;
	if (isSqlDialect(target.instance.type)) {
		const sql = readSqlInput(options);
		const defaults = getEffectiveDefaults(loaded.config);
		const result = checkSql(sql, {
			dialect: target.instance.type,
			level: parseLevel(options.level ?? defaults.permissionLevel),
			maxLimit: defaults.maxLimit
		});
		if (options.verbose || options.printCommand || !result.ok) io.stdout(formatResult(result));
		if (!result.ok) throw new CliError("SQL guard 阻断执行。", 2);
		plan = createSqlExecutionPlan(target, { sql });
	} else {
		if (!options.action) throw new CliError("非关系型 exec 必须提供 --action。");
		plan = createActionPlan(loaded.config, target, {
			action: options.action,
			key: options.key,
			field: options.field,
			query: options.query,
			vector: options.vector,
			limit: options.limit ? resolveLimit(loaded.config, parsePositiveInteger(String(options.limit), "limit")) : resolveLimit(loaded.config)
		});
	}
	await runPlan(plan, {
		io,
		verbose: options.verbose,
		printCommand: options.printCommand
	});
}
/**
* 执行凭据桥接 client 子命令。
*
* @param passthrough 透传到底层 CLI 的参数。
* @param options CLI 选项。
* @param io 输出抽象。
* @returns 无返回值。
*/
async function runClient(passthrough, options, io) {
	await runPlan(createClientPlan(resolveTarget((await loadConfig(options.config)).config, {
		instance: options.instance,
		database: options.database,
		schema: options.schema,
		collection: options.collection
	}), passthrough), {
		io,
		verbose: true,
		printCommand: options.printCommand
	});
}
/**
* 执行或打印执行计划。
*
* @param plan 执行计划。
* @param options 执行选项。
* @returns 无返回值。
*/
async function runPlan(plan, options) {
	const resolvedPlan = resolvePlanTool(plan);
	if (options.verbose || options.printCommand) options.io.stdout(formatExecutionPlan(resolvedPlan));
	if (options.printCommand) return;
	if (resolvedPlan.sdk) {
		const result = await runSdkPlan(resolvedPlan.sdk);
		options.io.stdout(JSON.stringify(result, null, 2));
		return;
	}
	if (resolvedPlan.args.length === 0) {
		options.io.stdout(resolvedPlan.summary);
		return;
	}
	const result = spawnSync(resolvedPlan.tool, resolvedPlan.args, {
		env: {
			...process.env,
			...resolvedPlan.env
		},
		encoding: "utf8",
		stdio: "pipe"
	});
	if (result.stdout) options.io.stdout(result.stdout.trimEnd());
	if (result.stderr) options.io.stderr(result.stderr.trimEnd());
	if (result.error) throw new CliError(result.error.message);
	if (result.status && result.status !== 0) throw new CliError(`${resolvedPlan.tool} 退出码: ${result.status}`, result.status);
}
/**
* 将执行计划中的底层命令解析为当前环境可用命令。
*
* @param plan 原始执行计划。
* @returns 使用可用命令名的执行计划。
*/
function resolvePlanTool(plan) {
	if (plan.sdk || plan.args.length === 0) return plan;
	const result = probeTool(plan.tool);
	if (!result.command || result.command === plan.tool) return plan;
	return {
		...plan,
		tool: result.command
	};
}
/**
* 执行 SDK 计划。
*
* @param plan SDK 执行计划。
* @returns SDK 原始返回值。
*/
async function runSdkPlan(plan) {
	if (plan.provider === "milvus") return runMilvusPlan(plan);
	throw new CliError(`不支持的 SDK provider: ${plan.provider}`);
}
/**
* 执行 Milvus 只读 SDK 动作。
*
* @param plan Milvus SDK 执行计划。
* @returns Milvus SDK 返回值。
*/
async function runMilvusPlan(plan) {
	const { MilvusClient } = await import("@zilliz/milvus2-sdk-node").catch(() => {
		throw new CliError("缺少 @zilliz/milvus2-sdk-node。请在 skill 或项目环境安装该 SDK 后再执行 Milvus 动作。");
	});
	const client = new MilvusClient({
		address: plan.address,
		token: plan.token
	});
	if (plan.action === "list-collections") return client.showCollections();
	if (plan.action === "describe-collection") {
		requireCliValue(plan.collection, "Milvus describe-collection 需要 collection。");
		return client.describeCollection({ collection_name: plan.collection });
	}
	if (plan.action === "query") {
		requireCliValue(plan.collection, "Milvus query 需要 collection。");
		return client.query({
			collection_name: plan.collection,
			filter: plan.query,
			limit: plan.limit
		});
	}
	if (plan.action === "search") {
		requireCliValue(plan.collection, "Milvus search 需要 collection。");
		requireCliValue(plan.vector, "Milvus search 需要 --vector JSON 数组。");
		return client.search({
			collection_name: plan.collection,
			data: [JSON.parse(plan.vector)],
			filter: plan.query,
			limit: plan.limit
		});
	}
	throw new CliError(`不支持的 Milvus 动作: ${plan.action}`);
}
/**
* 格式化上下文快照。
*
* @param snapshot 脱敏上下文。
* @returns 人类可读文本。
*/
function formatContext(snapshot) {
	const lines = [`config: ${snapshot.configPath ?? "<unknown>"}`, `defaults: instance=${snapshot.defaults.defaultInstance ?? "<auto>"} limit=${snapshot.defaults.limit} maxLimit=${snapshot.defaults.maxLimit} level=${snapshot.defaults.permissionLevel}`];
	for (const instance of snapshot.instances) {
		lines.push(`- ${instance.id} (${instance.type}) defaultDatabase=${instance.defaultDatabase ?? "<auto>"} actions=${instance.allowedActions.join(", ")}`);
		for (const database of instance.databases) {
			const namespaces = [database.schemas?.length ? `schemas=${database.schemas.join(",")}` : "", database.collections?.length ? `collections=${database.collections.join(",")}` : ""].filter(Boolean).join(" ");
			lines.push(`  - ${database.name}${namespaces ? ` ${namespaces}` : ""}`);
		}
	}
	return lines.join("\n");
}
/**
* 执行配置元信息子命令。
*
* @param action 子动作名称。
* @param options CLI 选项。
* @param io 输出抽象。
* @returns 无返回值。
*/
async function runConfigCommand(action, options, io) {
	if (action === "paths") {
		const paths = getConfigSearchPaths();
		io.stdout(options.format === "json" ? JSON.stringify(paths, null, 2) : formatConfigPaths(paths));
		return;
	}
	if (action === "current") {
		const current = resolveCurrentConfigPath(options.config);
		io.stdout(options.format === "json" ? JSON.stringify(current, null, 2) : formatCurrentConfig(current));
		if (!current.path) throw new CliError("未找到配置文件。", 1);
		return;
	}
	if (action === "discover-databases") {
		const summary = await runDiscoverDatabases(options);
		io.stdout(options.format === "json" ? JSON.stringify(summary, null, 2) : formatDiscoverDatabasesSummary(summary));
		return;
	}
	throw new CliError(`不支持的 config action: ${action}`);
}
/**
* 格式化配置查找路径。
*
* @param paths 配置查找路径摘要。
* @returns 人类可读文本。
*/
function formatConfigPaths(paths) {
	return [
		"database-query config paths:",
		`projectDirectory: ${paths.projectDirectory}`,
		`globalDirectory: ${paths.globalDirectory}`,
		`globalLocalConfigPath: ${paths.globalLocalConfigPath}`,
		`filenames: ${paths.filenames.join(", ")}`,
		"searchOrder:",
		...paths.projectCandidates.map((path) => `- ${path}`),
		...paths.globalCandidates.map((path) => `- ${path}`)
	].join("\n");
}
/**
* 解析当前应使用的配置路径，不读取配置内容。
*
* @param configPath 显式配置文件路径。
* @returns 当前配置路径摘要。
*/
function resolveCurrentConfigPath(configPath) {
	const explicitPath = configPath ? resolve(configPath) : void 0;
	const resolvedPath = explicitPath ?? findDefaultConfigPath();
	const paths = getConfigSearchPaths();
	return {
		mode: explicitPath ? "explicit" : "default",
		path: resolvedPath,
		globalDirectory: paths.globalDirectory,
		globalLocalConfigPath: paths.globalLocalConfigPath,
		searchOrder: [...paths.projectCandidates, ...paths.globalCandidates]
	};
}
/**
* 格式化当前配置路径。
*
* @param current 当前配置路径摘要。
* @returns 人类可读文本。
*/
function formatCurrentConfig(current) {
	const lines = [
		"database-query config current:",
		`mode: ${current.mode}`,
		`path: ${current.path ?? "<not-found>"}`
	];
	if (!current.path) lines.push(`hint: 请提供 --config，或创建 ${current.globalLocalConfigPath}。`);
	return lines.join("\n");
}
/**
* 执行数据库候选发现命令。
*
* @param options CLI 配置子命令选项。
* @returns 发现与可选写回摘要。
*/
async function runDiscoverDatabases(options) {
	if (options.config && options.global) throw new CliError("--config 与 --global 只能选择一个。");
	const loaded = await loadConfig(options.global ? getGlobalLocalConfigPath() : options.config);
	const resolvedConfigPath = loaded.path;
	if (!resolvedConfigPath) throw new CliError("无法确定配置文件路径。");
	const instance = resolveTarget(loaded.config, { instance: options.instance }).instance;
	if (instance.type !== "postgres" && instance.type !== "mysql") throw new CliError(`config discover-databases 暂不支持 ${instance.type} 实例。首版仅支持 PostgreSQL 与 MySQL。`);
	const { plan, connectionDatabase } = createDiscoverDatabasesPlan(instance, options.database);
	const output = runDiscoveryPlan(plan);
	const discovered = filterSystemDatabases(instance.type, parseDatabaseListOutput(output));
	const selected = applyDatabaseFilters(discovered, {
		include: options.include,
		exclude: options.exclude
	});
	const summary = {
		configPath: resolvedConfigPath,
		instance: instance.id,
		type: instance.type,
		connectionDatabase,
		discovered,
		selected,
		write: Boolean(options.write)
	};
	if (options.write) {
		const writeResult = await writeDiscoveredDatabases({
			configPath: resolvedConfigPath,
			instanceId: instance.id,
			databases: selected,
			connectionDatabase
		});
		summary.backupPath = writeResult.backupPath;
		summary.updatedPath = writeResult.updatedPath;
	}
	return summary;
}
/**
* 创建关系型数据库候选发现执行计划。
*
* @param instance 数据库实例。
* @param explicitDatabase PostgreSQL 发现连接库覆盖值。
* @returns 执行计划与实际连接库。
*/
function createDiscoverDatabasesPlan(instance, explicitDatabase) {
	if (instance.type === "postgres") {
		const connectionDatabase = explicitDatabase ?? instance.defaultDatabase ?? "postgres";
		const args = [
			...optionalArgPair("-h", instance.host),
			...optionalArgPair("-p", instance.port?.toString()),
			...optionalArgPair("-U", instance.username),
			"-d",
			connectionDatabase,
			"-A",
			"-t",
			"-c",
			"select datname from pg_database where not datistemplate order by datname;"
		];
		return {
			connectionDatabase,
			plan: {
				tool: "psql",
				args,
				displayArgs: args,
				env: instance.password ? { PGPASSWORD: instance.password } : {},
				displayEnv: instance.password ? { PGPASSWORD: "<redacted>" } : {},
				summary: `PostgreSQL ${instance.id} discover databases`
			}
		};
	}
	const args = [
		...optionalArgPair("--host", instance.host),
		...optionalArgPair("--port", instance.port?.toString()),
		...optionalArgPair("--user", instance.username),
		"--batch",
		"--skip-column-names",
		"--execute",
		"SHOW DATABASES;"
	];
	return { plan: {
		tool: "mysql",
		args,
		displayArgs: args,
		env: instance.password ? { MYSQL_PWD: instance.password } : {},
		displayEnv: instance.password ? { MYSQL_PWD: "<redacted>" } : {},
		summary: `MySQL ${instance.id} discover databases`
	} };
}
/**
* 执行数据库发现计划并返回 stdout。
*
* @param plan 执行计划。
* @param runner 进程执行抽象，便于测试替换。
* @returns 底层客户端 stdout。
*/
function runDiscoveryPlan(plan, runner = runProcess) {
	const resolvedPlan = resolvePlanTool(plan);
	const result = runner(resolvedPlan.tool, resolvedPlan.args, {
		...process.env,
		...resolvedPlan.env
	});
	if (result.error) throw new CliError(result.error.message);
	if (result.status && result.status !== 0) {
		const stderr = result.stderr.trim();
		throw new CliError(`${resolvedPlan.tool} 退出码: ${result.status}${stderr ? `\n${stderr}` : ""}`, result.status);
	}
	return result.stdout;
}
/**
* 执行底层进程并捕获输出。
*
* @param command 命令名。
* @param args 参数列表。
* @param env 子进程环境变量。
* @returns 进程执行结果。
*/
function runProcess(command, args, env) {
	const result = spawnSync(command, args, {
		env,
		encoding: "utf8",
		stdio: "pipe"
	});
	return {
		status: result.status,
		stdout: result.stdout ?? "",
		stderr: result.stderr ?? "",
		error: result.error
	};
}
/**
* 解析底层客户端输出中的数据库名称。
*
* @param output 底层客户端 stdout。
* @returns 去重排序后的数据库名称。
*/
function parseDatabaseListOutput(output) {
	return uniqueSorted(output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean));
}
/**
* 过滤数据库类型对应的系统库。
*
* @param type 数据库类型。
* @param databases 原始数据库名称。
* @returns 过滤系统库后的数据库名称。
*/
function filterSystemDatabases(type, databases) {
	const excluded = type === "postgres" ? new Set(["template0", "template1"]) : new Set([
		"information_schema",
		"mysql",
		"performance_schema",
		"sys"
	]);
	return databases.filter((database) => !excluded.has(database));
}
/**
* 按 include / exclude glob 过滤数据库名称。
*
* @param databases 数据库名称列表。
* @param options 过滤参数。
* @returns 过滤后的数据库名称。
*/
function applyDatabaseFilters(databases, options) {
	const include = parsePatternList(options.include);
	const exclude = parsePatternList(options.exclude);
	return databases.filter((database) => {
		const included = include.length === 0 || include.some((pattern) => matchesGlob(database, pattern));
		const excluded = exclude.some((pattern) => matchesGlob(database, pattern));
		return included && !excluded;
	});
}
/**
* 将发现到的数据库合并写回本机 local JSON 配置。
*
* @param options 写回参数。
* @returns 备份路径和更新路径。
*/
async function writeDiscoveredDatabases(options) {
	assertWritableLocalJsonConfig(options.configPath);
	const rawContent = readFileSync(options.configPath, "utf8");
	const updatedConfig = mergeDiscoveredDatabasesIntoConfig(JSON.parse(rawContent), {
		instanceId: options.instanceId,
		databases: options.databases,
		connectionDatabase: options.connectionDatabase
	});
	const backupPath = createBackupPath(options.configPath);
	await writeFile(backupPath, rawContent, {
		flag: "wx",
		mode: 384
	});
	await writeFile(options.configPath, `${JSON.stringify(updatedConfig, null, 2)}\n`);
	return {
		backupPath,
		updatedPath: options.configPath
	};
}
/**
* 合并发现到的数据库到配置对象。
*
* @param config 原始配置对象。
* @param options 合并参数。
* @returns 合并后的配置对象。
*/
function mergeDiscoveredDatabasesIntoConfig(config, options) {
	const instances = config.instances.map((instance) => {
		if (instance.id !== options.instanceId) return instance;
		const byName = /* @__PURE__ */ new Map();
		for (const database of instance.databases ?? []) byName.set(database.name, database);
		for (const database of options.databases) if (!byName.has(database)) byName.set(database, { name: database });
		const updated = {
			...instance,
			databases: [...byName.values()].sort((left, right) => left.name.localeCompare(right.name))
		};
		if (!updated.defaultDatabase && options.connectionDatabase && options.databases.includes(options.connectionDatabase)) updated.defaultDatabase = options.connectionDatabase;
		return updated;
	});
	return {
		...config,
		instances
	};
}
/**
* 校验配置文件是否允许自动写回。
*
* @param configPath 配置文件路径。
* @returns 无返回值。
*/
function assertWritableLocalJsonConfig(configPath) {
	if (!basename(configPath).endsWith(".local.json")) throw new CliError(`自动写回只支持 *.local.json 本机私有配置: ${configPath}`);
}
/**
* 创建同目录配置备份路径。
*
* @param configPath 配置文件路径。
* @returns 不存在的备份文件路径。
*/
function createBackupPath(configPath) {
	const timestamp = formatLocalTimestamp(/* @__PURE__ */ new Date());
	let candidate = `${configPath}.${timestamp}.bak`;
	let index = 1;
	while (existsSync(candidate)) {
		candidate = `${configPath}.${timestamp}-${index}.bak`;
		index += 1;
	}
	return candidate;
}
/**
* 格式化本地时间戳用于备份文件名。
*
* @param date 时间对象。
* @returns `YYYY-MM-DD_HH-mm-ss` 格式时间戳。
*/
function formatLocalTimestamp(date) {
	const pad = (value) => value.toString().padStart(2, "0");
	return [
		date.getFullYear(),
		"-",
		pad(date.getMonth() + 1),
		"-",
		pad(date.getDate()),
		"_",
		pad(date.getHours()),
		"-",
		pad(date.getMinutes()),
		"-",
		pad(date.getSeconds())
	].join("");
}
/**
* 格式化数据库发现摘要。
*
* @param summary 发现摘要。
* @returns 人类可读文本。
*/
function formatDiscoverDatabasesSummary(summary) {
	const lines = [
		"database-query config discover-databases:",
		`configPath: ${summary.configPath}`,
		`instance: ${summary.instance}`,
		`type: ${summary.type}`,
		`connectionDatabase: ${summary.connectionDatabase ?? "<none>"}`,
		`discovered: ${summary.discovered.length ? summary.discovered.join(", ") : "<none>"}`,
		`selected: ${summary.selected.length ? summary.selected.join(", ") : "<none>"}`,
		`write: ${summary.write ? "yes" : "no"}`
	];
	if (summary.backupPath) lines.push(`backupPath: ${summary.backupPath}`);
	if (summary.updatedPath) lines.push(`updatedPath: ${summary.updatedPath}`);
	if (!summary.write) lines.push("hint: 传 --write 写回本机 *.local.json 配置。");
	return lines.join("\n");
}
/**
* 拆分逗号分隔的 glob 模式。
*
* @param value CLI 输入。
* @returns 模式列表。
*/
function parsePatternList(value) {
	return (value ?? "").split(",").map((item) => item.trim()).filter(Boolean);
}
/**
* 判断文本是否匹配简单 glob。
*
* @param value 待匹配文本。
* @param pattern glob 模式，支持 `*` 与 `?`。
* @returns 匹配时返回 true。
*/
function matchesGlob(value, pattern) {
	return new RegExp(`^${pattern.split("").map((char) => {
		if (char === "*") return ".*";
		if (char === "?") return ".";
		return char.replace(/[\\^$+?.()|[\]{}]/g, "\\$&");
	}).join("")}$`).test(value);
}
/**
* 对字符串列表去重排序。
*
* @param values 原始字符串列表。
* @returns 去重排序后的列表。
*/
function uniqueSorted(values) {
	return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}
/**
* 按存在性添加命令参数键值对。
*
* @param key 参数名。
* @param value 参数值。
* @returns 参数片段。
*/
function optionalArgPair(key, value) {
	return value ? [key, value] : [];
}
/**
* 格式化 doctor 检查结果。
*
* @returns doctor 文本。
*/
async function formatDoctor() {
	const tools = [
		"psql",
		"mysql",
		"sqlite3",
		"mongosh",
		"redis-cli"
	];
	const lines = ["database-query doctor:", "install policy: 不自动安装底层客户端；agent 应根据当前平台、权限和 PATH 自行选择安装方式。"];
	for (const tool of tools) {
		const result = probeTool(tool);
		if (result.command) lines.push(`- ${tool}: ok (${result.origin}) command=${result.command}${result.version ? ` version="${result.version}"` : ""}`);
		else {
			lines.push(`- ${tool}: missing`);
			lines.push(...formatInstallHints(tool));
		}
	}
	const milvusSdkAvailable = await hasMilvusSdk();
	lines.push(`- @zilliz/milvus2-sdk-node: ${milvusSdkAvailable ? "ok" : "missing"} (Milvus exec actions)`);
	if (!milvusSdkAvailable) lines.push(...formatInstallHints("@zilliz/milvus2-sdk-node"));
	lines.push("install reference: references/client-installation.md");
	return lines.join("\n");
}
/**
* 探测底层客户端命令，WSL 场景下原生命令缺失时尝试 `.exe`。
*
* @param name 客户端命令基础名称。
* @param runner 命令执行抽象，便于测试模拟 PATH。
* @returns 客户端探测结果。
*/
function probeTool(name, runner = runToolVersion) {
	const nativeResult = runner(name, ["--version"]);
	if (nativeResult.ok) return {
		name,
		command: name,
		origin: "native",
		version: firstOutputLine(nativeResult.output)
	};
	const windowsCommand = `${name}.exe`;
	const windowsResult = runner(windowsCommand, ["--version"]);
	if (windowsResult.ok) return {
		name,
		command: windowsCommand,
		origin: "windows-exe",
		version: firstOutputLine(windowsResult.output)
	};
	return { name };
}
/**
* 运行客户端版本命令。
*
* @param command 客户端命令。
* @param args 命令参数。
* @returns 命令是否可运行及版本输出。
*/
function runToolVersion(command, args) {
	const result = spawnSync(command, args, {
		encoding: "utf8",
		stdio: "pipe"
	});
	return {
		ok: !result.error && result.status === 0,
		output: result.stdout || result.stderr || void 0
	};
}
/**
* 获取命令输出第一行。
*
* @param output 原始命令输出。
* @returns 去空白后的第一行。
*/
function firstOutputLine(output) {
	return output?.split(/\r?\n/).map((line) => line.trim()).find(Boolean);
}
/**
* 检查 Milvus Node SDK 是否可动态加载。
*
* @returns SDK 可用时返回 true。
*/
async function hasMilvusSdk() {
	const sdkName = "@zilliz/milvus2-sdk-node";
	try {
		await import(sdkName);
		return true;
	} catch {
		return false;
	}
}
/**
* 返回带缩进的工具安装提示。
*
* @param tool 工具名。
* @returns 安装提示行。
*/
function formatInstallHints(tool) {
	return {
		psql: [
			"  install: Windows: winget install PostgreSQL.PostgreSQL 或 scoop install postgresql",
			"  install: macOS: brew install libpq",
			"  install: Debian/Ubuntu: sudo apt-get install postgresql-client"
		],
		mysql: [
			"  install: Windows: winget install Oracle.MySQL 或 scoop install mysql",
			"  install: macOS: brew install mysql-client",
			"  install: Debian/Ubuntu: sudo apt-get install mysql-client"
		],
		sqlite3: [
			"  install: Windows: winget install SQLite.SQLite 或 scoop install sqlite",
			"  install: macOS: brew install sqlite",
			"  install: Debian/Ubuntu: sudo apt-get install sqlite3"
		],
		mongosh: [
			"  install: Windows: winget install MongoDB.Shell 或 scoop install mongosh",
			"  install: macOS: brew install mongosh",
			"  install: Debian/Ubuntu: 按 MongoDB 官方仓库安装 mongodb-mongosh"
		],
		"redis-cli": [
			"  install: Windows: 优先使用 WSL/容器内 redis-tools，或 scoop install redis",
			"  install: macOS: brew install redis",
			"  install: Debian/Ubuntu: sudo apt-get install redis-tools"
		],
		"@zilliz/milvus2-sdk-node": ["  install: 在运行 database-query.js 的 skill/项目目录安装 @zilliz/milvus2-sdk-node", "  install: pnpm add @zilliz/milvus2-sdk-node 或 npm install @zilliz/milvus2-sdk-node"]
	}[tool] ?? ["  install: 查看 references/client-installation.md"];
}
/**
* 校验 CLI 必填字符串。
*
* @param value 待校验值。
* @param message 缺失时报错消息。
* @returns 无返回值。
*/
function requireCliValue(value, message) {
	if (!value) throw new CliError(message);
}
/**
* 从 `--sql` 或 `--file` 读取待检查 SQL。
*
* @param options CLI 选项。
* @returns SQL 文本。
*/
function readSqlInput(options) {
	if (options.sql && options.file) throw new CliError("只能指定 --sql 或 --file 其中一个。");
	if (options.sql) return options.sql;
	if (options.file) return readFileSync(options.file, "utf8");
	throw new CliError("请通过 --sql 或 --file 提供 SQL。");
}
/**
* 解析并校验 SQL 方言。
*
* @param value CLI 输入的方言名称。
* @returns 受支持的 SQL 方言。
*/
function parseDialect(value) {
	if (!DIALECTS.has(value)) throw new CliError(`不支持的 dialect: ${value}`);
	return value;
}
/**
* 解析并校验权限层级。
*
* @param value CLI 输入的权限层级。
* @returns 受支持的权限层级。
*/
function parseLevel(value) {
	if (!LEVELS.has(value)) throw new CliError(`不支持的 level: ${value}`);
	return value;
}
/**
* 解析正整数参数。
*
* @param value CLI 输入的数字文本。
* @param label 参数名。
* @returns 正整数。
*/
function parsePositiveInteger(value, label) {
	const parsed = Number.parseInt(value, 10);
	if (!Number.isInteger(parsed) || parsed <= 0) throw new CliError(`--${label} 必须是正整数。`);
	return parsed;
}
/**
* 让 cac 内置 help 使用当前 IO 抽象。
*
* @param cli cac CLI。
* @param io 输出抽象。
* @returns cac CLI。
*/
function patchHelpOutput(cli, io) {
	const originalOutputHelp = cli.outputHelp.bind(cli);
	cli.outputHelp = () => {
		const originalLog = console.log;
		console.log = (...values) => io.stdout(values.map(String).join(" "));
		try {
			originalOutputHelp();
		} finally {
			console.log = originalLog;
		}
	};
	return cli;
}
/**
* 提取 client 子命令 `--` 后透传参数。
*
* @param argv 原始 CLI 参数。
* @returns 透传参数；非 client 或未透传时返回 undefined。
*/
function extractClientPassthrough(argv) {
	if (argv[0] !== "client") return;
	const separatorIndex = argv.indexOf("--");
	if (separatorIndex < 0) return;
	return argv.slice(separatorIndex + 1);
}
/**
* 判断 cac help 抛出的退出信号。
*
* @param error 捕获的错误。
* @returns 是 help 退出信号时返回 true。
*/
function isHelpError(error) {
	return Boolean(error && typeof error === "object" && "message" in error && String(error.message).includes("CACError"));
}
/**
* 创建默认 CLI IO。
*
* @returns 使用原始 console 输出函数的 IO 抽象。
*/
function defaultIo() {
	return {
		stdout: DEFAULT_STDOUT,
		stderr: DEFAULT_STDERR
	};
}

//#endregion
//#region src/database-query.ts
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) process.exitCode = await runCli(process.argv.slice(2));

//#endregion
export {  };
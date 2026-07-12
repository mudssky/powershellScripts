#!/usr/bin/env node
import { basename, dirname, join, relative, resolve } from "node:path";
import { access, appendFile, copyFile, mkdir, readFile, readdir, rename, stat, writeFile } from "node:fs/promises";
import { constants, existsSync } from "node:fs";
import { createConnection } from "node:net";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";

//#region ../../../../node_modules/.pnpm/cac@7.0.0/node_modules/cac/dist/index.js
function toArr(any) {
	return any == null ? [] : Array.isArray(any) ? any : [any];
}
function toVal(out, key, val, opts) {
	var x, old = out[key], nxt = !!~opts.string.indexOf(key) ? val == null || val === true ? "" : String(val) : typeof val === "boolean" ? val : !!~opts.boolean.indexOf(key) ? val === "false" ? false : val === "true" || (out._.push((x = +val, x * 0 === 0) ? x : val), !!val) : (x = +val, x * 0 === 0) ? x : val;
	out[key] = old == null ? nxt : Array.isArray(old) ? old.concat(nxt) : [old, nxt];
}
function lib_default(args, opts) {
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
function removeBrackets(v) {
	return v.replace(/[<[].+/, "").trim();
}
function findAllBrackets(v) {
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
}
function getMriOptions(options) {
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
}
function findLongest(arr) {
	return arr.sort((a, b) => {
		return a.length > b.length ? -1 : 1;
	})[0];
}
function padRight(str, length) {
	return str.length >= length ? str : `${str}${" ".repeat(length - str.length)}`;
}
function camelcase(input) {
	return input.replaceAll(/([a-z])-([a-z])/g, (_, p1, p2) => {
		return p1 + p2.toUpperCase();
	});
}
function setDotProp(obj, keys, val) {
	let current = obj;
	for (let i = 0; i < keys.length; i++) {
		const key = keys[i];
		if (i === keys.length - 1) {
			current[key] = val;
			return;
		}
		if (current[key] == null) {
			const nextKeyIsArrayIndex = +keys[i + 1] > -1;
			current[key] = nextKeyIsArrayIndex ? [] : {};
		}
		current = current[key];
	}
}
function setByType(obj, transforms) {
	for (const key of Object.keys(transforms)) {
		const transform = transforms[key];
		if (transform.shouldTransform) {
			obj[key] = [obj[key]].flat();
			if (typeof transform.transformFunction === "function") obj[key] = obj[key].map(transform.transformFunction);
		}
	}
}
function getFileName(input) {
	const m = /([^\\/]+)$/.exec(input);
	return m ? m[1] : "";
}
function camelcaseOptionName(name) {
	return name.split(".").map((v, i) => {
		return i === 0 ? camelcase(v) : v;
	}).join(".");
}
var CACError = class extends Error {
	constructor(message) {
		super(message);
		this.name = "CACError";
		if (typeof Error.captureStackTrace !== "function") this.stack = new Error(message).stack;
	}
};
var Option = class {
	rawName;
	description;
	/** Option name */
	name;
	/** Option name and aliases */
	names;
	isBoolean;
	required;
	config;
	negated;
	constructor(rawName, description, config) {
		this.rawName = rawName;
		this.description = description;
		this.config = Object.assign({}, config);
		rawName = rawName.replaceAll(".*", "");
		this.negated = false;
		this.names = removeBrackets(rawName).split(",").map((v) => {
			let name = v.trim().replace(/^-{1,2}/, "");
			if (name.startsWith("no-")) {
				this.negated = true;
				name = name.replace(/^no-/, "");
			}
			return camelcaseOptionName(name);
		}).sort((a, b) => a.length > b.length ? 1 : -1);
		this.name = this.names.at(-1);
		if (this.negated && this.config.default == null) this.config.default = true;
		if (rawName.includes("<")) this.required = true;
		else if (rawName.includes("[")) this.required = false;
		else this.isBoolean = true;
	}
};
let runtimeProcessArgs;
let runtimeInfo;
if (typeof process !== "undefined") {
	let runtimeName;
	if (typeof Deno !== "undefined" && typeof Deno.version?.deno === "string") runtimeName = "deno";
	else if (typeof Bun !== "undefined" && typeof Bun.version === "string") runtimeName = "bun";
	else runtimeName = "node";
	runtimeInfo = `${process.platform}-${process.arch} ${runtimeName}-${process.version}`;
	runtimeProcessArgs = process.argv;
} else if (typeof navigator === "undefined") runtimeInfo = `unknown`;
else runtimeInfo = `${navigator.platform} ${navigator.userAgent}`;
var Command = class {
	rawName;
	description;
	config;
	cli;
	options;
	aliasNames;
	name;
	args;
	commandAction;
	usageText;
	versionNumber;
	examples;
	helpCallback;
	globalCommand;
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
	/**
	* Add a option for this command
	* @param rawName Raw option name(s)
	* @param description Option description
	* @param config Option config
	*/
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
	/**
	* Check if a command name is matched by this command
	* @param name Command name
	*/
	isMatched(name) {
		return this.name === name || this.aliasNames.includes(name);
	}
	get isDefaultCommand() {
		return this.name === "" || this.aliasNames.includes("!");
	}
	get isGlobalCommand() {
		return this instanceof GlobalCommand;
	}
	/**
	* Check if an option is registered in this command
	* @param name Option name
	*/
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
			}, {
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
		console.info(sections.map((section) => {
			return section.title ? `${section.title}:\n${section.body}` : section.body;
		}).join("\n\n"));
	}
	outputVersion() {
		const { name } = this.cli;
		const { versionNumber } = this.cli.globalCommand;
		if (versionNumber) console.info(`${name}/${versionNumber} ${runtimeInfo}`);
	}
	checkRequiredArgs() {
		const minimalArgsCount = this.args.filter((arg) => arg.required).length;
		if (this.cli.args.length < minimalArgsCount) throw new CACError(`missing required args for command \`${this.rawName}\``);
	}
	/**
	* Check if the parsed options contain any unknown options
	*
	* Exit and output error when true
	*/
	checkUnknownOptions() {
		const { options, globalCommand } = this.cli;
		if (!this.config.allowUnknownOptions) {
			for (const name of Object.keys(options)) if (name !== "--" && !this.hasOption(name) && !globalCommand.hasOption(name)) throw new CACError(`Unknown option \`${name.length > 1 ? `--${name}` : `-${name}`}\``);
		}
	}
	/**
	* Check if the required string-type options exist
	*/
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
	/**
	* Check if the number of args is more than expected
	*/
	checkUnusedArgs() {
		const maximumArgsCount = this.args.some((arg) => arg.variadic) ? Infinity : this.args.length;
		if (maximumArgsCount < this.cli.args.length) throw new CACError(`Unused args: ${this.cli.args.slice(maximumArgsCount).map((arg) => `\`${arg}\``).join(", ")}`);
	}
};
var GlobalCommand = class extends Command {
	constructor(cli) {
		super("@@global@@", "", {}, cli);
	}
};
var CAC = class extends EventTarget {
	/** The program name to display in help and version message */
	name;
	commands;
	globalCommand;
	matchedCommand;
	matchedCommandName;
	/**
	* Raw CLI arguments
	*/
	rawArgs;
	/**
	* Parsed CLI arguments
	*/
	args;
	/**
	* Parsed CLI options, camelCased
	*/
	options;
	showHelpOnExit;
	showVersionOnExit;
	/**
	* @param name The program name to display in help and version message
	*/
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
	/**
	* Add a global usage text.
	*
	* This is not used by sub-commands.
	*/
	usage(text) {
		this.globalCommand.usage(text);
		return this;
	}
	/**
	* Add a sub-command
	*/
	command(rawName, description, config) {
		const command = new Command(rawName, description || "", config, this);
		command.globalCommand = this.globalCommand;
		this.commands.push(command);
		return command;
	}
	/**
	* Add a global CLI option.
	*
	* Which is also applied to sub-commands.
	*/
	option(rawName, description, config) {
		this.globalCommand.option(rawName, description, config);
		return this;
	}
	/**
	* Show help message when `-h, --help` flags appear.
	*
	*/
	help(callback) {
		this.globalCommand.option("-h, --help", "Display this message");
		this.globalCommand.helpCallback = callback;
		this.showHelpOnExit = true;
		return this;
	}
	/**
	* Show version number when `-v, --version` flags appear.
	*
	*/
	version(version, customFlags = "-v, --version") {
		this.globalCommand.version(version, customFlags);
		this.showVersionOnExit = true;
		return this;
	}
	/**
	* Add a global example.
	*
	* This example added here will not be used by sub-commands.
	*/
	example(example) {
		this.globalCommand.example(example);
		return this;
	}
	/**
	* Output the corresponding help message
	* When a sub-command is matched, output the help message for the command
	* Otherwise output the global one.
	*
	*/
	outputHelp() {
		if (this.matchedCommand) this.matchedCommand.outputHelp();
		else this.globalCommand.outputHelp();
	}
	/**
	* Output the version number.
	*
	*/
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
	/**
	* Parse argv
	*/
	parse(argv, { run = true } = {}) {
		if (!argv) {
			if (!runtimeProcessArgs) throw new Error("No argv provided and runtime process argv is not available.");
			argv = runtimeProcessArgs;
		}
		this.rawArgs = argv;
		if (!this.name) this.name = argv[1] ? getFileName(argv[1]) : "cli";
		let shouldParse = true;
		for (const command of this.commands) {
			const parsed = this.mri(argv.slice(2), command);
			const commandName = parsed.args[0];
			if (command.isMatched(commandName)) {
				shouldParse = false;
				const parsedInfo = {
					...parsed,
					args: parsed.args.slice(1)
				};
				this.setParsedInfo(parsedInfo, command, commandName);
				this.dispatchEvent(new CustomEvent(`command:${commandName}`, { detail: command }));
			}
		}
		if (shouldParse) {
			for (const command of this.commands) if (command.isDefaultCommand) {
				shouldParse = false;
				const parsed = this.mri(argv.slice(2), command);
				this.setParsedInfo(parsed, command);
				this.dispatchEvent(new CustomEvent("command:!", { detail: command }));
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
		if (!this.matchedCommand && this.args[0]) this.dispatchEvent(new CustomEvent("command:*", { detail: this.args[0] }));
		return parsedArgv;
	}
	mri(argv, command) {
		const cliOptions = [...this.globalCommand.options, ...command ? command.options : []];
		const mriOptions = getMriOptions(cliOptions);
		let argsAfterDoubleDashes = [];
		const doubleDashesIndex = argv.indexOf("--");
		if (doubleDashesIndex !== -1) {
			argsAfterDoubleDashes = argv.slice(doubleDashesIndex + 1);
			argv = argv.slice(0, doubleDashesIndex);
		}
		let parsed = lib_default(argv, mriOptions);
		parsed = Object.keys(parsed).reduce((res, name) => {
			return {
				...res,
				[camelcaseOptionName(name)]: parsed[name]
			};
		}, { _: [] });
		const args = parsed._;
		const options = { "--": argsAfterDoubleDashes };
		const ignoreDefault = command && command.config.ignoreOptionDefaultValue ? command.config.ignoreOptionDefaultValue : this.globalCommand.config.ignoreOptionDefaultValue;
		const transforms = Object.create(null);
		for (const cliOption of cliOptions) {
			if (!ignoreDefault && cliOption.config.default !== void 0) for (const name of cliOption.names) options[name] = cliOption.config.default;
			if (Array.isArray(cliOption.config.type) && transforms[cliOption.name] === void 0) {
				transforms[cliOption.name] = Object.create(null);
				transforms[cliOption.name].shouldTransform = true;
				transforms[cliOption.name].transformFunction = cliOption.config.type[0];
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
		command.checkUnusedArgs();
		const actionArgs = [];
		command.args.forEach((arg, index) => {
			if (arg.variadic) actionArgs.push(args.slice(index));
			else actionArgs.push(args[index]);
		});
		actionArgs.push(options);
		return command.commandAction.apply(this, actionArgs);
	}
};
/**
* @param name The program name to display in help and version message
*/
const cac = (name = "") => new CAC(name);

//#endregion
//#region src/types.ts
var CliError = class extends Error {
	code;
	exitCode;
	/**
	* 创建可映射到 CLI 退出码的错误。
	*
	* @param code 诊断代码。
	* @param message 面向用户的错误消息。
	* @param exitCode CLI 退出码。
	*/
	constructor(code, message, exitCode = 1) {
		super(message);
		this.name = "CliError";
		this.code = code;
		this.exitCode = exitCode;
	}
};

//#endregion
//#region src/config.ts
const PROJECT_LOCAL_CONFIG = "project-launch.local.json";
const PROJECT_SHARED_CONFIG = "project-launch.config.json";
const GLOBAL_CONFIG_DIR = "project-launcher";
/**
* 返回项目级配置候选路径。
*
* @param projectRoot 项目根目录。
* @returns 按优先级排列的配置文件路径。
*/
function getProjectConfigCandidates(projectRoot) {
	return [join(projectRoot, PROJECT_LOCAL_CONFIG), join(projectRoot, PROJECT_SHARED_CONFIG)];
}
/**
* 返回用户级本机配置路径。
*
* @param env 环境变量集合。
* @returns XDG 或 home 下的用户级 local JSON 路径。
*/
function getGlobalLocalConfigPath(env = process.env) {
	return join(env.XDG_CONFIG_HOME && env.XDG_CONFIG_HOME.trim().length > 0 ? env.XDG_CONFIG_HOME : join(env.HOME ?? process.cwd(), ".config"), GLOBAL_CONFIG_DIR, PROJECT_LOCAL_CONFIG);
}
/**
* 读取配置文件；没有配置时返回空配置。
*
* @param projectRoot 项目根目录。
* @param options 显式配置路径和环境变量。
* @returns 已加载配置及命中来源。
*/
async function loadConfig(projectRoot, options = {}) {
	if (options.configPath) {
		const configPath = resolve(projectRoot, options.configPath);
		return {
			path: configPath,
			config: await readConfigFile(configPath),
			source: "explicit"
		};
	}
	for (const candidate of getProjectConfigCandidates(projectRoot)) if (await exists(candidate)) return {
		path: candidate,
		config: await readConfigFile(candidate),
		source: candidate.endsWith(PROJECT_LOCAL_CONFIG) ? "project-local" : "project-config"
	};
	const globalConfigPath = getGlobalLocalConfigPath(options.env);
	if (await exists(globalConfigPath)) return {
		path: globalConfigPath,
		config: await readConfigFile(globalConfigPath),
		source: "global-local"
	};
	return {
		config: {},
		source: "none"
	};
}
/**
* 读取并解析 JSON 配置。
*
* @param configPath 配置文件路径。
* @returns 解析后的配置。
*/
async function readConfigFile(configPath) {
	try {
		const raw = await readFile(configPath, "utf8");
		return resolveEnvPlaceholders(JSON.parse(raw));
	} catch (error) {
		if (error instanceof SyntaxError) throw new CliError("CONFIG_PARSE_ERROR", `配置文件不是有效 JSON: ${configPath}`);
		throw error;
	}
}
/**
* 把 `${env:NAME}` 占位符替换为环境变量值。
*
* @param value 任意 JSON 值。
* @param env 环境变量集合。
* @returns 替换后的 JSON 值。
*/
function resolveEnvPlaceholders(value, env = process.env) {
	if (typeof value === "string") return value.replace(/\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, name) => {
		return env[name] ?? "";
	});
	if (Array.isArray(value)) return value.map((item) => resolveEnvPlaceholders(item, env));
	if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, resolveEnvPlaceholders(entry, env)]));
	return value;
}
/**
* 写入或更新本机私有服务配置。
*
* @param projectRoot 项目根目录。
* @param service 要保存的服务配置。
* @param options 是否覆盖已有同名服务。
* @returns 写入路径和备份路径。
*/
async function saveServiceToLocalConfig(projectRoot, service, options = {}) {
	const configPath = join(projectRoot, PROJECT_LOCAL_CONFIG);
	const existing = await exists(configPath) ? await readConfigFile(configPath) : {};
	const services = existing.services ?? [];
	const serviceIndex = services.findIndex((item) => item.name === service.name);
	if (serviceIndex >= 0 && !options.overwrite) throw new CliError("CONFIG_PARSE_ERROR", `本机配置已存在同名服务: ${service.name}。需要覆盖时传 --overwrite。`);
	const nextServices = [...services];
	if (serviceIndex >= 0) nextServices[serviceIndex] = service;
	else nextServices.push(service);
	const nextConfig = {
		...existing,
		services: nextServices
	};
	await mkdir(dirname(configPath), { recursive: true });
	const backupPath = await exists(configPath) ? await backupFile(configPath, options.now) : void 0;
	const tempPath = `${configPath}.tmp`;
	await writeFile(tempPath, `${JSON.stringify(nextConfig, null, 2)}\n`, "utf8");
	await rename(tempPath, configPath);
	return {
		configPath,
		backupPath
	};
}
/**
* 创建同目录时间戳备份。
*
* @param filePath 待备份文件。
* @param now 当前时间，测试可注入。
* @returns 备份文件路径。
*/
async function backupFile(filePath, now = /* @__PURE__ */ new Date()) {
	const backupPath = `${filePath}.${formatBackupTimestamp(now)}.bak`;
	await copyFile(filePath, backupPath);
	return backupPath;
}
/**
* 格式化备份时间戳。
*
* @param value 当前时间。
* @returns 适合文件名的本地时间戳。
*/
function formatBackupTimestamp(value) {
	const pad = (input) => String(input).padStart(2, "0");
	return [
		value.getFullYear(),
		pad(value.getMonth() + 1),
		pad(value.getDate())
	].join("-") + "_" + [
		pad(value.getHours()),
		pad(value.getMinutes()),
		pad(value.getSeconds())
	].join("-");
}
/**
* 判断路径是否存在。
*
* @param filePath 目标路径。
* @returns 存在时为 true。
*/
async function exists(filePath) {
	try {
		await stat(filePath);
		return true;
	} catch {
		return false;
	}
}
/**
* 脱敏环境变量输出。
*
* @param env 服务环境变量。
* @returns 适合展示的环境变量。
*/
function redactEnv(env) {
	return Object.fromEntries(Object.entries(env).map(([key, value]) => [key, isSensitiveKey(key) ? "<redacted>" : value]));
}
/**
* 判断变量名是否可能包含敏感值。
*
* @param key 环境变量名。
* @returns 敏感变量返回 true。
*/
function isSensitiveKey(key) {
	return /(password|passwd|token|secret|key|cookie|credential|dsn|uri|url)/i.test(key);
}

//#endregion
//#region src/doctor.ts
/**
* 检查启动计划依赖。
*
* @param plan 启动计划。
* @param options 命令执行器和依赖配置。
* @returns 诊断列表。
*/
async function diagnosePlan(plan, options) {
	const diagnostics = [];
	diagnostics.push(...await diagnoseRequiredTools(plan.projectRoot, options.runner));
	diagnostics.push(...await diagnosePorts(plan.services));
	diagnostics.push(...await diagnoseDependencies(options.dependencies ?? [], options.runner));
	return diagnostics;
}
/**
* 检查 tmux、java 和构建工具。
*
* @param projectRoot 项目根目录。
* @param runner 命令执行器。
* @returns 诊断列表。
*/
async function diagnoseRequiredTools(projectRoot, runner) {
	const diagnostics = [];
	for (const tool of [{
		command: "tmux",
		args: ["-V"],
		code: "TMUX_MISSING"
	}, {
		command: "java",
		args: ["-version"],
		code: "JAVA_MISSING"
	}]) {
		const result = await runner.run(tool.command, tool.args, { cwd: projectRoot });
		if (result.exitCode !== 0) diagnostics.push({
			code: tool.code,
			level: "error",
			target: tool.command,
			message: `缺少必要命令: ${tool.command}`,
			detail: result.stderr || result.stdout
		});
	}
	const hasMavenWrapper = await canAccess(join(projectRoot, "mvnw"));
	const hasGradleWrapper = await canAccess(join(projectRoot, "gradlew"));
	if (!hasMavenWrapper && !hasGradleWrapper) {
		const maven = await runner.run("mvn", ["-v"], { cwd: projectRoot });
		const gradle = await runner.run("gradle", ["-v"], { cwd: projectRoot });
		if (maven.exitCode !== 0 && gradle.exitCode !== 0) diagnostics.push({
			code: "BUILD_TOOL_MISSING",
			level: "error",
			message: "未找到 Maven/Gradle wrapper，也未找到全局 mvn 或 gradle。"
		});
	}
	return diagnostics;
}
/**
* 检查服务端口占用。
*
* @param services 计划服务列表。
* @returns 端口诊断。
*/
async function diagnosePorts(services) {
	const diagnostics = [];
	for (const service of services) for (const port of service.ports) if (await isPortInUse(port)) diagnostics.push({
		code: "PORT_IN_USE",
		level: "error",
		target: `${service.name}:${port}`,
		message: `端口已被占用: ${port}`
	});
	return diagnostics;
}
/**
* 检查外部依赖命令。
*
* @param dependencies 依赖配置。
* @param runner 命令执行器。
* @returns 诊断列表。
*/
async function diagnoseDependencies(dependencies, runner) {
	const diagnostics = [];
	for (const dependency of dependencies) {
		if (!dependency.checkCommand) continue;
		const result = await runner.run("sh", ["-lc", dependency.checkCommand]);
		if (result.exitCode !== 0) diagnostics.push({
			code: "DEPENDENCY_MISSING",
			level: "warn",
			target: dependency.name,
			message: `依赖服务未就绪: ${dependency.name}`,
			detail: result.stderr || result.stdout
		});
	}
	return diagnostics;
}
/**
* 判断端口是否被占用。
*
* @param port 端口号。
* @returns 占用时为 true。
*/
function isPortInUse(port) {
	return new Promise((resolve) => {
		const socket = createConnection({
			port,
			host: "127.0.0.1"
		});
		socket.once("connect", () => {
			socket.destroy();
			resolve(true);
		});
		socket.once("error", () => {
			socket.destroy();
			resolve(false);
		});
	});
}
/**
* 检查文件是否可访问。
*
* @param filePath 文件路径。
* @returns 可访问时为 true。
*/
async function canAccess(filePath) {
	try {
		await access(filePath, constants.X_OK);
		return true;
	} catch {
		return false;
	}
}

//#endregion
//#region src/format.ts
/**
* 格式化计划输出。
*
* @param plan 启动计划。
* @param format 输出格式。
* @returns 输出文本。
*/
function formatPlan(plan, format) {
	if (format === "json") return JSON.stringify(plan, null, 2);
	const lines = [
		`Project: ${plan.projectRoot}`,
		`Session: ${plan.session}`,
		`Attach: ${plan.attachCommand}`,
		"",
		"Services:"
	];
	if (plan.services.length === 0) lines.push("  (none selected)");
	else for (const service of plan.services) {
		lines.push(`  - ${service.name} [${service.source}] ${service.displayCommand}`);
		if (service.ports.length > 0) lines.push(`    ports: ${service.ports.join(", ")}`);
		if (service.prepare.length > 0) lines.push(`    prepare: ${service.prepare.join(" && ")}`);
		if (Object.keys(service.displayEnv).length > 0) lines.push(`    env: ${JSON.stringify(service.displayEnv)}`);
	}
	if (plan.ignored.length > 0) {
		lines.push("", "Ignored/unknown modules:");
		for (const ignored of plan.ignored) lines.push(`  - ${ignored.name}: ${ignored.reason}`);
	}
	if (plan.diagnostics.length > 0) {
		lines.push("", "Diagnostics:");
		lines.push(...formatDiagnostics(plan.diagnostics).map((line) => `  ${line}`));
	}
	return lines.join("\n");
}
/**
* 格式化诊断列表。
*
* @param diagnostics 诊断列表。
* @returns 文本行。
*/
function formatDiagnostics(diagnostics) {
	return diagnostics.map((diagnostic) => {
		const target = diagnostic.target ? ` [${diagnostic.target}]` : "";
		const detail = diagnostic.detail ? `: ${diagnostic.detail.trim()}` : "";
		return `${diagnostic.level.toUpperCase()} ${diagnostic.code}${target} ${diagnostic.message}${detail}`;
	});
}

//#endregion
//#region src/gitignore.ts
const IGNORE_ENTRY = ".project-launcher/";
/**
* 检查项目 .gitignore 是否忽略运行态目录。
*
* @param projectRoot 项目根目录。
* @returns 已忽略时为 true。
*/
async function isRuntimeDirectoryIgnored(projectRoot) {
	const gitignorePath = join(projectRoot, ".gitignore");
	if (!await exists(gitignorePath)) return false;
	return (await readFile(gitignorePath, "utf8")).split(/\r?\n/).map((line) => line.trim()).some((line) => line === IGNORE_ENTRY || line === ".project-launcher");
}
/**
* 写入 .project-launcher/ 忽略规则。
*
* @param projectRoot 项目根目录。
* @returns 是否实际写入。
*/
async function writeRuntimeGitignore(projectRoot) {
	if (await isRuntimeDirectoryIgnored(projectRoot)) return false;
	const gitignorePath = join(projectRoot, ".gitignore");
	await appendFile(gitignorePath, `${await exists(gitignorePath) ? "\n" : ""}${IGNORE_ENTRY}\n`, "utf8");
	return true;
}

//#endregion
//#region src/discovery.ts
const LIBRARY_HINTS = [
	"common",
	"model",
	"models",
	"sdk",
	"client",
	"starter",
	"bom",
	"core",
	"domain",
	"shared",
	"lib",
	"libs"
];
/**
* 发现项目中的可运行服务候选。
*
* @param projectRoot 项目根目录。
* @param config 已加载配置。
* @returns 服务候选和被忽略模块。
*/
async function discoverProject(projectRoot, config = {}) {
	const servicesFromConfig = (config.services ?? []).map((service) => serviceFromConfig(projectRoot, service));
	const discovered = await discoverBuildServices(projectRoot, config);
	return {
		projectRoot,
		buildTool: discovered.buildTool,
		services: mergeServiceCandidates([...servicesFromConfig, ...discovered.services]),
		ignored: discovered.ignored
	};
}
/**
* 把显式配置转换为启动候选。
*
* @param projectRoot 项目根目录。
* @param service 显式服务配置。
* @returns 服务候选。
*/
function serviceFromConfig(projectRoot, service) {
	const cwd = resolve(projectRoot, service.cwd ?? ".");
	const ports = normalizePorts(service);
	return {
		name: service.name,
		cwd,
		command: service.command,
		source: "config",
		port: service.port ?? ports[0],
		ports,
		prepare: normalizePrepare(service.prepare),
		env: service.env ?? {},
		reload: service.reload ?? "auto",
		reloadCommand: service.reloadCommand,
		allowParallelBuild: service.allowParallelBuild ?? false,
		confidence: "high",
		reasons: ["显式配置服务"]
	};
}
/**
* 创建一次性命令服务候选。
*
* @param projectRoot 项目根目录。
* @param input 一次性命令参数。
* @returns 服务候选。
*/
function serviceFromCommand(projectRoot, input) {
	return {
		name: input.name,
		cwd: projectRoot,
		command: input.command,
		source: "command",
		port: input.port,
		ports: input.port ? [input.port] : [],
		prepare: [],
		env: {},
		reload: input.reload ?? "auto",
		allowParallelBuild: false,
		confidence: "high",
		reasons: ["CLI 一次性命令"]
	};
}
/**
* 根据构建文件发现服务。
*
* @param projectRoot 项目根目录。
* @param config 已加载配置。
* @returns 构建工具、服务候选和被忽略模块。
*/
async function discoverBuildServices(projectRoot, config) {
	if (await exists(join(projectRoot, "pom.xml"))) return discoverMavenServices(projectRoot, config);
	if (await exists(join(projectRoot, "build.gradle")) || await exists(join(projectRoot, "build.gradle.kts")) || await exists(join(projectRoot, "settings.gradle")) || await exists(join(projectRoot, "settings.gradle.kts"))) return discoverGradleServices(projectRoot, config);
	return {
		services: [],
		ignored: []
	};
}
/**
* 发现 Maven 服务模块。
*
* @param projectRoot 项目根目录。
* @param config 已加载配置。
* @returns Maven 服务候选。
*/
async function discoverMavenServices(projectRoot, config) {
	const modules = parseMavenModules(await readText(join(projectRoot, "pom.xml")));
	const targets = modules.length > 0 ? modules.map((module) => resolve(projectRoot, module)) : [projectRoot];
	const services = [];
	const ignored = [];
	for (const target of targets) {
		const moduleName = basename(target);
		const pomPath = join(target, "pom.xml");
		if (!await exists(pomPath)) {
			ignored.push({
				name: moduleName,
				path: target,
				reason: "模块缺少 pom.xml"
			});
			continue;
		}
		const pom = await readText(pomPath);
		const appMain = await findSpringBootMain(target);
		const hasSpringPlugin = /spring-boot-maven-plugin/.test(pom);
		const isAggregator = parsePomPackaging(pom) === "pom";
		const libraryLike = isLibraryLike(moduleName);
		if (isAggregator || libraryLike && !hasSpringPlugin && !appMain) {
			ignored.push({
				name: moduleName,
				path: target,
				reason: isAggregator ? "Maven aggregator/parent 模块" : "疑似 library 模块"
			});
			continue;
		}
		if (hasSpringPlugin || appMain || modules.length === 0) {
			const moduleSelector = modules.length > 0 ? ` -pl ${moduleName}` : "";
			services.push({
				name: sanitizeServiceName(moduleName),
				cwd: projectRoot,
				command: `${mavenExecutable(projectRoot)} spring-boot:run${moduleSelector}`,
				source: "maven",
				modulePath: target,
				ports: [],
				prepare: [`${mavenExecutable(projectRoot)}${moduleSelector} -am compile`.trim()],
				env: profileEnv(config),
				reload: config.defaults?.reload ?? "auto",
				allowParallelBuild: config.defaults?.allowParallelBuild ?? false,
				confidence: hasSpringPlugin || appMain ? "high" : "medium",
				reasons: [hasSpringPlugin ? "存在 Spring Boot Maven 插件" : "单模块 Maven 项目", appMain ? "存在 @SpringBootApplication" : ""].filter(Boolean)
			});
		} else ignored.push({
			name: moduleName,
			path: target,
			reason: "未发现可运行 main 或 Spring Boot 插件"
		});
	}
	return {
		buildTool: "maven",
		services,
		ignored
	};
}
/**
* 发现 Gradle 服务模块。
*
* @param projectRoot 项目根目录。
* @param config 已加载配置。
* @returns Gradle 服务候选。
*/
async function discoverGradleServices(projectRoot, config) {
	const modules = parseGradleIncludes(await readOptionalText(join(projectRoot, "settings.gradle")) ?? await readOptionalText(join(projectRoot, "settings.gradle.kts")) ?? "");
	const targets = modules.length > 0 ? modules.map((module) => resolve(projectRoot, module.replace(/:/g, "/"))) : [projectRoot];
	const services = [];
	const ignored = [];
	for (const target of targets) {
		const moduleName = basename(target);
		const buildPath = await exists(join(target, "build.gradle")) && join(target, "build.gradle") || await exists(join(target, "build.gradle.kts")) && join(target, "build.gradle.kts");
		if (!buildPath) {
			ignored.push({
				name: moduleName,
				path: target,
				reason: "模块缺少 Gradle build 文件"
			});
			continue;
		}
		const build = await readText(buildPath);
		const appMain = await findSpringBootMain(target);
		const hasBootRun = /org\.springframework\.boot|bootRun/.test(build);
		const hasRun = /application\b|mainClass|tasks\.run\b/.test(build);
		if (isLibraryLike(moduleName) && !hasBootRun && !hasRun && !appMain) {
			ignored.push({
				name: moduleName,
				path: target,
				reason: "疑似 library 模块"
			});
			continue;
		}
		if (hasBootRun || hasRun || appMain || modules.length === 0) {
			const gradleTask = modules.length > 0 ? `:${relative(projectRoot, target).replace(/\//g, ":")}:` : "";
			const taskName = hasBootRun || appMain ? "bootRun" : "run";
			services.push({
				name: sanitizeServiceName(moduleName),
				cwd: projectRoot,
				command: `${gradleExecutable(projectRoot)} ${gradleTask}${taskName}`.trim(),
				source: "gradle",
				modulePath: target,
				ports: [],
				prepare: [`${gradleExecutable(projectRoot)} ${gradleTask}classes`.trim()],
				env: profileEnv(config),
				reload: config.defaults?.reload ?? "auto",
				reloadCommand: void 0,
				allowParallelBuild: config.defaults?.allowParallelBuild ?? false,
				confidence: hasBootRun || hasRun || appMain ? "high" : "medium",
				reasons: [
					hasBootRun ? "存在 bootRun/Spring Boot 插件" : "",
					hasRun ? "存在 application/run 线索" : "",
					appMain ? "存在 @SpringBootApplication" : ""
				].filter(Boolean)
			});
		} else ignored.push({
			name: moduleName,
			path: target,
			reason: "未发现可运行 Gradle task"
		});
	}
	return {
		buildTool: "gradle",
		services,
		ignored
	};
}
/**
* 解析 Maven modules。
*
* @param pom pom.xml 文本。
* @returns 模块路径列表。
*/
function parseMavenModules(pom) {
	const modulesBlock = pom.match(/<modules>([\s\S]*?)<\/modules>/);
	if (!modulesBlock) return [];
	return [...modulesBlock[1].matchAll(/<module>(.*?)<\/module>/g)].map((match) => match[1].trim()).filter(Boolean);
}
/**
* 解析 pom packaging。
*
* @param pom pom.xml 文本。
* @returns packaging 值。
*/
function parsePomPackaging(pom) {
	return pom.match(/<packaging>(.*?)<\/packaging>/)?.[1]?.trim() ?? "jar";
}
/**
* 解析 Gradle include 声明。
*
* @param settings settings.gradle 文本。
* @returns 子项目路径列表。
*/
function parseGradleIncludes(settings) {
	const modules = [];
	for (const match of settings.matchAll(/include\s*\(?\s*([^\n)]+)/g)) {
		const segment = match[1];
		for (const entry of segment.matchAll(/['"](:?[\w.-][\w.:-]*)['"]/g)) modules.push(entry[1].replace(/^:/, "").replace(/:/g, "/"));
	}
	return [...new Set(modules)];
}
/**
* 归一化服务名。
*
* @param name 原始名称。
* @returns 适合 CLI 使用的名称。
*/
function sanitizeServiceName(name) {
	return name.replace(/([a-z0-9])([A-Z])/g, "$1-$2").replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^-+|-+$/g, "").toLowerCase();
}
/**
* 判断模块名是否像库模块。
*
* @param name 模块名。
* @returns 疑似库模块时为 true。
*/
function isLibraryLike(name) {
	const normalized = sanitizeServiceName(name);
	return LIBRARY_HINTS.some((hint) => normalized === hint || normalized.endsWith(`-${hint}`));
}
/**
* 查找 Spring Boot main class 线索。
*
* @param moduleRoot 模块目录。
* @returns 是否存在 Spring Boot main class。
*/
async function findSpringBootMain(moduleRoot) {
	const sourceRoot = join(moduleRoot, "src", "main");
	if (!await exists(sourceRoot)) return false;
	const files = await collectFiles(sourceRoot, 60);
	for (const file of files) {
		if (!/\.(java|kt)$/.test(file)) continue;
		const content = await readText(file);
		if (content.includes("@SpringBootApplication") || /public\s+static\s+void\s+main\s*\(/.test(content) || /fun\s+main\s*\(/.test(content)) return true;
	}
	return false;
}
/**
* 收集目录下文件，带上限避免扫描过深。
*
* @param root 根目录。
* @param limit 最大文件数量。
* @returns 文件路径列表。
*/
async function collectFiles(root, limit) {
	const files = [];
	const stack = [root];
	while (stack.length > 0 && files.length < limit) {
		const current = stack.pop();
		if (!current) break;
		for (const entry of await readdir(current, { withFileTypes: true })) {
			const path = join(current, entry.name);
			if (entry.isDirectory()) stack.push(path);
			else if (entry.isFile()) files.push(path);
			if (files.length >= limit) break;
		}
	}
	return files;
}
/**
* 合并配置和发现候选，配置优先。
*
* @param candidates 候选列表。
* @returns 去重后的候选。
*/
function mergeServiceCandidates(candidates) {
	const merged = /* @__PURE__ */ new Map();
	for (const candidate of candidates) if (!merged.has(candidate.name) || candidate.source === "config") merged.set(candidate.name, candidate);
	return [...merged.values()];
}
/**
* 从配置构造 profile 环境。
*
* @param config 已加载配置。
* @returns 环境变量。
*/
function profileEnv(config) {
	const profile = config.defaults?.profile;
	return profile ? { SPRING_PROFILES_ACTIVE: profile } : {};
}
/**
* Maven 可执行命令，优先 wrapper。
*
* @param projectRoot 项目根目录。
* @returns Maven 命令。
*/
function mavenExecutable(projectRoot) {
	return existsSync(join(projectRoot, "mvnw")) ? "./mvnw" : "mvn";
}
/**
* Gradle 可执行命令，优先 wrapper。
*
* @param projectRoot 项目根目录。
* @returns Gradle 命令。
*/
function gradleExecutable(projectRoot) {
	return existsSync(join(projectRoot, "gradlew")) ? "./gradlew" : "gradle";
}
/**
* 读取文本文件。
*
* @param filePath 文件路径。
* @returns 文件内容。
*/
async function readText(filePath) {
	return readFile(filePath, "utf8");
}
/**
* 尝试读取文本文件。
*
* @param filePath 文件路径。
* @returns 文件内容或 undefined。
*/
async function readOptionalText(filePath) {
	try {
		return await readText(filePath);
	} catch {
		return;
	}
}
/**
* 归一化端口配置。
*
* @param service 服务配置。
* @returns 端口列表。
*/
function normalizePorts(service) {
	return [...typeof service.port === "number" ? [service.port] : [], ...service.ports ?? []].filter((value, index, array) => array.indexOf(value) === index);
}
/**
* 归一化 prepare 配置。
*
* @param prepare prepare 字段。
* @returns prepare 命令列表。
*/
function normalizePrepare(prepare) {
	if (!prepare) return [];
	return Array.isArray(prepare) ? prepare : [prepare];
}

//#endregion
//#region src/planner.ts
/**
* 生成启动计划。
*
* @param options 计划输入。
* @returns 启动计划。
*/
async function createLaunchPlan(options) {
	const discovery = await discoverProject(options.projectRoot, options.loadedConfig.config);
	const extra = options.commandService ? [serviceFromCommand(options.projectRoot, options.commandService)] : [];
	const candidates = [...discovery.services, ...extra];
	const diagnostics = [];
	const selection = selectServices(candidates, {
		names: options.serviceNames,
		all: options.all,
		action: options.action
	});
	diagnostics.push(...selection.diagnostics);
	if (hasParallelBuildRisk(selection.services) && !options.allowParallelBuild) diagnostics.push({
		code: "PARALLEL_BUILD_RISK",
		level: "warn",
		message: "检测到多个服务包含构建/编译准备命令；默认将串行准备，需并发时传 --allow-parallel-build。"
	});
	const session = resolveSessionName(options.projectRoot, options.loadedConfig.config.defaults?.sessionName);
	const services = selection.services.map((service, index) => toPlannedService(service, index));
	return {
		ok: !diagnostics.some((item) => item.level === "error"),
		action: options.action,
		projectRoot: options.projectRoot,
		session,
		attachCommand: `tmux attach -t ${shellQuote(session)}`,
		services,
		ignored: discovery.ignored,
		diagnostics,
		metadataPath: join(options.projectRoot, ".project-launcher", "session.json"),
		configPath: options.loadedConfig.path,
		selectionRequired: selection.selectionRequired
	};
}
/**
* 根据服务名或 all 参数选择服务。
*
* @param candidates 可用候选。
* @param options 选择参数。
* @returns 被选服务和诊断。
*/
function selectServices(candidates, options) {
	const diagnostics = [];
	const names = options.names ?? [];
	if (names.length > 0) {
		const services = candidates.filter((candidate) => names.includes(candidate.name));
		const missing = names.filter((name) => !candidates.some((candidate) => candidate.name === name));
		for (const name of missing) diagnostics.push({
			code: "UNKNOWN_SERVICE",
			level: "error",
			message: `未找到服务: ${name}`,
			target: name
		});
		return {
			services,
			diagnostics,
			selectionRequired: false
		};
	}
	if (options.all) return {
		services: candidates,
		diagnostics,
		selectionRequired: false
	};
	if (candidates.length === 1) return {
		services: candidates,
		diagnostics,
		selectionRequired: false
	};
	if (candidates.length > 1) {
		diagnostics.push({
			code: "MULTI_SERVICE_SELECTION_REQUIRED",
			level: options.action === "start" ? "error" : "warn",
			message: "发现多个服务候选，未传 --service 或 --all；默认只输出计划，不启动全部候选。"
		});
		return {
			services: [],
			diagnostics,
			selectionRequired: true
		};
	}
	if (options.action === "start") diagnostics.push({
		code: "NO_SERVICE_CANDIDATE",
		level: "error",
		message: "没有可启动服务。可先运行 plan 查看发现结果，或使用 --name 与 --command 指定一次性命令。"
	});
	return {
		services: [],
		diagnostics,
		selectionRequired: false
	};
}
/**
* 转换为计划服务。
*
* @param service 服务候选。
* @param index pane 序号。
* @returns 计划服务。
*/
function toPlannedService(service, index) {
	const pane = `dev.${index}`;
	return {
		name: service.name,
		cwd: service.cwd,
		command: service.command,
		displayCommand: service.command,
		port: service.port,
		ports: service.ports,
		prepare: service.prepare,
		env: service.env,
		displayEnv: redactEnv(service.env),
		pane,
		source: service.source
	};
}
/**
* 判断服务计划是否有并发构建风险。
*
* @param services 服务候选。
* @returns 存在风险时为 true。
*/
function hasParallelBuildRisk(services) {
	return services.filter((service) => service.prepare.some((command) => /\b(compile|build|package|classes)\b/.test(command))).length > 1;
}
/**
* 生成默认 tmux session 名。
*
* @param projectRoot 项目根目录。
* @param explicit 显式 session 名。
* @returns session 名称。
*/
function resolveSessionName(projectRoot, explicit) {
	if (explicit) return explicit;
	return `pl-${sanitizeServiceName(basename(resolve(projectRoot)))}`;
}
/**
* shell 参数引用。
*
* @param value 原始值。
* @returns 可用于 shell 的值。
*/
function shellQuote(value) {
	if (/^[A-Za-z0-9_./:-]+$/.test(value)) return value;
	return `'${value.replace(/'/g, `'\\''`)}'`;
}

//#endregion
//#region src/runner.ts
var NodeCommandRunner = class {
	/**
	* 运行外部命令并收集输出。
	*
	* @param command 命令名。
	* @param args 命令参数。
	* @param options 执行目录、环境和输入。
	* @returns 命令退出结果。
	*/
	run(command, args, options = {}) {
		return new Promise((resolve) => {
			const child = spawn(command, args, {
				cwd: options.cwd,
				env: {
					...process.env,
					...options.env
				},
				stdio: [
					"pipe",
					"pipe",
					"pipe"
				]
			});
			let stdout = "";
			let stderr = "";
			child.stdout.setEncoding("utf8");
			child.stderr.setEncoding("utf8");
			child.stdout.on("data", (chunk) => {
				stdout += chunk;
			});
			child.stderr.on("data", (chunk) => {
				stderr += chunk;
			});
			child.on("error", (error) => {
				resolve({
					exitCode: 127,
					stdout,
					stderr: error.message
				});
			});
			child.on("close", (code) => {
				resolve({
					exitCode: code ?? 1,
					stdout,
					stderr
				});
			});
			if (options.input) child.stdin.write(options.input);
			child.stdin.end();
		});
	}
};

//#endregion
//#region src/session.ts
/**
* 创建 session 元数据。
*
* @param plan 启动计划。
* @param now 当前时间。
* @returns session 元数据。
*/
function createSessionMetadata(plan, now = /* @__PURE__ */ new Date()) {
	return {
		managedBy: "project-launcher",
		session: plan.session,
		projectRoot: plan.projectRoot,
		configPath: plan.configPath,
		configHash: createPlanHash(plan),
		services: plan.services.map((service) => service.name),
		createdAt: now.toISOString()
	};
}
/**
* 写入 session 元数据。
*
* @param metadataPath 元数据路径。
* @param metadata 元数据。
* @returns 无返回值。
*/
async function writeSessionMetadata(metadataPath, metadata) {
	await mkdir(dirname(metadataPath), { recursive: true });
	await writeFile(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`, "utf8");
}
/**
* 读取 session 元数据。
*
* @param metadataPath 元数据路径。
* @returns 元数据或 undefined。
*/
async function readSessionMetadata(metadataPath) {
	if (!await exists(metadataPath)) return;
	return JSON.parse(await readFile(metadataPath, "utf8"));
}
/**
* 判断元数据是否匹配当前计划。
*
* @param metadata 已保存元数据。
* @param plan 当前启动计划。
* @returns 匹配结果和原因。
*/
function validateSessionMetadata(metadata, plan) {
	if (!metadata) return {
		ok: false,
		reason: "缺少 .project-launcher/session.json"
	};
	if (metadata.managedBy !== "project-launcher") return {
		ok: false,
		reason: "session 不是 project-launcher 管理"
	};
	if (metadata.session !== plan.session) return {
		ok: false,
		reason: "session 名不匹配"
	};
	if (metadata.projectRoot !== plan.projectRoot) return {
		ok: false,
		reason: "项目根目录不匹配"
	};
	const currentServices = plan.services.map((service) => service.name).sort();
	const metadataServices = [...metadata.services].sort();
	if (currentServices.join(",") !== metadataServices.join(",")) return {
		ok: false,
		reason: "服务列表不匹配"
	};
	return { ok: true };
}
/**
* 生成计划指纹。
*
* @param plan 启动计划。
* @returns 短 hash。
*/
function createPlanHash(plan) {
	const payload = {
		configPath: plan.configPath,
		services: plan.services.map((service) => ({
			name: service.name,
			cwd: service.cwd,
			command: service.command,
			ports: service.ports
		}))
	};
	return createHash("sha256").update(JSON.stringify(payload)).digest("hex").slice(0, 12);
}

//#endregion
//#region src/tmux.ts
/**
* 生成 tmux 启动命令。
*
* @param plan 启动计划。
* @returns tmux 命令序列。
*/
function buildTmuxCommands(plan) {
	const commands = [];
	const session = plan.session;
	commands.push(command("tmux", [
		"new-session",
		"-d",
		"-s",
		session,
		"-n",
		"dev"
	]));
	plan.services.forEach((service, index) => {
		if (index > 0) commands.push(command("tmux", [
			"split-window",
			"-t",
			`${session}:dev`
		]));
		commands.push(command("tmux", [
			"send-keys",
			"-t",
			`${session}:dev.${index}`,
			`cd ${shellQuote(service.cwd)} && ${service.command}`,
			"C-m"
		]));
	});
	if (plan.services.length > 1) commands.push(command("tmux", [
		"select-layout",
		"-t",
		`${session}:dev`,
		"tiled"
	]));
	return commands;
}
/**
* 执行 tmux 启动命令。
*
* @param plan 启动计划。
* @param runner 命令执行器。
* @returns 执行结果。
*/
async function executeTmuxPlan(plan, runner) {
	for (const tmuxCommand of buildTmuxCommands(plan)) {
		const result = await runner.run(tmuxCommand.command, tmuxCommand.args, { cwd: plan.projectRoot });
		if (result.exitCode !== 0) throw new Error(result.stderr || `tmux 命令失败: ${tmuxCommand.display}`);
	}
}
/**
* 检查 tmux session 是否存在。
*
* @param session tmux session 名。
* @param runner 命令执行器。
* @param cwd 执行目录。
* @returns session 存在时为 true。
*/
async function tmuxSessionExists(session, runner, cwd) {
	return (await runner.run("tmux", [
		"has-session",
		"-t",
		session
	], { cwd })).exitCode === 0;
}
/**
* 停止指定 tmux session。
*
* @param session tmux session 名。
* @param runner 命令执行器。
* @param cwd 执行目录。
* @returns 无返回值。
*/
async function killTmuxSession(session, runner, cwd) {
	const result = await runner.run("tmux", [
		"kill-session",
		"-t",
		session
	], { cwd });
	if (result.exitCode !== 0) throw new Error(result.stderr || `停止 tmux session 失败: ${session}`);
}
/**
* 生成 attach 命令。
*
* @param session tmux session 名。
* @returns attach 命令对象。
*/
function buildAttachCommand(session) {
	return command("tmux", [
		"attach",
		"-t",
		session
	]);
}
/**
* 创建命令对象。
*
* @param commandName 命令名。
* @param args 参数列表。
* @returns 命令对象。
*/
function command(commandName, args) {
	return {
		command: commandName,
		args,
		display: [commandName, ...args.map(shellQuote)].join(" ")
	};
}

//#endregion
//#region src/cli.ts
const DEFAULT_IO = {
	stdout: (message) => console.log(message),
	stderr: (message) => console.error(message)
};
/**
* 运行 CLI。
*
* @param argv 命令行参数。
* @param runtime 测试可注入的运行环境。
* @returns 退出码。
*/
async function runCli(argv, runtime = {}) {
	const io = runtime.io ?? DEFAULT_IO;
	const runner = runtime.runner ?? new NodeCommandRunner();
	const cwd = runtime.cwd ?? process.cwd();
	const cli = cac("project-launcher");
	cli.option("--cwd <path>", "项目根目录。").help();
	cli.command("plan", "发现项目并输出启动计划。").option("--config <path>", "配置文件路径。").option("--service <name>", "指定服务，支持逗号分隔。").option("--all", "选择全部服务。").option("--format <format>", "输出格式：text 或 json。", { default: "text" }).option("--allow-parallel-build", "允许并发构建。").action(async (options) => {
		const plan = await preparePlan("plan", options, {
			cwd,
			runner
		});
		await warnGitignore(plan, io);
		io.stdout(formatPlan(plan, parseFormat(options.format)));
	});
	cli.command("doctor", "检查启动依赖、端口和外部依赖。").option("--config <path>", "配置文件路径。").option("--service <name>", "指定服务，支持逗号分隔。").option("--all", "选择全部服务。").option("--format <format>", "输出格式：text 或 json。", { default: "text" }).action(async (options) => {
		const plan = await preparePlan("doctor", options, {
			cwd,
			runner
		});
		plan.diagnostics.push(...await diagnosePlan(plan, {
			runner,
			dependencies: (await loadConfigForOptions(options, cwd)).config.dependencies
		}));
		await warnGitignore(plan, io);
		io.stdout(formatPlan(plan, parseFormat(options.format)));
	});
	cli.command("start", "通过 tmux 启动服务。").option("--config <path>", "配置文件路径。").option("--service <name>", "指定服务，支持逗号分隔。").option("--all", "选择全部服务。").option("--name <name>", "一次性命令的服务名。").option("--command <command>", "一次性启动命令。").option("--port <port>", "一次性命令端口。").option("--save", "把一次性命令保存到 project-launch.local.json。").option("--overwrite", "保存同名服务时覆盖。").option("--replace", "同名 tmux session 冲突时显式停止并重建。").option("--attach", "启动后直接 attach 进入 tmux。").option("--format <format>", "输出格式：text 或 json。", { default: "text" }).option("--reload <mode>", "热重载模式：auto、off 或 command。", { default: "auto" }).option("--allow-parallel-build", "允许并发构建。").action(async (options) => {
		const commandOverride = parseCommandOverride(options);
		if (options.save && !commandOverride) throw new CliError("CONFIG_PARSE_ERROR", "--save 需要同时提供 --name 和 --command。");
		const plan = await preparePlan("start", options, {
			cwd,
			runner
		});
		const loadedConfig = await loadConfigForOptions(options, cwd);
		if (options.save && commandOverride) {
			const port = parsePort(options.port);
			await saveServiceToLocalConfig(resolveProjectRoot(cwd, options.cwd), {
				name: commandOverride.name,
				command: commandOverride.command,
				port
			}, { overwrite: Boolean(options.overwrite) });
		}
		plan.diagnostics.push(...await diagnosePlan(plan, {
			runner,
			dependencies: loadedConfig.config.dependencies
		}));
		await warnGitignore(plan, io);
		if (!plan.ok || plan.diagnostics.some((item) => item.level === "error")) {
			io.stdout(formatPlan(plan, parseFormat(options.format)));
			return;
		}
		const metadataCheck = validateSessionMetadata(await readSessionMetadata(plan.metadataPath), plan);
		if (await tmuxSessionExists(plan.session, runner, plan.projectRoot)) {
			if (metadataCheck.ok) {
				io.stdout(formatPlan(plan, parseFormat(options.format)));
				if (options.attach) {
					const attach = buildAttachCommand(plan.session);
					await runner.run(attach.command, attach.args, { cwd: plan.projectRoot });
				}
				return;
			}
			if (!options.replace) throw new CliError("SESSION_CONFLICT", `同名 tmux session 已存在但不能安全复用: ${metadataCheck.reason}。需要重建时传 --replace。`);
			await killTmuxSession(plan.session, runner, plan.projectRoot);
		}
		await executePrepareCommands(plan, runner);
		await executeTmuxPlan(plan, runner);
		await writeSessionMetadata(plan.metadataPath, createSessionMetadata(plan));
		io.stdout(formatPlan(plan, parseFormat(options.format)));
		if (options.attach) {
			const attach = buildAttachCommand(plan.session);
			await runner.run(attach.command, attach.args, { cwd: plan.projectRoot });
		}
	});
	cli.command("attach", "进入当前项目 tmux session。").option("--print", "只打印 attach 命令。").action(async (options) => {
		const projectRoot = resolveProjectRoot(cwd, options.cwd);
		const metadata = await readSessionMetadata(join(projectRoot, ".project-launcher", "session.json"));
		if (!metadata) throw new CliError("SESSION_CONFLICT", "未找到 session 元数据。");
		const attach = buildAttachCommand(metadata.session);
		if (options.print) {
			io.stdout(attach.display);
			return;
		}
		await runner.run(attach.command, attach.args, { cwd: projectRoot });
	});
	cli.command("stop", "停止当前项目 tmux session。").option("--force", "缺少完整元数据时仍尝试停止。").action(async (options) => {
		const projectRoot = resolveProjectRoot(cwd, options.cwd);
		const metadata = await readSessionMetadata(join(projectRoot, ".project-launcher", "session.json"));
		if (!metadata && !options.force) throw new CliError("SESSION_CONFLICT", "未找到 session 元数据。需要强制停止时传 --force。");
		const session = metadata?.session;
		if (!session) throw new CliError("SESSION_CONFLICT", "--force 仍需要可识别 session。");
		await killTmuxSession(session, runner, projectRoot);
		io.stdout(`Stopped ${session}`);
	});
	cli.command("init", "初始化项目启动器辅助配置。").option("--write-gitignore", "写入 .project-launcher/ 忽略规则。").action(async (options) => {
		const projectRoot = resolveProjectRoot(cwd, options.cwd);
		if (!options.writeGitignore) {
			const ignored = await isRuntimeDirectoryIgnored(projectRoot);
			io.stdout(ignored ? ".project-launcher/ 已被 .gitignore 忽略。" : "未写入任何文件；如需忽略运行态目录，传 --write-gitignore。");
			return;
		}
		const changed = await writeRuntimeGitignore(projectRoot);
		io.stdout(changed ? "已写入 .project-launcher/" : "忽略规则已存在。");
	});
	try {
		cli.parse([
			"node",
			"project-launcher",
			...argv
		], { run: false });
		await cli.runMatchedCommand();
		return 0;
	} catch (error) {
		if (error instanceof CliError) {
			io.stderr(error.message);
			return error.exitCode;
		}
		io.stderr(error instanceof Error ? error.message : String(error));
		return 1;
	}
}
/**
* 准备计划。
*
* @param action 当前动作。
* @param options CLI 选项。
* @param runtime 运行环境。
* @returns 启动计划。
*/
async function preparePlan(action, options, runtime) {
	const projectRoot = resolveProjectRoot(runtime.cwd, options.cwd);
	const loadedConfig = await loadConfigForOptions(options, runtime.cwd);
	const commandOverride = parseCommandOverride(options);
	return createLaunchPlan({
		action,
		projectRoot,
		loadedConfig,
		serviceNames: parseServiceNames(options.service),
		all: Boolean(options.all),
		commandService: commandOverride ? {
			...commandOverride,
			port: parsePort(options.port),
			reload: parseReload(options.reload)
		} : void 0,
		allowParallelBuild: Boolean(options.allowParallelBuild)
	});
}
/**
* 加载配置。
*
* @param options CLI 选项。
* @param cwd 当前目录。
* @returns 已加载配置。
*/
async function loadConfigForOptions(options, cwd) {
	return loadConfig(resolveProjectRoot(cwd, options.cwd), { configPath: typeof options.config === "string" ? options.config : void 0 });
}
/**
* 解析项目根目录。
*
* @param cwd 当前目录。
* @param option 显式 cwd。
* @returns 项目根目录。
*/
function resolveProjectRoot(cwd, option) {
	return resolve(cwd, typeof option === "string" ? option : ".");
}
/**
* 解析输出格式。
*
* @param value 原始值。
* @returns 输出格式。
*/
function parseFormat(value) {
	return value === "json" ? "json" : "text";
}
/**
* 解析服务名列表。
*
* @param value 原始值。
* @returns 服务名列表。
*/
function parseServiceNames(value) {
	if (typeof value !== "string" || value.trim().length === 0) return;
	return value.split(",").map((item) => item.trim()).filter(Boolean);
}
/**
* 解析一次性命令参数。
*
* @param options CLI 选项。
* @returns 一次性命令或 undefined。
*/
function parseCommandOverride(options) {
	if (typeof options.name === "string" && typeof options.command === "string") return {
		name: options.name,
		command: options.command
	};
}
/**
* 解析端口。
*
* @param value 原始值。
* @returns 端口或 undefined。
*/
function parsePort(value) {
	if (value === void 0) return;
	const parsed = Number(value);
	return Number.isInteger(parsed) ? parsed : void 0;
}
/**
* 解析热重载模式。
*
* @param value 原始值。
* @returns 热重载模式。
*/
function parseReload(value) {
	if (value === "auto" || value === "off" || value === "command") return value;
}
/**
* 输出 gitignore 运行态目录提示。
*
* @param plan 启动计划。
* @param io 输出接口。
* @returns 无返回值。
*/
async function warnGitignore(plan, io) {
	if (!await isRuntimeDirectoryIgnored(plan.projectRoot)) io.stderr("提示: 建议将 .project-launcher/ 加入 .gitignore，可执行 project-launcher init --write-gitignore。");
}
/**
* 串行执行服务 prepare 命令。
*
* @param plan 启动计划。
* @param runner 命令执行器。
* @returns 无返回值。
*/
async function executePrepareCommands(plan, runner) {
	for (const service of plan.services) for (const prepare of service.prepare) {
		const result = await runner.run("sh", ["-lc", prepare], {
			cwd: service.cwd,
			env: service.env
		});
		if (result.exitCode !== 0) throw new CliError("PREPARE_FAILED", `服务 ${service.name} 的 prepare 命令失败: ${prepare}\n${result.stderr || result.stdout}`);
	}
}

//#endregion
//#region src/project-launcher.ts
const exitCode = await runCli(process.argv.slice(2));
process.exitCode = exitCode;

//#endregion
export {  };
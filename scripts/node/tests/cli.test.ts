import fs from "node:fs";
import path from "node:path";
import { execa } from "execa";
import { describe, expect, it } from "vitest";

// Helper to run the built script
const runScript = async (scriptName: string, args: string[] = []) => {
  const binPath = path.resolve(
    __dirname,
    "../../../bin",
    process.platform === "win32" ? `${scriptName}.cmd` : scriptName
  );

  // Ensure build exists
  if (!fs.existsSync(binPath)) {
    throw new Error(
      `Script not found at ${binPath}. Did you run 'pnpm build'?`
    );
  }

  return execa(binPath, args);
};

describe("CLI Integration Tests", () => {
  it("should run rule-loader --version", async () => {
    const { stdout } = await runScript("rule-loader", ["--version"]);

    expect(stdout).toContain("1.0.0");
  });

  it("should run rule-loader --help", async () => {
    const { stdout } = await runScript("rule-loader", ["--help"]);

    expect(stdout).toContain("Usage: rule-loader");
    expect(stdout).toContain("AI 编码规则加载器");
  });
});

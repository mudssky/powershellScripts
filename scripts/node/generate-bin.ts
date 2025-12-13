import fs from 'fs/promises'
import path from 'path'
import { fileURLToPath } from 'url'
import { constants } from 'fs'

// ESM environment helpers
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

interface GeneratorConfig {
  distDir: string
  globalBinDir: string
  copyJsToBin: boolean
}

/**
 * Generates the Unix shell script content
 */
function getUnixScript(jsRelPath: string): string {
  // Use $basedir to resolve the script location
  return `#!/bin/sh
basedir=$(dirname "$0")
exec node "$basedir/${jsRelPath}" "$@"
`
}

/**
 * Generates the Windows CMD script content
 */
function getWindowsScript(jsRelPath: string): string {
  // Convert to Windows backslashes
  const winJsRelPath = jsRelPath.replace(/\//g, '\\')
  // Use %~dp0 to resolve the script location
  return `@echo off
node "%~dp0\\${winJsRelPath}" %*
`
}

/**
 * Main generation logic
 */
async function generateBinWrappers() {
  const config: GeneratorConfig = {
    distDir: path.resolve(__dirname, 'dist'),
    globalBinDir: path.resolve(__dirname, '../../bin'),
    copyJsToBin: process.env.COPY_JS === 'true',
  }

  console.log(`Target Bin Dir: ${config.globalBinDir}`)
  console.log(`Copy JS Mode: ${config.copyJsToBin}`)

  // Ensure directories exist
  try {
    await fs.mkdir(config.globalBinDir, { recursive: true })
  } catch (error) {
    console.error('Error creating bin directory:', error)
    process.exit(1)
  }

  // Check if dist exists
  try {
    await fs.access(config.distDir, constants.F_OK)
  } catch {
    console.error('No dist directory found. Run build first.')
    process.exit(1)
  }

  // Read files
  const files = await fs.readdir(config.distDir)

  for (const file of files) {
    if (!file.endsWith('.cjs')) {
      continue
    }

    const name = file.replace('.cjs', '')
    let jsRelPath: string

    try {
      if (config.copyJsToBin) {
        // Copy JS file to global bin
        const srcJs = path.join(config.distDir, file)
        const destJs = path.join(config.globalBinDir, file)
        await fs.copyFile(srcJs, destJs)
        console.log(`Copied ${file} to ${config.globalBinDir}`)

        // Relative path is just the filename since they are in the same dir
        jsRelPath = file
      } else {
        // Calculate relative path from bin dir to dist dir
        const relPath = path.relative(
          config.globalBinDir,
          path.join(config.distDir, file),
        )
        // Ensure forward slashes for cross-platform consistency in JS strings (used in Unix script)
        jsRelPath = relPath.split(path.sep).join('/')
      }

      // 1. Generate Unix Shell Script
      const unixScript = getUnixScript(jsRelPath)
      const unixPath = path.join(config.globalBinDir, name)
      await fs.writeFile(unixPath, unixScript)

      try {
        await fs.chmod(unixPath, '755') // Make executable
      } catch (e) {
        // Ignore chmod errors on Windows if they occur, though fs/promises might throw
      }

      // 2. Generate Windows CMD Script
      const cmdScript = getWindowsScript(jsRelPath)
      const cmdPath = path.join(config.globalBinDir, `${name}.cmd`)
      await fs.writeFile(cmdPath, cmdScript)

      console.log(`Generated wrappers for ${name} -> ${jsRelPath}`)
    } catch (error) {
      console.error(`Failed to generate wrappers for ${file}:`, error)
    }
  }
}

// Run
generateBinWrappers().catch((err) => {
  console.error('Fatal error:', err)
  process.exit(1)
})

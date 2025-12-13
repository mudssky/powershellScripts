import path from 'path'
import fs from 'fs'

console.log('Hello from Rspack bundled script!')
console.log('Args:', process.argv.slice(2))
console.log('CWD:', process.cwd())
console.log('__dirname:', __dirname) // Note: In bundled code, this might point to the bundle location or be shimmed.

// Simple logic to prove it works
const args = process.argv.slice(2)
if (args.length > 0) {
  console.log(`You said: ${args.join(' ')}`)
} else {
  console.log('No arguments provided. Try passing some!')
}

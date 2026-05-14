import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const artifactPath = resolve(root, 'out/NerwoEscrow.sol/NerwoEscrow.json');
const outputPath = resolve(root, 'exports/NerwoEscrow.abi.json');
const artifact = JSON.parse(await readFile(artifactPath, 'utf8'));

if (!Array.isArray(artifact.abi)) {
  throw new Error(`Missing ABI in ${artifactPath}`);
}

await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(artifact.abi, null, 2)}\n`);
console.log(`Exported NerwoEscrow ABI to ${outputPath}`);

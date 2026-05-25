import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const root = resolve(new URL('..', import.meta.url).pathname);
const exports = [
  {
    artifactPath: resolve(root, 'out/NerwoEscrow.sol/NerwoEscrow.json'),
    outputPath: resolve(root, 'exports/NerwoEscrow.abi.json'),
    name: 'NerwoEscrow',
  },
  {
    artifactPath: resolve(
      root,
      'out/NerwoCentralizedArbitrator.sol/NerwoCentralizedArbitrator.json',
    ),
    outputPath: resolve(root, 'exports/NerwoCentralizedArbitrator.abi.json'),
    name: 'NerwoCentralizedArbitrator',
  },
];

for (const item of exports) {
  const artifact = JSON.parse(await readFile(item.artifactPath, 'utf8'));

  if (!Array.isArray(artifact.abi)) {
    throw new Error(`Missing ABI in ${item.artifactPath}`);
  }

  await mkdir(dirname(item.outputPath), { recursive: true });
  await writeFile(item.outputPath, `${JSON.stringify(artifact.abi, null, 2)}\n`);
  console.log(`Exported ${item.name} ABI to ${item.outputPath}`);
}

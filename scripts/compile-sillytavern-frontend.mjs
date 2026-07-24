import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const sourceDirectory = path.resolve(process.argv[2] ?? '');
const packageFile = path.join(sourceDirectory, 'package.json');
const webpackConfigFile = path.join(sourceDirectory, 'webpack.config.js');

if (!fs.existsSync(packageFile) || !fs.existsSync(webpackConfigFile)) {
  throw new Error(`Invalid SillyTavern source directory: ${sourceDirectory}`);
}

process.chdir(sourceDirectory);
const applicationRequire = createRequire(packageFile);
const webpack = applicationRequire('webpack');
const { default: getPublicLibConfig } = await import(pathToFileURL(webpackConfigFile).href);
const config = getPublicLibConfig({ forceDist: true, pruneCache: true });

await new Promise((resolve, reject) => {
  const compiler = webpack(config);
  compiler.run((error, stats) => {
    const finish = (closeError) => {
      if (error || closeError || stats?.hasErrors()) {
        const details = stats?.toString(config.stats) || '';
        reject(error ?? closeError ?? new Error(details || 'Webpack compilation failed.'));
        return;
      }
      resolve();
    };
    compiler.close(finish);
  });
});

const outputFile = path.join(config.output.path, config.output.filename);
const outputSize = fs.statSync(outputFile).size;
if (outputSize < 100_000) {
  throw new Error(`Precompiled frontend library is unexpectedly small: ${outputSize} bytes.`);
}

console.log(`Precompiled SillyTavern frontend: ${outputFile} (${outputSize} bytes)`);

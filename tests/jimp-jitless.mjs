import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const sourceDirectory = path.resolve(process.argv[2] ?? '');
const jimpEntrypoint = path.join(sourceDirectory, 'src', 'jimp.js');
const pngFixture = path.join(sourceDirectory, 'default', 'content', 'default_Seraphina.png');
const jpegFixture = path.join(sourceDirectory, 'default', 'content', 'backgrounds', '_white.jpg');

const { Jimp, JimpMime } = await import(pathToFileURL(jimpEntrypoint).href);
const pngImage = await Jimp.read(await fs.readFile(pngFixture));
const jpegImage = await Jimp.read(await fs.readFile(jpegFixture));
const encodedPNG = await pngImage.getBuffer(JimpMime.png);
const encodedJPEG = await jpegImage.getBuffer(JimpMime.jpeg);

assert.ok(pngImage.width > 0 && pngImage.height > 0);
assert.ok(jpegImage.width > 0 && jpegImage.height > 0);
assert.ok(encodedPNG.length > 100);
assert.ok(encodedJPEG.length > 100);

console.log(JSON.stringify({
  ok: true,
  png: { width: pngImage.width, height: pngImage.height, bytes: encodedPNG.length },
  jpeg: { width: jpegImage.width, height: jpegImage.height, bytes: encodedJPEG.length },
}, null, 2));

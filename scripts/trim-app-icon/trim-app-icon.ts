/**
 * Trim outer white padding from the receipt-drop app icon and write launcher assets.
 *
 * Uses corner flood-fill so interior whites (e.g. the receipt paper) stay intact.
 *
 * Usage:
 *   npm run trim -- <input.png> [output-dir]
 *
 * Default output: ../../assets/branding/app_icon/
 */
import { mkdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_OUT = path.resolve(__dirname, "../../assets/branding/app_icon");
const BRAND_YELLOW = "#F6C64B";
const OUTPUT_SIZE = 1024;
/** Pixels with R,G,B all >= this value are treated as removable background. */
const WHITE_FLOOR = 240;

type Rgba = { r: number; g: number; b: number; a: number };

function isBackgroundWhite(p: Rgba): boolean {
  return p.r >= WHITE_FLOOR && p.g >= WHITE_FLOOR && p.b >= WHITE_FLOOR;
}

/** Flood-fill white-ish pixels reachable from image edges (corner padding). */
function maskOuterWhite(data: Buffer, width: number, height: number): Uint8Array {
  const n = width * height;
  const remove = new Uint8Array(n);
  const visited = new Uint8Array(n);
  const queue: number[] = [];

  const seed = (x: number, y: number) => {
    const i = y * width + x;
    if (visited[i]) return;
    const o = i * 4;
    const px: Rgba = { r: data[o], g: data[o + 1], b: data[o + 2], a: data[o + 3] };
    if (!isBackgroundWhite(px)) return;
    visited[i] = 1;
    queue.push(i);
  };

  for (let x = 0; x < width; x++) {
    seed(x, 0);
    seed(x, height - 1);
  }
  for (let y = 0; y < height; y++) {
    seed(0, y);
    seed(width - 1, y);
  }

  while (queue.length > 0) {
    const i = queue.pop()!;
    remove[i] = 1;
    const x = i % width;
    const y = (i - x) / width;
    for (const [nx, ny] of [
      [x - 1, y],
      [x + 1, y],
      [x, y - 1],
      [x, y + 1],
    ] as const) {
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
      const ni = ny * width + nx;
      if (visited[ni]) continue;
      const o = ni * 4;
      const px: Rgba = { r: data[o], g: data[o + 1], b: data[o + 2], a: data[o + 3] };
      if (!isBackgroundWhite(px)) continue;
      visited[ni] = 1;
      queue.push(ni);
    }
  }

  return remove;
}

function applyMask(data: Buffer, remove: Uint8Array): Buffer {
  const out = Buffer.from(data);
  for (let i = 0; i < remove.length; i++) {
    if (remove[i]) out[i * 4 + 3] = 0;
  }
  return out;
}

function contentBounds(data: Buffer, width: number, height: number): {
  left: number;
  top: number;
  right: number;
  bottom: number;
} | null {
  let left = width;
  let top = height;
  let right = -1;
  let bottom = -1;

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (data[(y * width + x) * 4 + 3] === 0) continue;
      left = Math.min(left, x);
      top = Math.min(top, y);
      right = Math.max(right, x);
      bottom = Math.max(bottom, y);
    }
  }

  if (right < 0) return null;
  return { left, top, right, bottom };
}

async function processIcon(inputPath: string, outDir: string) {
  const { data, info } = await sharp(inputPath)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const remove = maskOuterWhite(data, info.width, info.height);
  const masked = applyMask(data, remove);
  const bounds = contentBounds(masked, info.width, info.height);
  if (!bounds) throw new Error("No visible content after trimming white");

  const cropW = bounds.right - bounds.left + 1;
  const cropH = bounds.bottom - bounds.top + 1;
  const side = Math.max(cropW, cropH);
  const padLeft = Math.floor((side - cropW) / 2);
  const padTop = Math.floor((side - cropH) / 2);

  const cropped = await sharp(masked, {
    raw: { width: info.width, height: info.height, channels: 4 },
  })
    .extract({ left: bounds.left, top: bounds.top, width: cropW, height: cropH })
    .extend({
      top: padTop,
      bottom: side - cropH - padTop,
      left: padLeft,
      right: side - cropW - padLeft,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .resize(OUTPUT_SIZE, OUTPUT_SIZE, { fit: "fill" })
    .png()
    .toBuffer();

  mkdirSync(outDir, { recursive: true });

  const foregroundPath = path.join(outDir, "adaptive_foreground.png");
  await sharp(cropped).png().toFile(foregroundPath);

  const iconPath = path.join(outDir, "icon.png");
  await sharp(cropped)
    .flatten({ background: BRAND_YELLOW })
    .png()
    .toFile(iconPath);

  console.log(`Trimmed ${info.width}x${info.height} -> crop ${cropW}x${cropH} -> ${OUTPUT_SIZE}x${OUTPUT_SIZE}`);
  console.log(`Wrote ${iconPath}`);
  console.log(`Wrote ${foregroundPath}`);
}

const input = process.argv[2];
const outDir = process.argv[3] ? path.resolve(process.argv[3]) : DEFAULT_OUT;

if (!input) {
  console.error("Usage: npm run trim -- <input.png> [output-dir]");
  process.exit(1);
}

processIcon(path.resolve(input), outDir).catch((err) => {
  console.error(err);
  process.exit(1);
});

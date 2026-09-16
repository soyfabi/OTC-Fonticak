const fs = require('fs');
const zlib = require('zlib');

const W = 20, H = 20;
const rgba = Buffer.alloc(W * H * 4, 0);
const mark = [192, 192, 192, 255];

function setPixel(x, y, c) {
  if (x < 0 || y < 0 || x >= W || y >= H) return;
  const i = (y * W + x) * 4;
  rgba[i] = c[0];
  rgba[i + 1] = c[1];
  rgba[i + 2] = c[2];
  rgba[i + 3] = c[3];
}

// Proper question mark: open curve, stem, separated dot (vertically centered in 20x20)
const art = [
  '....................',
  '....................',
  '....................',
  '....................',
  '....................',
  '........####........',
  '.......##..##.......',
  '......##....##......',
  '......##....##......',
  '.........##.........',
  '........##..........',
  '........##..........',
  '........##..........',
  '....................',
  '........###.........',
  '........###.........',
  '....................',
  '....................',
  '....................',
  '....................',
];

for (let y = 0; y < art.length; y++) {
  for (let x = 0; x < art[y].length; x++) {
    if (art[y][x] === '#') {
      setPixel(x, y, mark);
    }
  }
}

function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) {
      c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
  }
  return (~c) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const typeBuf = Buffer.from(type);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
  return Buffer.concat([len, typeBuf, data, crcBuf]);
}

const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0);
ihdr.writeUInt32BE(H, 4);
ihdr[8] = 8;
ihdr[9] = 6;

const stride = W * 4 + 1;
const raw = Buffer.alloc(stride * H);
for (let y = 0; y < H; y++) {
  raw[y * stride] = 0;
  rgba.copy(raw, y * stride + 1, y * W * 4, (y + 1) * W * 4);
}

const png = Buffer.concat([
  signature,
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw)),
  chunk('IEND', Buffer.alloc(0))
]);

const out = 'C:/Users/fabim/Downloads/OTC-Fonticak/data/images/ui/lenshelp_icon.png';
fs.writeFileSync(out, png);
console.log('written', out);

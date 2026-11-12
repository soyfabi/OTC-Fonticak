"""Build optional HD animation atlases from export_animation.lua and a matching HD pack."""
import argparse
from collections import defaultdict
from functools import lru_cache
from math import lcm
from pathlib import Path
from struct import unpack_from

import numpy as np
from PIL import Image

CHUNK = 512
SPRITE = 32
MAX_FRAMES = 16


class StaticFrameMismatch(ValueError):
    pass


def read_types(path):
    types = {}
    for line in path.read_text().splitlines():
        item, w, h, layers, nx, ny, nz, phases, dx, dy, *sprites = map(int, line.split())
        if len(sprites) != w * h * layers * nx * ny * nz * phases:
            raise ValueError(f"Unexpected sprite layout for item {item}")
        types[item] = (w, h, layers, nx, ny, nz, phases, dx, dy, sprites)
    return types


def sprite_reader(path, expected_signature):
    data = path.read_bytes()
    signature, count = unpack_from("<II", data)
    if signature != expected_signature:
        raise ValueError("SPR signature does not match the HD pack")

    @lru_cache(maxsize=8192)
    def read_sprite(sprite):
        if not 1 <= sprite <= count:
            return None
        offset, = unpack_from("<I", data, 8 + (sprite - 1) * 4)
        if not offset:
            return None
        size, = unpack_from("<H", data, offset + 3)
        cursor, pixel = offset + 5, 0
        end = cursor + size
        rgba = bytearray(SPRITE * SPRITE * 4)
        while cursor < end:
            transparent, colored = unpack_from("<HH", data, cursor)
            cursor += 4
            pixel += transparent
            for _ in range(colored):
                rgba[pixel * 4:pixel * 4 + 4] = data[cursor:cursor + 3] + b"\xff"
                pixel += 1
                cursor += 3
        image = Image.frombytes("RGBA", (SPRITE, SPRITE), bytes(rgba))
        return image, image.getchannel("A")

    return read_sprite


def chunks_for_floor(path, types, base_chunks):
    operations = defaultdict(list)
    periods = {}
    for line in path.read_text().splitlines():
        if not line:
            continue
        item, x, y, px, py, pz = map(int, line.split())
        w, h, layers, nx, ny, nz, phases, dx, dy, sprites = types[item]
        x, y = x - dx, y - dy
        stride = w * h * layers * nx * ny * nz
        pattern = ((pz * ny + py) * nx + px) * layers
        for layer in range(layers):
            for col in range(w):
                for row in range(h):
                    sx, sy = x - col * SPRITE, y - row * SPRITE
                    first = ((pattern + layer) * h + row) * w + col
                    ids = tuple(sprites[first + stride * frame] for frame in range(phases))
                    if not any(ids):
                        continue
                    if all(sprite == ids[0] for sprite in ids):
                        ids = ids[:1]
                    for cy in range(sy // CHUNK, (sy + SPRITE - 1) // CHUNK + 1):
                        for cx in range(sx // CHUNK, (sx + SPRITE - 1) // CHUNK + 1):
                            key = (cx, cy)
                            if key not in base_chunks:
                                continue
                            operations[key].append((sx - cx * CHUNK, sy - cy * CHUNK, ids))
                            if len(ids) > 1:
                                periods[key] = lcm(periods.get(key, 1), len(ids))
    return operations, periods


def render(operations, read_sprite, phase):
    image = Image.new("RGBA", (CHUNK, CHUNK))
    for x, y, ids in operations:
        sprite = read_sprite(ids[phase % len(ids)])
        if sprite is not None:
            image.paste(sprite[0], (x, y), sprite[1])
    return np.asarray(image)


def build_atlas(base, operations, frames, read_sprite):
    reference = render(operations, read_sprite, 0)
    images = [base]
    dirty = np.zeros((CHUNK, CHUNK), dtype=bool)
    for phase in range(1, frames):
        current = render(operations, read_sprite, phase)
        changed = np.any(current != reference, axis=2)
        dirty |= changed
        images.append(np.where(changed[:, :, None], current, base))
    if np.any(base[dirty] != reference[dirty]):
        raise StaticFrameMismatch

    # Keep adjacent samples so linear filtering sees the original edge colors.
    padded = np.pad(dirty, 1)
    dirty = np.logical_or.reduce([
        padded[y:y + CHUNK, x:x + CHUNK] for y in range(3) for x in range(3)
    ])
    ys, xs = np.nonzero(dirty)
    if not len(xs):
        return None

    left, right = int(xs.min()), int(xs.max()) + 1
    top, bottom = int(ys.min()), int(ys.max()) + 1
    # An overlay can replace opaque pixels or draw where the base is empty.
    # If a frame uncovers the map background, replace the complete chunk.
    occupied = dirty & (base[:, :, 3] != 0)
    replace = any(np.any(image[:, :, 3][occupied] != 255) for image in images)
    if replace:
        left, top, right, bottom = 0, 0, CHUNK, CHUNK
    width, height = right - left, bottom - top
    columns = min(4, frames)
    atlas = Image.new("RGBA", (columns * (width + 2), ((frames + columns - 1) // columns) * (height + 2)))
    for phase, image in enumerate(images):
        if not replace:
            image = np.where(dirty[:, :, None], image, 0)
        crop = np.pad(image[top:bottom, left:right], ((1, 1), (1, 1), (0, 0)), mode="edge")
        atlas.paste(Image.fromarray(crop), ((phase % columns) * (width + 2), (phase // columns) * (height + 2)))
    return atlas, (left, top, width, height, int(replace))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("spr", type=Path)
    parser.add_argument("pack", type=Path)
    parser.add_argument("output", type=Path, help="new animation directory to install inside the HD pack")
    args = parser.parse_args()
    header, *chunks = (args.pack / "index.txt").read_text().splitlines()
    magic, version, chunk, tile, dat, spr, count = header.split()
    if (magic, version, chunk, tile) != ("ASTRAHD", "1", "16", "32") or int(count) != len(chunks):
        raise ValueError("Unsupported HD pack")
    if (args.source / "signatures.txt").read_text().split() != [dat, spr]:
        raise ValueError("Exported DAT/SPR signatures do not match the HD pack")
    types = read_types(args.source / "types.txt")
    read_sprite = sprite_reader(args.spr, int(spr))
    args.output.mkdir()
    entries = []
    approximated = 0
    mismatched = 0
    for floor in range(16):
        base_chunks = {}
        for line in chunks:
            level, x, y, z, filename = line.split()
            if int(level) == 1 and int(z) == floor:
                base_chunks[(int(x) // 16, int(y) // 16)] = filename
        operations, periods = chunks_for_floor(args.source / f"{floor}.txt", types, base_chunks)
        for (cx, cy), period in sorted(periods.items()):
            sprites = operations[cx, cy]
            frames = period
            if frames > MAX_FRAMES:
                # Prefer the longest supported cycle when different items have
                # incompatible periods. Keep atlas size bounded.
                frames = min(MAX_FRAMES, max(len(ids) for _, _, ids in sprites))
            with Image.open(args.pack / base_chunks[cx, cy]) as static:
                try:
                    result = build_atlas(np.asarray(static.convert("RGBA")), sprites, frames, read_sprite)
                except StaticFrameMismatch:
                    mismatched += 1
                    continue
            if result is None:
                continue
            atlas, rect = result
            approximated += frames != period
            x, y = cx * 16, cy * 16
            atlas.save(args.output / f"animation-{x}-{y}-{floor}.png", compress_level=3)
            entries.append(f"{x} {y} {floor} {frames} " + " ".join(map(str, rect)))
        print(f"Floor {floor}: {len(entries)} animated chunks so far", flush=True)
    (args.output / "index.txt").write_text(
        f"FONTICAKHDANIM 2 {dat} {spr} {len(entries)}\n" + "\n".join(entries) + "\n", encoding="ascii"
    )
    print(f"{len(entries)} atlases generated ({approximated} with shortened mixed cycles); "
          f"{mismatched} chunks kept static due to frame mismatch")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Writes the data the benchmark (test/bench.asm) plays back.

    bench_data.py <directory>

bench_frames.bin: six frames of an animation, each drawn from the top
with ESC [ H as Telehack's starwars does: 13 rows of 78 characters,
mostly spaces, of which only some 60 cells change from one frame to the
next. The last frame leads back to the first, so the data can repeat.

bench_text.bin: about 4 KB of BBS text that scrolls: words in changing
colours, and rows of CP437 shading and blocks on coloured backgrounds,
with a status line on top now and then.

Both are the same on every run (a fixed seed).
"""

import os
import random
import sys

ESC = "\x1b"
WIDTH, HEIGHT = 78, 13


def frames(rnd):
    stars = [(rnd.randrange(WIDTH), rnd.randrange(HEIGHT - 1)) for _ in range(40)]
    caption = "   a long time ago, in a terminal far, far away ...   "
    out = ESC + "[?25l"
    for frame, shift in enumerate([0, 1, 2, 3, 2, 1]):
        rows = [[" "] * WIDTH for _ in range(HEIGHT)]
        for i, (x, y) in enumerate(stars):
            if i % 3 != frame % 3:              # a third of them twinkle off
                rows[y][x] = "."
        centre = 20 + shift
        for y in range(1, 10):                  # a ball of 8s that moves
            half = int(7 * (1 - ((y - 5) / 4.6) ** 2) ** 0.5)
            for x in range(centre - half, centre + half + 1):
                rows[y][x] = "8"
        text = caption[frame:] + caption[:frame]
        for x, c in enumerate(text):
            rows[HEIGHT - 1][12 + x] = c
        out += ESC + "[H" + "".join("".join(r) + "\r\n" for r in rows)
    return out.encode("ascii")


def text(rnd):
    words = ["the", "new", "files", "message", "board", "sysop", "chat", "games",
             "welcome", "users", "online", "door", "upload", "download", "ansi"]
    blocks = [0xb0, 0xb1, 0xb2, 0xdb, 0xdc, 0xdf]
    out = bytearray()
    status_lines = 0
    while len(out) < 4000:
        line, length = bytearray(), 0
        if rnd.random() < 0.5:
            while True:
                word = rnd.choice(words) + " "
                if length + len(word) > 79:
                    break
                line += f"{ESC}[{rnd.randrange(2)};3{rnd.randrange(1, 8)}m{word}".encode()
                length += len(word)
        else:
            while True:
                run = rnd.randrange(2, 9)
                if length + run > 79:
                    break
                line += f"{ESC}[3{rnd.randrange(1, 8)};4{rnd.randrange(8)}m".encode()
                line += bytes([rnd.choice(blocks)]) * run
                length += run
        out += line + f"{ESC}[0m\r\n".encode()
        if len(out) // 1000 != status_lines:        # now and then a status line
            status_lines += 1                       # on top, as some BBSes do
            status = f" {status_lines} new messages ".ljust(80)
            out += f"{ESC}7{ESC}[H{ESC}[1;37;44m{status}{ESC}[0m{ESC}8".encode()
    return bytes(out)


def main():
    directory = sys.argv[1]
    os.makedirs(directory, exist_ok=True)
    rnd = random.Random(64)
    for name, data in (("bench_frames.bin", frames(rnd)), ("bench_text.bin", text(rnd))):
        with open(os.path.join(directory, name), "wb") as f:
            f.write(data)


if __name__ == "__main__":
    main()

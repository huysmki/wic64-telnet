#!/usr/bin/env python3
"""Runs one test build in VICE and writes what it ended up with.

    run_test.py <test.prg> <labels> <output.txt> [--disk <d64>] [--png <file>]

Starts x64sc (override with $VICE) with the binary monitor, stops at
test_finished (the scenario's TK_END) and writes a text report: the
screen as text, then screen codes and colours per row, then every byte
the client sent to the fake server. In 80 columns the screen is the
80-column cells followed by the text screen (whose bottom rows show
below them), and a checksum of the bitmap the cells are drawn on. `make check` compares these reports
with test/expected/.
"""

import hashlib
import os
import signal
import socket
import struct
import subprocess
import sys
import time

TIMEOUT = 60

CMD_MEMORY_GET = 0x01
CMD_BANKS_AVAILABLE = 0x82
CMD_CHECKPOINT_SET = 0x12
CMD_EXIT = 0xAA
CMD_QUIT = 0xBB
EVENT_STOPPED = 0x62
EVENT_RESUMED = 0x63


class Monitor:
    """Client for VICE's binary monitor protocol."""

    def __init__(self, vice, port):
        deadline = time.time() + TIMEOUT
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), 1)
                break
            except OSError:
                if vice.poll() is not None:
                    sys.exit(f"VICE exited at start-up (try running: {' '.join(vice.args)})")
                if time.time() > deadline:
                    raise
                time.sleep(0.2)
        self.sock.settimeout(TIMEOUT)
        self.request_id = 0
        self.buffer = b""

    def _read(self, n):
        while len(self.buffer) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("VICE closed the monitor connection")
            self.buffer += chunk
        data, self.buffer = self.buffer[:n], self.buffer[n:]
        return data

    def _response(self):
        header = self._read(12)
        _stx, _api, length, kind, error, request_id = struct.unpack("<BBIBBI", header)
        return kind, error, request_id, self._read(length)

    def send(self, command, body=b""):
        self.request_id += 1
        self.sock.sendall(struct.pack("<BBII", 2, 2, len(body), self.request_id)
                          + bytes([command]) + body)
        while True:
            kind, error, request_id, data = self._response()
            if request_id == self.request_id:
                if error:
                    raise RuntimeError(f"monitor command {command:#x} failed: {error:#x}")
                return data

    def run_until_stopped(self):
        """Resumes the emulator (every command pauses it) until a checkpoint."""
        self.send(CMD_EXIT)
        resumed = False
        while True:
            kind, _error, _request_id, _data = self._response()
            if kind == EVENT_RESUMED:
                resumed = True
            elif kind == EVENT_STOPPED and resumed:
                return

    def break_at(self, address):
        # start, end, stop when hit, enabled, operation (4 = exec), temporary
        self.send(CMD_CHECKPOINT_SET, struct.pack("<HHBBBB", address, address, 1, 1, 4, 0))

    def memory(self, start, end, bank=0):
        # side effects, start, end, memspace (0 = main CPU), bank (0 = CPU view)
        data = self.send(CMD_MEMORY_GET, struct.pack("<BHHBH", 0, start, end, 0, bank))
        length = struct.unpack("<H", data[:2])[0]
        return data[2:2 + length]

    def bank(self, name):
        """The ID of a memory bank, e.g. "ram" for the RAM under the ROMs."""
        data = self.send(CMD_BANKS_AVAILABLE)
        count = struct.unpack("<H", data[:2])[0]
        i = 2
        for _ in range(count):
            size = data[i]
            bank_id, name_length = struct.unpack("<HB", data[i + 1:i + 4])
            if data[i + 4:i + 4 + name_length].decode() == name:
                return bank_id
            i += 1 + size
        raise RuntimeError(f"VICE has no memory bank {name!r}")

    def quit(self):
        try:
            self.send(CMD_QUIT)
        except (ConnectionError, OSError):
            pass


def free_port():
    """A port no other VICE (say, one still shutting down) is listening on."""
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def read_labels(path):
    labels = {}
    for line in open(path):
        parts = line.split("=")
        if len(parts) == 2:
            value = parts[1].split(";")[0].strip()
            if value.startswith("$"):
                labels[parts[0].strip()] = int(value[1:], 16)
    return labels


def screen_char(code):
    """An approximation of a screen code as text (either character set)."""
    code &= 0x7F
    if code == 0:
        return "@"
    if code < 0x1B:
        return chr(ord("a") + code - 1)
    if code < 0x20:
        return "[\\]^_"[code - 0x1B]
    if code < 0x40:
        return chr(code)
    if code == 0x40:
        return "-"
    if code < 0x5B:
        return chr(code)
    return "#"


def screen_rows(screen, colors, columns, rows):
    """Splits screen codes and colours into (codes, colours) per row."""
    return [(screen[r * columns:(r + 1) * columns], colors[r * columns:(r + 1) * columns])
            for r in range(rows)]


def report(rows, bitmap_digest, sent):
    lines = ["Screen:"]
    for cells, _ in rows:
        text = "".join(screen_char(c) for c in cells)
        lines.append(f"  |{text}|")
    lines.append("")
    lines.append("Screen codes and colours:")
    for row, (cells, cols) in enumerate(rows):
        lines.append(f"  {row:2} " + cells.hex())
        lines.append("     " + "".join(f"{c & 15:x}" for c in cols))
    lines.append("")
    if bitmap_digest:
        lines.append(f"Bitmap: {bitmap_digest}")
        lines.append("")
    lines.append(f"Sent ({len(sent)} bytes):")
    for i in range(0, len(sent), 16):
        chunk = sent[i:i + 16]
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"  {chunk.hex(' '):<47}  {text}")
    return "\n".join(lines) + "\n"


def main():
    args = sys.argv[1:]
    disk = png = None
    if "--disk" in args:
        i = args.index("--disk")
        disk = args[i + 1]
        del args[i:i + 2]
    if "--png" in args:
        i = args.index("--png")
        png = args[i + 1]
        del args[i:i + 2]
    prg, labels_path, output = args
    labels = read_labels(labels_path)
    port = free_port()

    command = [os.environ.get("VICE", "x64sc"), "-default", "-warp", "-minimized",
               "-sounddev", "dummy", "-binarymonitor",
               "-binarymonitoraddress", f"ip4://127.0.0.1:{port}",
               "-autostartprgmode", "1"]
    if disk:
        command += ["-8", disk]
    if png:
        command += ["-exitscreenshot", png]
    command += ["-autostart", prg]

    # its own process group: macOS builds start x64sc through a wrapper script
    vice = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    try:
        monitor = Monitor(vice, port)
        monitor.break_at(labels["test_finished"])
        monitor.run_until_stopped()
        screen = monitor.memory(0x0400, 0x07E7)
        colors = monitor.memory(0xD800, 0xDBE7)
        rows = screen_rows(screen, colors, 40, 25)
        bitmap_digest = None
        if monitor.memory(labels["term_columns"], labels["term_columns"])[0] == 80:
            # the bitmap's cells, found through the terminal's table of
            # rows, then the text screen (status line, popup boxes) that
            # shows below them
            color_offset = labels["CELLS80_COLORS"] - labels["CELLS80"]
            lo = monitor.memory(labels["term_cells_lo"], labels["term_cells_lo"] + 23)
            hi = monitor.memory(labels["term_cells_hi"], labels["term_cells_hi"] + 23)
            cells = [lo[r] | hi[r] << 8 for r in range(24)]
            rows = [(monitor.memory(c, c + 79), monitor.memory(c + color_offset, c + color_offset + 79))
                    for c in cells] + rows
            ram = monitor.bank("ram")
            bitmap = labels["BITMAP80"]
            matrix = labels["MATRIX80"]
            bitmap_digest = hashlib.sha1(monitor.memory(bitmap, bitmap + 7999, ram)
                                         + monitor.memory(matrix, matrix + 999, ram)).hexdigest()
        pointer = monitor.memory(labels["test_tx_pointer"], labels["test_tx_pointer"] + 1)
        tx_end = pointer[0] | pointer[1] << 8
        sent = monitor.memory(0x9000, tx_end - 1) if tx_end > 0x9000 else b""
        monitor.quit()
        vice.wait(TIMEOUT)
    finally:
        try:
            os.killpg(vice.pid, signal.SIGKILL)
        except OSError:             # already gone
            pass

    with open(output, "w") as f:
        f.write(report(rows, bitmap_digest, sent))


if __name__ == "__main__":
    main()

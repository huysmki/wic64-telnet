#!/usr/bin/env python3
"""A small BBS to test the client against: a message editor, as C64 BBSes have.

    test_bbs.py [--port N] [--width W] [--erase del|crsr] [--status S]
                [--noise BYTES] [--welcome FILE] [--dir DIR]

Listens on port N (6464 by default) and prints the address to connect to:
in VICE 127.0.0.1:N, from a real C64 this computer's address (on the same
network). Connect in PETSCII mode, with O on the start screen or an entry.

The editor works like those of C64 BBSes: it echoes every key, and when a
line is full (W characters, 39 by default) it wraps the last word onto the
next line, deleting it first with DEL (--erase del) or with cursor left,
space, cursor left (--erase crsr). RETURN starts a new line, DEL deletes.
On a line of its own, .S shows the message so far, .C clears it and .Q
hangs up. No login, and nothing is posted anywhere.

Like a BBS with more users, it can also update a line of the screen while
you type (--status S: every S seconds): it moves the cursor there with
HOME and cursor down/right, writes, and moves back to where you were
typing. --noise adds that many bytes of other text to every update, as a
busy BBS sends, so that reads bring a lot. --welcome sends a file first, such as a BBS's welcome screen
recorded with telnet_proxy.py (its .server.bin).

Every session is recorded as telnet_proxy.py does: session-<time>.log,
.server.bin and .client.bin in DIR (the current directory by default).
"""

import argparse
import datetime
import functools
import os
import select
import socket
import time

print = functools.partial(print, flush=True)

CLEAR, HOME = b"\x93", b"\x13"
WHITE, GREEN, YELLOW, CYAN, GREY = b"\x05", b"\x1e", b"\x9e", b"\x9f", b"\x98"
RETURN, DEL, LEFT = 0x0d, 0x14, 0x9d
LOWER_CASE = b"\x0e"


def pet(text):
    """ASCII text as PETSCII for the lower/upper case set."""
    out = bytearray()
    for ch in text:
        c = ord(ch)
        if "a" <= ch <= "z":
            c -= 0x20
        elif "A" <= ch <= "Z":
            c += 0x80
        elif ch == "\n":
            c = RETURN
        out.append(c)
    return bytes(out)


def local_address():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("192.0.2.1", 9))     # no packet is sent
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


class Session:
    def __init__(self, conn, args, base):
        self.conn = conn
        self.args = args
        self.start = datetime.datetime.now()
        self.log = open(base + ".log", "w")
        self.server_bin = open(base + ".server.bin", "wb")
        self.client_bin = open(base + ".client.bin", "wb")
        self.log.write("# BBS> = from this BBS to the client, C64> = from the client\n")
        self.lines = []
        self.line = bytearray()
        self.row = 0                    # where the editor's cursor is on
        self.updates = 0                # the client's screen

    def _log(self, direction, data):
        elapsed = (datetime.datetime.now() - self.start).total_seconds()
        for i in range(0, len(data), 16):
            chunk = data[i:i + 16]
            stamp = f"{elapsed:9.3f} {direction}" if i == 0 else " " * 11
            text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
            self.log.write(f"{stamp}  {chunk.hex(' '):<47}  {text}\n")
        self.log.flush()

    def send(self, data):
        self.conn.sendall(data)
        self.server_bin.write(data)
        self.server_bin.flush()
        self._log("BBS>", data)

    def erase(self, count):
        if self.args.erase == "del":
            return bytes([DEL]) * count
        return bytes([LEFT, 0x20, LEFT]) * count

    def welcome(self):
        if self.args.welcome:
            with open(self.args.welcome, "rb") as f:
                self.send(f.read())
        self.send(LOWER_CASE + CLEAR + YELLOW + pet("WiC64 test BBS\n\n") + GREEN
                  + pet(f"A message editor: lines wrap at {self.args.width}.\n")
                  + pet("On a line of its own: .S shows it,\n.C clears it, .Q hangs up.\n\n")
                  + WHITE)
        self.row = 7

    def newline(self):
        self.row = min(self.row + 1, 24)    # the screen scrolls at the end

    def status(self):
        """Writes the status line at row 1 and goes back to the editor."""
        self.updates += 1
        text = GREY + bytes([0x12]) + pet(f" {self.updates % 9 + 1} people online ") + bytes([0x92]) + WHITE
        back = HOME + bytes([0x11]) * self.row + bytes([0x1d]) * len(self.line)
        noise = b""
        if self.args.noise:
            line = pet("someone else is chatting on another node. ")
            noise = HOME + bytes([0x11]) * 2 + (line * (self.args.noise // len(line) + 1))[:self.args.noise]
        self.send(HOME + bytes([0x11]) + bytes([0x1d]) * 12 + text + noise + back)

    def show(self):
        out = CYAN + pet("\nThe message:\n") + WHITE
        for line in self.lines:
            out += bytes(line) + bytes([RETURN])
        out += GREY + pet(f"({len(self.lines)} lines)\n\n") + WHITE
        self.send(out)

    def key(self, b):
        """Handles one key; returns False to hang up."""
        if b == RETURN:
            line = bytes(self.line)         # unshifted letters: .S is b".S"
            self.line = bytearray()
            self.newline()
            if line == b".S":
                self.send(bytes([RETURN]))
                self.show()
            elif line == b".C":
                self.lines = []
                self.send(bytes([RETURN]) + GREY + pet("Cleared.\n") + WHITE)
            elif line == b".Q":
                self.send(bytes([RETURN]) + pet("Bye.\n"))
                return False
            else:
                self.lines.append(line)
                self.send(bytes([RETURN]))
        elif b in (DEL, 0x08, 0x7f):
            if self.line:
                self.line.pop()
                self.send(self.erase(1) if self.args.erase == "crsr" else bytes([DEL]))
        elif b >= 0x20 and b != 0x7f and not 0x80 <= b < 0xa0:
            if len(self.line) < self.args.width:
                self.line.append(b)
                self.send(bytes([b]))
            elif b == 0x20:                 # a space at the end: just a new line
                self.newline()
                self.lines.append(bytes(self.line))
                self.line = bytearray()
                self.send(bytes([RETURN]))
            else:                           # wrap the last word onto a new line
                self.newline()
                space = bytes(self.line).rfind(b" ")
                word = bytes(self.line[space + 1:]) if space >= 0 else b""
                self.lines.append(bytes(self.line[:space]) if space >= 0 else bytes(self.line))
                self.line = bytearray(word + bytes([b]))
                self.send(self.erase(len(word)) + bytes([RETURN]) + word + bytes([b]))
        return True

    def run(self):
        self.welcome()
        next_status = time.time() + (self.args.status or 0)
        while True:
            if self.args.status:
                wait = max(0, next_status - time.time())
                if not select.select([self.conn], [], [], wait)[0]:
                    self.status()
                    next_status = time.time() + self.args.status
                    continue
            data = self.conn.recv(4096)
            if not data:
                return
            self.client_bin.write(data)
            self.client_bin.flush()
            self._log("C64>", data)
            for b in data:
                if not self.key(b):
                    return
            if self.args.status and time.time() >= next_status:
                self.status()               # also while the user types
                next_status = time.time() + self.args.status

    def close(self):
        for f in (self.log, self.server_bin, self.client_bin):
            f.close()
        self.conn.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--port", type=int, default=6464)
    parser.add_argument("--width", type=int, default=39)
    parser.add_argument("--erase", choices=("del", "crsr"), default="del")
    parser.add_argument("--status", type=float, default=0)
    parser.add_argument("--noise", type=int, default=0)
    parser.add_argument("--welcome")
    parser.add_argument("--dir", default=".")
    args = parser.parse_args()

    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("0.0.0.0", args.port))
    listener.listen(1)
    print(f"Test BBS on {local_address()}:{args.port} (VICE: 127.0.0.1:{args.port}). Ctrl-C stops.")
    while True:
        conn, address = listener.accept()
        base = os.path.join(args.dir, datetime.datetime.now().strftime("session-%Y%m%d-%H%M%S"))
        print(f"{address[0]} connected; recording to {base}.*")
        session = Session(conn, args, base)
        try:
            session.run()
        except OSError as e:
            print(f"Connection lost: {e}")
        finally:
            session.close()
        print("Session ended.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()

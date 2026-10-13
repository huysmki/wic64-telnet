#!/usr/bin/env python3
"""Records a session between the client and a BBS.

    telnet_proxy.py host:port [--port N] [--dir DIR]

Listens on port N (6464 by default) and passes everything on to the BBS
at host:port, both ways, unchanged.
Connect the client to this computer instead of to the BBS: in VICE to
127.0.0.1:N, from a real C64 to the address printed at start-up (both
on the same network). Use O on the start screen, or add an entry.

Every session is written to DIR (the current directory by default):

    session-<time>.log         what went each way, with the time it took,
                               in hex and as text
    session-<time>.server.bin  everything the BBS sent, for replaying
    session-<time>.client.bin  everything the client sent

The client's file holds what you type, passwords included, and so does
the log: delete them when you no longer need them.
"""

import argparse
import datetime
import functools
import os
import select
import socket

print = functools.partial(print, flush=True)


def local_address():
    """The address other machines on the network reach this one at."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("192.0.2.1", 9))     # no packet is sent
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def text(data):
    """Printable ASCII as is, everything else as a dot."""
    return "".join(chr(b) if 32 <= b < 127 else "." for b in data)


def log_chunk(log, start, direction, data):
    elapsed = (datetime.datetime.now() - start).total_seconds()
    for i in range(0, len(data), 16):
        chunk = data[i:i + 16]
        stamp = f"{elapsed:9.3f} {direction}" if i == 0 else " " * 11
        log.write(f"{stamp}  {chunk.hex(' '):<47}  {text(chunk)}\n")
    log.flush()


def relay(client, upstream, base):
    start = datetime.datetime.now()
    with open(base + ".log", "w") as log, open(base + ".server.bin", "wb") as server_bin, \
            open(base + ".client.bin", "wb") as client_bin:
        log.write("# BBS> = from the BBS to the client, C64> = from the client to the BBS\n")
        sockets = [client, upstream]
        while True:
            readable, _, _ = select.select(sockets, [], [])
            for s in readable:
                data = s.recv(65536)
                if not data:
                    return
                if s is upstream:
                    client.sendall(data)
                    server_bin.write(data)
                    server_bin.flush()
                    log_chunk(log, start, "BBS>", data)
                else:
                    upstream.sendall(data)
                    client_bin.write(data)
                    client_bin.flush()
                    log_chunk(log, start, "C64>", data)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("upstream", help="the BBS, as host:port")
    parser.add_argument("--port", type=int, default=6464)
    parser.add_argument("--dir", default=".")
    args = parser.parse_args()
    host, port = args.upstream.rsplit(":", 1)

    listener = socket.socket()
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("0.0.0.0", args.port))
    listener.listen(1)
    print(f"Passing sessions on to {host}:{port}.")
    print(f"Connect the client to {local_address()}:{args.port} (VICE: 127.0.0.1:{args.port}).")
    print("Ctrl-C stops.")
    while True:
        client, address = listener.accept()
        base = os.path.join(args.dir, datetime.datetime.now().strftime("session-%Y%m%d-%H%M%S"))
        print(f"{address[0]} connected; recording to {base}.*")
        try:
            upstream = socket.create_connection((host, int(port)), 15)
            upstream.settimeout(None)
        except OSError as e:
            print(f"Can't reach {host}:{port}: {e}")
            client.close()
            continue
        try:
            relay(client, upstream, base)
        except OSError as e:
            print(f"Connection lost: {e}")
        finally:
            client.close()
            upstream.close()
        print("Session ended.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()

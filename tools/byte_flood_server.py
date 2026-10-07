"""Test server that sends every byte as a TCP segment of its own, the way
cib.dyndns.org (Image BBS behind a modem emulator) does. A few hundred of
those in a short time make a WiC64 with firmware 2.1.0 lose its network.

Run it, connect to the address it prints from the telnet client on the C64
(mode PETSCII), and press a key: it then sends numbered lines, one byte per
segment, at about --rate segments a second. Ping the WiC64 meanwhile to see
whether it still answers.

With the system's own send buffer, the bytes pile up here while the WiC64
does not acknowledge them, and once it does, they go out in bigger segments:
the WiC64 then drops off the network for some seconds and recovers. A sender
that keeps sending tiny segments, as the modem emulator behind CIB seems to,
makes it lose the network for good. --buffer makes the send buffer small,
but then the next byte waits for each acknowledgement (some 4 bytes a
second), which is no flood at all.

    python3 tools/byte_flood_server.py [--port 2323] [--rate 450] [--bytes 5000]
                                       [--buffer BYTES]
"""

import argparse, socket, time

def local_ip():
    """The address of this computer on the local network (nothing is sent)."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("192.0.2.1", 9))
        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()

def flood_text(count):
    """count bytes of numbered PETSCII lines ending in RETURN."""
    text = b""
    line = 1
    while len(text) < count:
        text += b"LINE %04d ABCDEFGHIJKLMNOPQRSTUVWXYZ\r" % line
        line += 1
    return text[:count]

def wait_for_key(client):
    """Waits for a key from the C64, ignoring what it sends on connecting
    (telnet negotiation)."""
    time.sleep(1)
    client.setblocking(False)
    try:
        while client.recv(256):
            pass
    except (BlockingIOError, ConnectionError):
        pass
    client.setblocking(True)
    return client.recv(1) != b""

def serve(client, rate, count, buffer):
    client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    if buffer:
        client.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, buffer)
    client.sendall(b"\x93\x05BYTE FLOOD TEST\r\r"
                   b"PRESS A KEY TO RECEIVE %d BYTES,\r"
                   b"EACH IN A TCP SEGMENT OF ITS OWN.\r\r" % count)
    print("Connected; waiting for a key on the C64...")
    if not wait_for_key(client):
        print("The C64 hung up.")
        return
    print(f"Sending {count} bytes, one per segment, at about {rate} a second "
          f"(send buffer {client.getsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF)} bytes).")
    client.settimeout(1)
    data = flood_text(count)
    interval = 1 / rate
    start = last_report = time.time()
    sent = sent_at_report = 0
    while sent < count:
        try:
            client.send(data[sent:sent + 1])
            sent += 1
        except socket.timeout:
            # The send buffer is full: the WiC64 does not acknowledge
            print(f"  {time.time() - start:6.1f} s  stuck at {sent} bytes: "
                  "the WiC64 acknowledges nothing")
            continue
        except ConnectionError as error:
            print(f"Connection lost after {sent} bytes: {error}")
            return
        time.sleep(interval)
        now = time.time()
        if now - last_report >= 1:
            print(f"  {now - start:6.1f} s  {sent:5} bytes sent "
                  f"({(sent - sent_at_report) / (now - last_report):.0f}/s)")
            last_report, sent_at_report = now, sent
    print(f"All {count} bytes sent in {time.time() - start:.1f} s.")
    client.settimeout(None)
    client.sendall(b"\r\rDONE. PRESS A KEY TO HANG UP.\r")
    try:
        client.recv(1)
    except ConnectionError:
        pass

def main():
    parser = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=2323)
    parser.add_argument("--rate", type=int, default=450,
                        help="segments per second (default 450, like CIB)")
    parser.add_argument("--bytes", type=int, default=5000,
                        help="how many bytes to send (default 5000)")
    parser.add_argument("--buffer", type=int, default=0,
                        help="send buffer in bytes (default: the system's)")
    args = parser.parse_args()

    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("", args.port))
    server.listen(1)
    print(f"Enter this in the telnet client on the C64:  "
          f"{local_ip()}:{args.port}   (mode PETSCII)")
    print("Stop with Ctrl+C.\n")
    try:
        while True:
            client, address = server.accept()
            print(f"Connection from {address[0]}")
            with client:
                try:
                    serve(client, args.rate, args.bytes, args.buffer)
                except ConnectionError as error:
                    print(f"Connection lost: {error}")
            print("Waiting for the next connection...\n")
    except KeyboardInterrupt:
        print()

if __name__ == "__main__":
    main()

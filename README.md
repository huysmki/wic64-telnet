# WiC64 Telnet Client 3.0

A Telnet client for the Commodore 64 with a WiC64 (firmware 2.0.0 or later).

**Download:** [`telnet.prg`](https://github.com/huysmki/wic64-telnet/releases/latest/download/telnet.prg)
from the [latest release](https://github.com/huysmki/wic64-telnet/releases/latest)
— copy it to a disk (or SD card) and `LOAD"TELNET.PRG",8` / `RUN`.

To build it yourself with [ACME](https://sourceforge.net/projects/acme-crossass/):
`make` gives `build/telnet.prg`.

## Terminal modes

| Mode    | For                 | Screen                                                                               |
|---------|---------------------|--------------------------------------------------------------------------------------|
| PETSCII | Commodore BBSes     | 40×25, colors and graphics as the BBS sends them                                     |
| ANSI    | PC BBSes            | 40×24 + status line; ANSI/VT100 escape codes, CP437 line drawing and blocks          |
| UTF-8   | Unix hosts, MUDs    | like ANSI, with UTF-8 characters (box drawing, accents → nearest ASCII)              |

Each server in the address book has its own mode (`T` on the start screen).
During a session, `F7` then `M` switches mode. A PETSCII session switches to
ANSI by itself when the server draws with ANSI escape codes (colours, cursor
positioning, clearing). ANSI detection queries such as `ESC [ 5 n`, which
some Commodore BBSes send at login, are ignored and left unanswered, so those
BBSes stay in PETSCII. For a UTF-8 host, press `F7`, `M` once more.

## Keys

Start screen: `CRSR` select, `HOME` first entry, `RETURN` or `1`–`9` connect,
`N` new, `E` edit, `D` delete, `T` mode, `S` save to disk, `O` connect to a
host that isn't in the list (starts in PETSCII mode), `←` WiC64 portal. When
editing, the C64 screen editor overwrites text; use `INST` to insert.

Online: `F1` hang up, `F3` type a whole line (up to 80 characters),
`F5` local echo on/off, `F7` session menu (mode, echo, Telnet break /
interrupt / are-you-there, hang up).

In the ANSI modes the bottom row is a status line: host, mode, `echo` when
local echo is on, and the time online.

In ANSI and UTF-8 modes the keyboard sends ASCII:

| C64 key            | Sends            |
|--------------------|------------------|
| cursor keys, `HOME`, `CLR` | `ESC [ A`–`D`, `ESC [ H`, `ESC [ F` |
| `←`                | ESC              |
| `CTRL`+letter      | control code (e.g. CTRL+C, also CTRL+Q/S) |
| `DEL`              | DEL (`$7F`)      |
| `£` / `SHIFT £`    | `\` / `\|`       |
| `↑` / `SHIFT ↑`    | `^` / `~`        |
| `SHIFT -`, `SHIFT @`, `SHIFT *`, `SHIFT +` | `_`, `` ` ``, `{`, `}` |

## Telnet

The client only answers negotiation; it never starts one. Servers without
Telnet support therefore receive nothing except your keystrokes. It agrees to
BINARY, ECHO, SGA, TTYPE (reports `PETSCII` or `ANSI`) and NAWS (40×25 or
40×24), and refuses every other option. When the server takes over echoing,
local echo is switched off.

`RETURN` sends a bare CR in PETSCII mode (what Commodore BBSes expect) and the
Telnet end of line CR NUL in the ANSI modes (a bare CR in binary mode).

## Connection problems

A request the WiC64 doesn't answer in time is retried quietly up to three
times. After that, or on any other error, a box shows the WiC64's message
with `F1` Abort and `F3` Retry; Retry reconnects if the WiFi or network
connection was lost.

## Address book

The list is stored in `telnet.cfg` on the drive the program was loaded from
(device 8 if unknown). It is loaded at start-up and written when you press `S`.

## Source layout

| File | Contents |
|------|----------|
| `main.asm` | entry point, includes |
| `net.asm` | TCP connection through the WiC64 |
| `telnet.asm` | Telnet protocol and option negotiation |
| `term.asm` | terminal modes, keyboard, cursor |
| `ansi.asm` | ANSI/VT100 screen driver |
| `charmaps.asm` | ASCII character set, CP437/UTF-8/DEC tables |
| `session.asm` | connection loop, session keys, status line, retry |
| `book.asm` | address book start screen, disk load/save |
| `ui.asm` | printing, popup boxes, line input, clock |
| `test/` | fake network and scripted scenarios |

Memory: program `$0801`–`$37FF` (checked at build time), ANSI character set
at `$3800`, buffers from `$4000`.

## Testing

`make test` builds `build/test1.prg` … `build/test10.prg`. In these the WiC64
is replaced by a fake server that plays back a script, and keys come from a
script too (`test/scenarios.asm`): PETSCII with Telnet negotiation, ANSI BBS
output, UTF-8 host output, address book editing, line input, a network error,
saving and loading `telnet.cfg`, and switching to ANSI (or not, for BBSes that
only probe for it). Run one in VICE and look at the screen; what the client
sent is logged at `$9000`.

To use the WiC64 in VICE (user port device "WiC64", `-userportdevice 23`) on
macOS you need VICE 3.10 or later: earlier versions crash on the first WiC64
request (VICE bug #1978).

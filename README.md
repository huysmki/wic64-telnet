# WiC64 Telnet Client 3.1

A Telnet client for the Commodore 64 with a WiC64 (firmware 2.0.0 or later).

**Download:** [`telnet.prg`](https://github.com/huysmki/wic64-telnet/releases/latest/download/telnet.prg)
from the [latest release](https://github.com/huysmki/wic64-telnet/releases/latest)
— copy it to a disk (or SD card) and `LOAD"TELNET.PRG",8` / `RUN`.

To build it yourself with [ACME](https://sourceforge.net/projects/acme-crossass/):
`make` gives `build/telnet.prg`.

![The start screen with the address book](docs/screenshots/address-book.png)

| PETSCII | PETSCII |
|---------|---------|
| <img src="docs/screenshots/petscii-retrocampus.png" width="384" alt="RetroCampus BBS in PETSCII mode"> | <img src="docs/screenshots/petscii-rapidfire.png" width="384" alt="Rapidfire BBS in PETSCII mode"> |
| **ANSI** | **UTF-8** |
| <img src="docs/screenshots/ansi-vertrauen.png" width="384" alt="Vertrauen, a Synchronet BBS, in ANSI mode"> | <img src="docs/screenshots/utf8-telehack.png" width="384" alt="Telehack in UTF-8 mode"> |

*RetroCampus, Rapidfire, Vertrauen and Telehack, taken in VICE with its WiC64
emulation.*

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

The C64 has one background colour, so a coloured ANSI background shows as
reverse video in that colour. Blink shows as a bright background (iCE
colours), which is what most PC BBS art means by it. 256-colour and true
colour codes show as the nearest of the 16 ANSI colours. Full-screen Unix
programs get an alternate screen (the screen comes back when vim or less
exits) and application cursor keys when they ask for them.

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
| cursor keys, `HOME`, `CLR` | `ESC [ A`–`D`, `ESC [ H`, `ESC [ F` (`ESC O …` when the host asks for application cursor keys) |
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

It comes with nine servers that were online when this version was made:

| # | Server | Mode |
|---|--------|------|
| 1 | `8bit.hoyvision.com:6502` (8-Bit Playground) | PETSCII |
| 2 | `cib.dyndns.org:6405` | PETSCII |
| 3 | `cottonwoodbbs.dyndns.org:6502` | PETSCII |
| 4 | `rapidfire.hopto.org:64128` | PETSCII |
| 5 | `raveolution.hopto.org:64128` | PETSCII |
| 6 | `bbs.fozztexx.com:23` (Level 29) | PETSCII |
| 7 | `bbs.retrocampus.com:6510` | PETSCII |
| 8 | `vert.synchro.net:23` (Vertrauen, home of Synchronet) | ANSI |
| 9 | `telehack.com:23` | UTF-8 |

Telehack ignores the window size and writes 80-column text, so its longer
lines wrap onto two rows.

The list is stored in `telnet.cfg` on the drive the program was loaded from
(device 8 if unknown). It is loaded at start-up and written when you press `S`:
first as `telnet.tmp`, which then replaces `telnet.cfg`, so a failed save
leaves the old list on the disk.

## Credits and licence

Based on the [WiC64 Simple Telnet Client](https://github.com/WiC64-Team/wic64-telnet)
by Henning Liebenau, and built on his
[WiC64 library](https://github.com/WiC64-Team/wic64-library) (`wic64.asm`,
`wic64.h`, included unchanged). Both are under the BSD 2-Clause licence, and
so is this program: see [`LICENSE.txt`](LICENSE.txt), which also applies
to the `telnet.prg` download.

## Source layout

| File | Contents |
|------|----------|
| `main.asm` | entry point, includes |
| `wic64.asm`, `wic64.h` | WiC64 library by Henning Liebenau |
| `net.asm` | TCP connection through the WiC64 |
| `telnet.asm` | Telnet protocol and option negotiation |
| `term.asm` | terminal modes, keyboard, cursor |
| `ansi.asm` | ANSI/VT100 screen driver |
| `charmaps.asm` | ASCII character set, CP437/UTF-8/DEC tables |
| `session.asm` | connection loop, session keys, status line, retry |
| `book.asm` | address book start screen, disk load/save |
| `ui.asm` | printing, popup boxes, line input, clock |
| `test/` | fake network, scripted scenarios, expected results |
| `tools/` | `run_test.py`: runs a test build in VICE for `make check` |

Memory: program `$0801`–`$37FF` (checked at build time), ANSI character set
at `$3800`, buffers (popup boxes, address book loading, the alternate screen)
from `$4000`.

## Testing

`make test` builds `build/test1.prg` … `build/test12.prg`. In these the WiC64
is replaced by a fake server that plays back a script, and keys come from a
script too (`test/scenarios.asm`): PETSCII with Telnet negotiation, ANSI BBS
output, UTF-8 host output, address book editing, line input, a network error,
saving and loading `telnet.cfg`, switching to ANSI (or not, for BBSes that
only probe for it), and the finer points of the ANSI and UTF-8 modes. Run one
in VICE and look at the screen; what the client sent is logged at `$9000`.

`make check` runs them all in VICE (`x64sc` and `c1541` from the PATH or a
VICE in `/Applications`, or set `VICE=` and `C1541=`) and compares the
screen and what was sent with `test/expected/`. Each run also leaves a
screenshot in `build/`. After an intended change, look at the new results
and accept them with `make expected`.

The test builds never touch `net.asm` or the WiC64, so after changing those,
try a real connection too: `x64sc -userportdevice 23 -autostart
build/telnet.prg` starts the client in VICE with its WiC64 emulation (user port
device "WiC64"), which uses the computer's network connection. On macOS this
needs VICE 3.10 or later: earlier versions crash on the first WiC64 request
(VICE bug #1978).

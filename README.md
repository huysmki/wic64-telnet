# WiC64 Telnet Client 3.3

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
| **ANSI** | **UTF-8 80** |
| <img src="docs/screenshots/ansi-vertrauen.png" width="384" alt="Vertrauen, a Synchronet BBS, in ANSI mode"> | <img src="docs/screenshots/utf8-telehack.png" width="384" alt="Telehack in UTF-8 80 mode"> |

*RetroCampus, Rapidfire, Vertrauen and Telehack, taken in VICE with its WiC64
emulation.*

## Terminal modes

| Mode    | For                 | Screen                                                                               |
|---------|---------------------|--------------------------------------------------------------------------------------|
| PETSCII | Commodore BBSes     | 40×25, colors and graphics as the BBS sends them                                     |
| ANSI    | PC BBSes            | 40×24 + status line; ANSI/VT100 escape codes, CP437 line drawing and blocks          |
| UTF-8   | Unix hosts, MUDs    | like ANSI, with UTF-8 characters (box drawing, accents → nearest ASCII)              |
| ANSI 80, UTF-8 80 | the same, for hosts that expect 80 columns | 80×24 + status line, characters 4 pixels wide |

Each server in the address book has its own mode (`T` on the start screen).
During a session, `F7` then `M` switches mode. A PETSCII session switches to
ANSI by itself when the server draws with ANSI escape codes (colours, cursor
positioning, clearing). ANSI detection queries such as `ESC [ 5 n`, which
some Commodore BBSes send at login, are ignored and left unanswered, so those
BBSes stay in PETSCII. For a UTF-8 host, press `F7`, `M` once more.

In every mode, the bell character (sent for chat requests, for example)
flashes the border white and plays a short ping on the SID.

## 80 columns

ANSI 80 and UTF-8 80 put 80 columns on the screen, with characters made 4
pixels wide from the C64's own font when the mode starts (the few letters
that do not suit are drawn by hand). Most Unix hosts and some BBSes expect
80 columns, and their lines then fit instead of wrapping. The status line,
the session menu and line input look as in the other modes.

The screen is a hires bitmap, which has one colour per block of 8×8 pixels:
two characters next to each other share their colour (the left one's,
unless that is a blank). Text looks fine; colourful ANSI art looks better
in 40 columns. Drawing on a bitmap is also more work for the C64, so a
screen full of fast output scrolls more slowly than in 40 columns.

The C64 has one background colour, so a coloured ANSI background shows as
reverse video in that colour. Blink shows as a bright background (iCE
colours), which is what most PC BBS art means by it. 256-colour and true
colour codes show as the nearest of the 16 ANSI colours. Full-screen Unix
programs get an alternate screen (the screen comes back when vim or less
exits) and application cursor keys when they ask for them.

## Keys

Start screen: `CRSR` select, `HOME` first entry, `RETURN` or `1`–`9` connect,
`N` new, `E` edit, `D` delete, `T` mode, `S` save to disk, `O` connect to a
host that isn't in the list (starts in PETSCII mode), `$` the disk's
directory, `@` a disk command (see [Disk directory and
commands](#disk-directory-and-commands)), `←` WiC64 portal. `N`
and `E` ask for the host and then for a name, a user name and a password
(each may stay empty). When
editing, the C64 screen editor overwrites text; use `INST` to insert.

Online: `F1` hang up, `F3` type a whole line (up to 80 characters),
`F4` send the user name and `F6` the password (each followed by `RETURN`, as
if typed), `F5` local echo on/off, `F7` session menu (mode, echo,
scrollback, file download, Telnet break / interrupt / are-you-there, hang
up), `SHIFT F7` scrollback.
`RUN/STOP`+`RESTORE` shows the crash report (see
[If the client hangs](#if-the-client-hangs)); a key then goes to BASIC, where
`RUN` starts the client again.

## File downloads

Many BBSes have file areas. Start the download on the BBS first, then press
`F7`, `D` and pick the protocol:

- `X` **XMODEM**, what PC BBSes (and most others) offer. The client asks for
  CRC and takes 128-byte as well as 1 KB blocks (XMODEM-1K), or falls back to
  a checksum. It asks for the file type (PRG, SEQ or USR). XMODEM pads the
  last block with `$1A` bytes, which stay at the end of the file, as with
  CCGMS: the protocol doesn't say where a file ends.
- `P` **Punter** (C1), the protocol of Commodore BBSes. The sender gives the
  file type, and the file arrives at its exact length.

A Commodore BBS that is ready to send with Punter repeats `GOO` until the
terminal answers. After three `GOO`s in a row the client starts the download
by itself, at once, as some BBSes give up when the answer takes too long.
After a download that stopped or failed, it doesn't start again by itself
until the BBS has sent something else.

**Multi-Punter**, which some BBSes offer, sends several files in one go,
each announced by a header with its name and type, which the BBS repeats
until the terminal answers. The client starts each download as soon as the
header comes, saves the file under that name without asking (unless the
drive refuses it), closes the box at once and is ready for the next one,
until the BBS says there are no more.

The file is saved as `download.tmp` on the drive the program was loaded from
(device 8 if unknown), while a box shows how many bytes have come in; neither
protocol sends the file's name. Once it is complete, the client asks for the
name and renames the file, asking again if the drive refuses (such as
`63, FILE EXISTS`). `RUN/STOP` stops the download (an XMODEM sender is told
to stop too); what came so far stays as `download.tmp`, which the next
download replaces. If the drive reports another error, the box shows it. In VICE, with a 1541, an XMODEM-1K
download ran at about 230 bytes a second.

The client doesn't take Telnet commands out of the data unless the server
spoke Telnet: many Commodore BBSes don't, and their files contain `$FF`.

## Disk directory and commands

On the start screen, `$` lists the directory of the drive the program was
loaded from (device 8 if unknown): the disk's name, every file with its size
in blocks and its type, and the blocks free. Any key pauses the list until
the next key; `RUN/STOP` ends it.

`@` sends a command to that drive and shows its answer below the list, for
example `01, FILES SCRATCHED,01,00` (the number of files at the end). With
no command, it shows the drive's status, such as the reason a save failed.
The commands are the drive's own (CBM DOS); the usual ones:

| Command | Does |
|---------|------|
| `S:NAME` | scratch (delete) a file; `*` and `?` work as wildcards, so `S:PART*` deletes every file starting with `PART` |
| `R:NEW=OLD` | rename the file `OLD` to `NEW` |
| `C:NEW=OLD` | copy a file on the same disk |
| `C:NEW=ONE,TWO` | join two files into a new one |
| `V` | validate: tidy the disk's block map (not on disks with GEOS files) |
| `I` | initialise: read the disk again, after swapping disks |
| `N:NAME,ID` | format the disk with a name and a two-character ID; **erases everything on it** |
| `N:NAME` | the same on a disk formatted before, without an ID: only clears the directory |
| `UJ` | reset the drive |

An SD2IEC or a similar device adds directories and disk images:

| Command | Does |
|---------|------|
| `CD/GAMES` or `CD:GAMES` | change to the directory or the disk image `GAMES` |
| `CD:←` | back to the parent directory (`←` is the key left of `1`) |
| `MD:NAME` | make a directory |
| `RD:NAME` | remove an (empty) directory |

`telnet.cfg` and downloaded files go to the current directory, so after `CD`
the address book is saved there too.

## Scrollback

Rows that scroll off the top of the screen are kept, and so is the whole
screen when the server clears it (Commodore BBSes clear it for almost every
menu). `SHIFT F7`, or `F7` then `S`, shows them above the current screen,
starting a page back: `CRSR` up/down one row, `F1`/`F3` a page up/down,
`HOME` the oldest row, `CLR` the current screen; any other key goes back to
the session. Nothing is read from the server meanwhile, so nothing is missed.

There is room for 16 KB of rows. A row is kept without its trailing blanks,
so that is about 260 full rows, and typically 350 or more; in 80 columns,
which need some of that memory, 7 KB, about 55 full rows. When it is full
the oldest rows make way. The scrollback starts empty when the terminal mode
changes (its rows only look right in their own character set) and at each
connection. In the ANSI modes rows that scroll within a part of the screen
(a full-screen program's scroll region) and the alternate screen are not
kept, and `ESC [ 3 J` empties the scrollback, as in xterm.

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
BINARY, ECHO, SGA, TTYPE (reports `PETSCII` or `ANSI`) and NAWS (40×25,
40×24 or 80×24), and refuses every other option. When the server takes over echoing,
local echo is switched off, and back on when the server stops echoing
(as some do after a password).

`RETURN` sends a bare CR in PETSCII mode (what Commodore BBSes expect) and the
Telnet end of line CR NUL in the ANSI modes (a bare CR in binary mode).

## Connection problems

A request the WiC64 doesn't answer in time is retried quietly up to three
times. After that, or on any other error, a box shows the WiC64's message
with `F1` Abort and `F3` Retry; Retry reconnects if the WiFi or network
connection was lost.

## If the client hangs

Press `RUN/STOP` + `RESTORE`. The client then shows a crash report on a red
border: where the processor was, its registers, the stack, the last bytes
the server sent, and the size of the WiC64 response it was receiving. Take
a photo of it and add it to an issue, with the version, the BBS, the
terminal mode and what you were doing.

Then press a key to go back to BASIC, where `RUN` starts the client again.
If the crash damaged too much for that, reset the C64. If nothing reacts to
`RUN/STOP` + `RESTORE` at all, the processor has stopped completely; please
mention that too. `RESTORE` on its own does nothing.

## Address book

Each server has a name, shown in the list and on the status line; a server
without a name shows its host instead. It can also have a login: a user name
and a password, which `F4` and `F6` send during the session, so that you
don't have to type them at every login. The password is never shown in the
list, but it is stored unencrypted in `telnet.cfg`: leave it empty if others
can read your disk. It comes with nine servers that were
online when this version was made:

| # | Name | Server | Mode |
|---|------|--------|------|
| 1 | 8-Bit Playground | `8bit.hoyvision.com:6502` | PETSCII |
| 2 | Particles! BBS | `particlesbbs.dyndns.org:6400` | PETSCII |
| 3 | Cottonwood BBS | `cottonwoodbbs.dyndns.org:6502` | PETSCII |
| 4 | Rapid Fire BBS | `rapidfire.hopto.org:64128` | PETSCII |
| 5 | Raveolution BBS | `raveolution.hopto.org:64128` | PETSCII |
| 6 | Level 29 | `bbs.fozztexx.com:23` | ANSI |
| 7 | RetroCampus BBS | `bbs.retrocampus.com:6510` | PETSCII |
| 8 | Vertrauen (home of Synchronet) | `vert.synchro.net:23` | ANSI |
| 9 | Telehack | `telehack.com:23` | UTF-8 80 |

Telehack writes 80-column text whatever window size it is told, so it is set
to UTF-8 80; in UTF-8 its longer lines wrap onto two rows.

The list is stored in `telnet.cfg` on the drive the program was loaded from
(device 8 if unknown). It is loaded at start-up and written when you press `S`:
first as `telnet.tmp`, which then replaces `telnet.cfg`, so a failed save
leaves the old list on the disk. A `telnet.cfg` saved by an older version
(without names or logins) is read as well; the next save writes the new
format, which older versions no longer read (they start with their own list
instead).

## Credits and licence

Based on the [WiC64 Simple Telnet Client](https://github.com/WiC64-Team/wic64-telnet)
by Henning Liebenau, and built on his
[WiC64 library](https://github.com/WiC64-Team/wic64-library) (`wic64.asm`,
`wic64.h`, included unchanged). The Punter download follows
[CCGMS Term](https://github.com/mist64/ccgmsterm) and its test version of
Per Olofsson's [CGTerm](https://github.com/MagerValp/CGTerm) Punter code. Both are under the BSD 2-Clause licence, and
so is this program: see [`LICENSE.txt`](LICENSE.txt), which also applies
to the `telnet.prg` download.

## Source layout

| File | Contents |
|------|----------|
| `main.asm` | entry point, includes |
| `wic64.asm`, `wic64.h` | WiC64 library by Henning Liebenau |
| `net.asm` | TCP connection through the WiC64 |
| `receive.asm` | hands what a read brought on to the Telnet layer, a byte at a time |
| `telnet.asm` | Telnet protocol and option negotiation |
| `term.asm` | terminal modes, keyboard, cursor |
| `ansi.asm` | ANSI/VT100 screen driver |
| `charmaps.asm` | ASCII character set, CP437/UTF-8/DEC tables |
| `session.asm` | connection loop, session keys, status line, retry |
| `scrollback.asm` | rows that left the screen, and the viewer for them |
| `screen80.asm` | 80 columns: font, bitmap drawing, the split with the text screen |
| `book.asm` | address book start screen, disk load/save, drive status, disk commands |
| `directory.asm` | the start screen's disk directory |
| `xfer.asm` | file downloads: XMODEM and Punter |
| `ui.asm` | printing, popup boxes, line input, clock |
| `crash.asm`, `crash_report.asm` | `RUN/STOP` + `RESTORE`: the crash report |
| `test/` | fake network, scripted scenarios, expected results |
| `tools/` | `run_test.py`: runs a test build in VICE for `make check` and `make bench`; `bench_data.py`: the benchmark's data; `test_bbs.py`, `telnet_proxy.py`, `byte_flood_server.py`: servers to test the client against (see [Testing](#testing)) |

Memory: the program runs in two parts around the ANSI character set at
`$3800`: `$0801`–`$37FF` and `$4000`–`$57FF` (both checked at build time).
The second part is stored right after the first in `telnet.prg` and moved up
at start-up. While the scrollback is shown the screen is kept at
`$5800`–`$5FFF`, which a file download uses for its blocks; the scrollback
itself is at `$6000`–`$9FFF`. What one read from the WiC64 brings (at most
8 KB) is received at `$A000`–`$BFFF`, in the RAM under the BASIC ROM, before
it is handled. Buffers (popup boxes, address book loading, the alternate
screen, the drive's status, a scrollback row) are at `$C000`–`$CBFF`, a
scrollback row's colours at `$02A7`. The cassette buffer at `$0334` holds,
one at a time, a file download's variables, the scrollback viewer's status
line and the host typed after `O`. 80 columns use
`$6000`–`$83FF` for their cells and font (the scrollback then starts at
`$8400`), the bitmap's colours at `$CC00` and the bitmap itself in the RAM
under the KERNAL ROM, at `$E000`. The crash report and the address book are
copied to the RAM under the I/O area at start-up: the report to `$D000`, the
address book to `$D400`, where it stays during a session, with the start
screen's directory code after it; the start screen works on a copy of both at
`$5800`.

## Testing

`make test` builds `build/test1.prg` … `build/test27.prg`. In these the WiC64
is replaced by a fake server that plays back a script, and keys come from a
script too (`test/scenarios.asm`): PETSCII with Telnet negotiation, ANSI BBS
output, UTF-8 host output, address book editing, line input, a network error,
saving and loading `telnet.cfg` (also ones saved by older versions), the
login keys, the disk directory and a disk command, switching to ANSI (or not, for BBSes that
only probe for it), a server that stops echoing, the scrollback
(with a 1 KB buffer, so that it fills up), 80 columns, and the finer points
of the ANSI and UTF-8 modes. Run one in VICE and look at the screen; what the
client sent is logged at `$9000` (so test builds must end below it).

`make check` runs them all in VICE (`x64sc` and `c1541` from the PATH or a
VICE in `/Applications`, or set `VICE=` and `C1541=`) and compares the
screen and what was sent with `test/expected/`. Each run also leaves a
screenshot in `build/`. After an intended change, look at the new results
and accept them with `make expected`.

`make bench` measures how fast the client shows what a server sends: how
many cycles it takes for each byte, from the read until the screen is up to
date (the WiC64 transfer itself not included). It plays back an animation
drawn from the top of the screen, like Telehack's `starwars`, in ANSI 80 and
UTF-8 80, and BBS text that scrolls, in ANSI 80 and ANSI 40
(`test/bench.asm`). The data goes through the same `receive.asm` loop as a
real connection.

To try the client against a server on your own computer (in VICE at
`127.0.0.1`, or from a real C64 on the same network at the address they
print; connect with `O` on the start screen):

- `tools/test_bbs.py` is a small BBS with a message editor that wraps
  words like C64 BBSes do, deleting the last word and typing it again on the
  next line. It needs no login and posts nothing. `--status` also updates a
  line of the screen while you type, as a BBS with more users does, and
  `--noise` adds more text to those updates.
- `tools/telnet_proxy.py host:port` passes a session on to a real BBS and
  records both directions, with the times. What you type is in the
  recording too, passwords included.
- `tools/byte_flood_server.py` sends a steady stream of bytes.

Each session of the first two is recorded as `session-<time>.log` and
`.server.bin`/`.client.bin`, so that what led to a problem can be looked at
and played back.

The test builds never touch `net.asm` or the WiC64, so after changing those,
try a real connection too: `x64sc -userportdevice 23 -autostart
build/telnet.prg` starts the client in VICE with its WiC64 emulation (user port
device "WiC64"), which uses the computer's network connection. On macOS this
needs VICE 3.10 or later: earlier versions crash on the first WiC64 request
(VICE bug #1978).

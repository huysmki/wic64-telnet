;---------------------------------------------------------
; Test scenarios: what the fake server sends and what the user types
;---------------------------------------------------------

IAC = $ff
ESC = $1b

!if SCENARIO = 1 {
; PETSCII BBS with Telnet negotiation, typing, line input
test_rx:
    !byte IAC, $fd, 24              ; DO TTYPE
    !byte IAC, $fa, 24, 1, IAC, $f0 ; SB TTYPE SEND SE
    !byte IAC, $fb, 1               ; WILL ECHO
    !byte IAC, $fb, 3               ; WILL SGA
    !byte IAC, $fd, 31              ; DO NAWS
    !byte IAC, $fd, 0               ; DO BINARY
    !byte IAC, $fd, 99              ; DO unknown option
    !byte IAC, $fd, 24              ; DO TTYPE again: no second answer
    !byte $93, $1e                  ; clear, green
    !pet "Welcome to the ", $05, "Test BBS", $1e, "!", 13
    !byte $12
    !pet "reverse", $92, " normal ", $22, "quoted", $22, $1c, " red", 13
    !byte $9e
    !pet "pi: ", IAC, IAC, 13       ; escaped $ff
    !byte $05
    !pet "Enter name: "
test_rx_end:

!align 255, 0
test_keys:
    !byte "1"                       ; connect to server 1 (PETSCII)
    !byte TK_WAIT_RX
    !text "A", "b"                  ; typed keys
    !text KEY_F3, TK_TYPE, 4, "H", "I", "!", KEY_RETURN
    !byte TK_IDLE, 5
    !byte TK_END
}

!if SCENARIO = 2 {
; PC BBS in ANSI mode: CP437 art, colours, cursor addressing, reports
test_rx:
    !text ESC, "[2J", ESC, "[1;33m"
    !byte $c9, $cd, $cd, $cd, $cd, $cd, $cd, $cd, $cd, $cd, $cd, $bb, 13, 10
    !text $ba, ESC, "[0;36m", " ANSI BBS ", ESC, "[1;33m", $ba, 13, 10
    !byte $c8, $cd, $cd, $cd, $cd, $cd, $cd, $cd, $cd, $cd, $cd, $bc, 13, 10
    !text ESC, "[0m", "Colours: "
    !text ESC, "[31mR", ESC, "[32mG", ESC, "[34mB", ESC, "[1;31mR", ESC, "[32mG"
    !text ESC, "[34mB", ESC, "[0m", 13, 10
    !text ESC, "[44;37m Blue bar ", ESC, "[K", ESC, "[0m", 13, 10
    !text ESC, "[7mReverse", ESC, "[0m normal", 13, 10
    !text "Blocks: ", $b0, $b1, $b2, $db, $dc, $df, $dd, $de, 13, 10
    !text "ASCII: {|}~ _^` ", $5c, " [] @", 13, 10
    !text ESC, "[10;20HAt row 10 col 20", ESC, "[6n"
    !text ESC, "[12;1H", "0123456789012345678901234567890123456789"
    !text "wrapped", 13, 10
    !text ESC, "[14;1HABCDEFGHIJ", ESC, "[14;3H", ESC, "[2P"
    !text ESC, "[15;1HABCDEFGHIJ", ESC, "[15;3H", ESC, "[2@"
    !text ESC, "[16;1HABCDEFGHIJ", ESC, "[16;5H", ESC, "[1K"
    !text ESC, "[18;1H", ESC, "[5n", ESC, "]0;title", 7, "OSC skipped"
    !text ESC, "[20;1H", "Tab:", 9, "x", 9, "y"
    !text ESC, "[22;1H", ESC, "(0", "lqqk x x mqqj", ESC, "(B", " DEC"
    !text ESC, "[23;1H", "Type: "
test_rx_end:

!align 255, 0
test_keys:
    !byte KEY_DOWN, "T"             ; server 2 -> ANSI
    !byte KEY_RETURN
    !byte TK_WAIT_RX
    !text "A", "b", KEY_UP, KEY_ARROW_LEFT, KEY_DEL, KEY_RETURN
    !byte TK_IDLE, 5
    !byte TK_END
}

!if SCENARIO = 3 {
; Unix host in UTF-8 mode: scroll region, insert/delete lines, UTF-8
test_rx:
    !text IAC, $fd, 24, IAC, $fa, 24, 1, IAC, $f0   ; TTYPE -> "ANSI"
    !byte IAC, $fd, 31                              ; NAWS -> 40 x 24
    !text ESC, "[H", ESC, "[2J"
    !text "Header line", 13, 10
    !text ESC, "[3;6r"                              ; scroll region 3-6
    !text ESC, "[3;1Hline 1", 13, 10, "line 2", 13, 10, "line 3", 13, 10
    !text "line 4", 13, 10, "line 5", 13, 10, "line 6"
    !text ESC, "[r"                                 ; reset region
    !text ESC, "[8;1H", $e2, $94, $8c, $e2, $94, $80, $e2, $94, $80
    !text $e2, $94, $90, " box ", $c3, $a9, "t", $c3, $a9, " ", $e2, $80, $9c
    !text "q", $e2, $80, $9d, " ", $e2, $82, $ac, " ", $f0, $9f, $98, $80
    !text 13, 10, $e2, $94, $82, "  ", $e2, $94, $82, " ", $e2, $96, $88
    !byte $e2, $96, $93, $e2, $96, $92, $e2, $96, $91
    !byte 13, 10, $e2, $94, $94, $e2, $94, $80, $e2, $94, $80, $e2, $94, $98
    !text ESC, "[12;1H", "row A", 13, 10, "row B", 13, 10, "row C"
    !text ESC, "[13;1H", ESC, "[L", "inserted"
    !text ESC, "[16;1H", "del 1", 13, 10, "del 2", 13, 10, "del 3"
    !text ESC, "[16;1H", ESC, "[M"
    !text ESC, "[20;1H", ESC, "[1;32muser@host", ESC, "[0m:", ESC, "[1;34m~", ESC, "[0m$ "
test_rx_end:

!align 255, 0
test_keys:
    !text KEY_DOWN, KEY_DOWN, "T", "T"  ; server 3 -> UTF-8
    !byte KEY_RETURN
    !byte TK_WAIT_RX
    !text "L", "S", KEY_RETURN
    !byte TK_IDLE, 5
    !byte KEY_F7                     ; session menu, shown at the end
    !byte TK_END
}

!if SCENARIO = 4 {
; Address book editing: new, type, edit, delete, then the result
test_rx:
    !byte 0
test_rx_end:

!align 255, 0
test_keys:
    !text "N", TK_TYPE, 7, "N", "E", "W", ":", "2", "3", KEY_RETURN
    !text "T", "T"                  ; new entry -> UTF-8
    !text KEY_HOME, "E", TK_TYPE, 3, "X", "Y", KEY_RETURN   ; edit first entry
    !text KEY_DOWN, "D", "Y"        ; delete the second
    !text KEY_DOWN, "D", "N"        ; keep the third
    !byte TK_END
}

!if SCENARIO = 5 {
; Line input box in ANSI mode, local echo, error box
test_rx:
    !text ESC, "[2J", "Line input test", 13, 10
test_rx_end:

!align 255, 0
test_keys:
    !byte "T", KEY_RETURN
    !byte TK_WAIT_RX
    !byte KEY_F5                    ; local echo on
    !text "a", "b"
    !text KEY_F3, TK_TYPE, 6, "H", "E", "L", "L", "O", KEY_RETURN
    !byte TK_IDLE, 5
    !byte KEY_F3                    ; leave the input box open
    !byte TK_END
}

!if SCENARIO = 6 {
; Network failure: the retry box, then a reconnect
test_rx:
    !text "Connected", 13
test_rx_end:

!align 255, 0
test_keys:
    !byte "1", TK_WAIT_RX
    !byte TK_FAIL, WIC64_CONNECTION_ERROR
    !byte TK_IDLE, 3
    !byte TK_END                    ; the retry box stays open
}

!if SCENARIO = 7 {
; Saving the address book to disk (drive 8 with a blank disk)
test_rx:
    !byte 0
test_rx_end:

!align 255, 0
test_keys:
    !byte "N", TK_TYPE, 8, "S", "A", "V", "E", "D", ":", "1", KEY_RETURN
    !byte "T"
    !byte "S"
    !byte TK_END
}

!if SCENARIO = 8 {
; Start-up with a saved address book on drive 8, then save it again
; (replacing the file)
test_rx:
    !byte 0
test_rx_end:

!align 255, 0
test_keys:
    !byte "S"
    !byte TK_END
}

!if SCENARIO = 9 {
; An ANSI host reached in PETSCII mode: switches to ANSI on ESC [
test_rx:
    !byte IAC, $fd, 31                              ; DO NAWS -> 40 x 25
    !text "plain text first", 13
    !text ESC, "(B"                                 ; ESC without [: no switch
    !text ESC, "[2J", ESC, "[H", "Switched to ANSI", 13, 10
    !text ESC, "[7m--More--(60%)", ESC, "[0m", 13, 10
    !text "@"
test_rx_end:

!align 255, 0
test_keys:
    !byte "1", TK_WAIT_RX
    !byte TK_IDLE, 80               ; let the status line catch up
    !byte TK_END
}

!if SCENARIO = 10 {
; A PETSCII BBS probing for ANSI (as rapidfire.hopto.org does):
; stays in PETSCII and does not answer the probe
test_rx:
    !byte $0d, $0a, $90, $40, $5c, $09, ESC, $5b, $21, ESC, $5b, $35, $6e
    !byte $0e, $9f, $0d, $0d, $00, $2d, $20, $c8, $9e, $45, $96, $41
    !pet "PETSCII still", 13
test_rx_end:

!align 255, 0
test_keys:
    !byte "1", TK_WAIT_RX
    !byte TK_IDLE, 5
    !byte TK_END
}

!if SCENARIO = 11 {
; ANSI mode: reverse video and backgrounds, iCE colours, 256 and true
; colours, too many parameters, strings, intermediate bytes, repeat
test_rx:
    !text ESC, "[2J"
    !text ESC, "[7m", "\\|~{}_^`", ESC, "[0m ", ESC, "[44m", "\\|~{}", ESC, "[0m", 13, 10
    !text ESC, "[44m", $db, $db, ESC, "[7m", $db, ESC, "[0m", " ", $db, " full blocks", 13, 10
    !text ESC, "[5;44m", " iCE ", ESC, "[0m ", ESC, "[5m", " blink ", ESC, "[0m", 13, 10
    !text ESC, "[38;5;196m", "red", ESC, "[38;5;21m", "blue", ESC, "[38;5;244m"
    !text "grey", ESC, "[48;5;46m", "green", ESC, "[0m", 13, 10
    !text ESC, "[38;2;255;255;0m", "yellow", ESC, "[38:2::0:255:255m", "cyan"
    !text ESC, "[38:2:255:0:255m", "magenta", ESC, "[38:5:9m", "red", ESC, "[0m", 13, 10
    !text ESC, "[1;2;3;4;5;6;7;8;1;31m", "nine", ESC, "[0m", 13, 10
    !text "DCS:", ESC, "P$qm", ESC, "\\", "gone", 13, 10
    !text "SR:ab", ESC, "[1 A", "cd", 13, 10
    !text "REP:x", ESC, "[4b", 13, 10
    !text ESC, "[3J", "ED 3 keeps the screen"
test_rx_end:

!align 255, 0
test_keys:
    !byte KEY_DOWN, "T"             ; server 2 -> ANSI
    !byte KEY_RETURN
    !byte TK_WAIT_RX
    !byte TK_IDLE, 5
    !byte TK_END
}

!if SCENARIO = 12 {
; UTF-8 mode: ED 2 keeps the cursor, UTF-8 in a title, the alternate
; screen, repeat, application cursor keys
test_rx:
    !text ESC, "[5;10H", ESC, "[2J", "stays at 5;10"
    !text ESC, "[1;1H", "Main screen", 13, 10
    !text ESC, "]0;Caf", $c3, $a9, " ", $e2, $98, $95, 7, "title skipped", 13, 10
    !text ESC, "[?1049h", "Alternate screen", ESC, "[?1049l", "back"
    !text ESC, "[7;1H", $e2, $94, $80, ESC, "[9b"
    !text ESC, "[?1h"
    !text ESC, "[9;1H", "$ "
test_rx_end:

!align 255, 0
test_keys:
    !text KEY_DOWN, KEY_DOWN, "T", "T"  ; server 3 -> UTF-8
    !byte KEY_RETURN
    !byte TK_WAIT_RX
    !byte KEY_UP, KEY_HOME
    !byte TK_IDLE, 5
    !byte TK_END
}

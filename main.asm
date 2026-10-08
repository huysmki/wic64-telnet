;---------------------------------------------------------
; WiC64 Telnet Client 3.2
;
; Build:       acme -f cbm -o telnet.prg main.asm
; Test build:  acme -f cbm -DTEST=1 -DSCENARIO=<n> -o test.prg main.asm
;              (fake network and scripted keys, see test/)
;
; Modules:
;   net.asm       TCP connection through the WiC64
;   telnet.asm    Telnet protocol and option negotiation
;   term.asm      terminal modes, keyboard, cursor
;   ansi.asm      ANSI/VT100 screen driver
;   charmaps.asm  ASCII character set and translation tables
;   screen80.asm  80 columns on a bitmap
;   session.asm   connection loop, session keys, status line
;   scrollback.asm rows that left the screen, and a viewer for them
;   book.asm      address book start screen, saved to disk
;   ui.asm        printing, popup boxes, line input, clock
;---------------------------------------------------------

!ifndef TEST {
    TEST = 0
}

!src "defs.asm"

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
    jmp start

wic64_include_enter_portal = 1
wic64_optimize_for_size = 1 ; one handshake routine instead of a copy in
                            ; every loop: some 350 bytes for 12 cycles a byte
!src "wic64.h"
!src "wic64.asm"

!src "ui.asm"
!if TEST {
    !src "test/fake_net.asm"
} else {
    !src "net.asm"
}
!src "telnet.asm"
!src "term.asm"
!src "ansi.asm"
!src "charmaps.asm"
!src "screen80.asm"
!src "session.asm"

start:
    jsr move_high_part
    jsr ui_screen_menu
    jsr net_init
    bcs .no_device
    bne .legacy_firmware
    jsr charset_init
    jsr book_init
main_menu:
    jsr book_menu
    bcs .portal
    jsr session_run
    jmp main_menu

.portal:
    jsr ui_screen_menu
    +wic64_enter_portal
    jmp main_menu           ; only reached if loading the portal failed

.no_device:
    +print .no_device_text
    rts

.legacy_firmware:
    +print .legacy_firmware_text
    rts

.no_device_text:
    !pet "?WiC64 not present or unresponsive", 13, 0
.legacy_firmware_text:
    !pet "?Legacy firmware detected", 13, 13
    !pet "Firmware 2.0.0 or later required", 13, 0

; The VIC needs the character set below $4000, so the program is in
; two parts around it: the first runs where it is loaded, the second
; is stored right after it and moved to HIGH_PART at start-up.
; Whole pages are moved, last page first, as the two places overlap.
; Only once: the move and the character set overwrite where the high
; part was loaded, and the program can be started again with RUN.
HIGH_PART = CHARSET + $0800

move_high_part:
    lda .high_part_moved
    bne .moved
    inc .high_part_moved
    lda #<(high_part_load + (HIGH_PAGES - 1) * $100)
    sta zp_a
    lda #>(high_part_load + (HIGH_PAGES - 1) * $100)
    sta zp_a+1
    lda #<(HIGH_PART + (HIGH_PAGES - 1) * $100)
    sta zp_b
    lda #>(HIGH_PART + (HIGH_PAGES - 1) * $100)
    sta zp_b+1
    ldx #HIGH_PAGES
    ldy #0
-   lda (zp_a),y
    sta (zp_b),y
    iny
    bne -
    dec zp_a+1
    dec zp_b+1
    dex
    bne -
.moved:
    rts

.high_part_moved: !byte 0

low_end:
!if low_end > CHARSET {
    !error "Program overlaps the character set at CHARSET"
}

high_part_load:
!pseudopc HIGH_PART {
!src "scrollback.asm"
!src "book.asm"
!src "xfer.asm"
}
high_part_end:
HIGH_PAGES = (high_part_end - high_part_load + $ff) >> 8

!if HIGH_PART - high_part_load < $100 {
    !error "Moving the high part a page at a time would overwrite it"
}
!if HIGH_PART + HIGH_PAGES * $100 > PROGRAM_LIMIT {
    !error "Program overlaps the memory at PROGRAM_LIMIT"
}

!if TEST {
* = TEST_DATA
!src "test/scenarios.asm"
    !if * > NET_RX_BUFFER {
        !error "The test data runs into NET_RX_BUFFER"
    }
}

;---------------------------------------------------------
; WiC64 Telnet Client 3.0
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
;   session.asm   connection loop, session keys, status line
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
!src "session.asm"
!src "book.asm"

start:
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

program_end:
!if program_end > CHARSET {
    !error "Program overlaps the character set at CHARSET"
}

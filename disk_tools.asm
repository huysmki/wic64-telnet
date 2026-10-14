;---------------------------------------------------------
; The start screen's disk tools: the directory ($) and the drive (#)
;
; directory_show lists the directory of disk_device as BASIC's LOAD"$"
; and LIST would: the blocks, then the name and type. Any key pauses the
; listing until the next key; RUN/STOP ends it.
;
; disk_device is the drive the program was loaded from (the KERNAL's
; last device), or drive 8 if that is none, or if telnet.cfg isn't on
; it: started from the WiC64 portal, a cartridge or a launcher, the last
; device need not be a drive at all. # steps through drives 8 to 11, and
; the start screen's title shows the one in use.
;
; This code only runs on the start screen. It is kept in the RAM under
; the I/O area after the address book and copied to BOOK_OVERLAY with
; it (book.asm's .fetch), as the program has no room left for it.
;---------------------------------------------------------

!zone drive {
.LAST_DRIVE = 11

; Chooses disk_device and loads the address book from it.
drive_init:
    lda LAST_DEVICE
    cmp #8
    bcc .eight
    cmp #31
    bcc +
.eight:
    lda #8
+   sta disk_device
    jsr book_load
    bcc .found
    lda #8                  ; not there: drive 8, the usual one
    cmp disk_device
    beq .found
    sta disk_device
    jmp book_load
.found:
    rts

; #: the next drive
drive_key:
    ldx disk_device
    inx
    cpx #.LAST_DRIVE + 1
    bcc +
    ldx #8
+   stx disk_device
    lda #<.no_message
    ldy #>.no_message
    jmp book_show_message

; Puts disk_device, in decimal, into the start screen's title.
drive_show:
    lda disk_device
    ldx #$30 - 1             ; "0" - 1
    sec
-   inx                     ; X = the tens, as a digit
    sbc #10
    bcs -
    adc #$30 + 10            ; "0" + 10: A = the units, as a digit
    cpx #"0"
    bne +
    tax                     ; one digit: then a space
    lda #" "
+   stx book_title_drive
    sta book_title_drive + 1
    rts

.no_message: !byte 0
}

!zone directory {
.FILE = 2
.KEYS_WAITING = $c6

directory_show:
    jsr ui_screen_menu
    lda #1
    ldx #<.dollar
    ldy #>.dollar
    jsr SETNAM
    lda #.FILE
    ldx disk_device
    ldy #0                  ; as a program: links and line numbers
    jsr SETLFS
    jsr OPEN
    bcs .done
    ldx #.FILE
    jsr CHKIN
    bcs .done
    jsr CHRIN               ; the load address
    jsr CHRIN

.line:
    jsr CHRIN               ; the link: 0 at the end
    sta .link
    jsr CHRIN
    ora .link
    beq .done
    jsr READST
    bne .done               ; no disk, or a drive error
    jsr CHRIN               ; the line number: the blocks
    sta print_number_value
    jsr CHRIN
    sta print_number_value+1
    lda #0
    sta print_number_value+2
    ldx #5
    jsr print_number
    lda #" "
    jsr CHROUT
-   jsr CHRIN
    beq +
    jsr CHROUT
    jsr READST
    beq -
+   lda #$0d
    jsr CHROUT
    jsr STOP
    beq .done
    lda .KEYS_WAITING       ; a key: pause until the next one
    beq .line
    jsr .key_from_keyboard
    ldx #.FILE
    jsr CHKIN
    jmp .line

.done:
    jsr CLRCHN
    lda #.FILE
    jsr CLOSE
    +print .press_key
.key_from_keyboard:
    jsr CLRCHN              ; GETIN reads the keyboard again
    lda #0
    sta .KEYS_WAITING
    jmp wait_key

.dollar:    !pet "$"
.press_key: !pet 13, PET_GREEN, "Press a key.", 0
.link:      !byte 0
}
directory_end:

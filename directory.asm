;---------------------------------------------------------
; Directory: the start screen's $ key
;
; Lists the directory of disk_device as BASIC's LOAD"$" and LIST
; would: the blocks, then the name and type. Any key pauses the
; listing until the next key; RUN/STOP ends it.
;
; This code only runs on the start screen. It is kept in the RAM under
; the I/O area after the address book and copied to BOOK_OVERLAY with
; it (book.asm's .fetch), as the program has no room left for it.
;---------------------------------------------------------

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

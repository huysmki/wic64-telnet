;---------------------------------------------------------
; UI helpers: printing, popup boxes, line input, the
; online clock and border flashes
;---------------------------------------------------------

!macro print .addr {
    lda #<.addr
    ldy #>.addr
    jsr print_str
}

!macro plot .col, .row {
    ldx #.row
    ldy #.col
    clc
    jsr PLOT
}

screen_row_lo: !for .r, 0, 24 { !byte <(SCREEN + .r * 40) }
screen_row_hi: !for .r, 0, 24 { !byte >(SCREEN + .r * 40) }

; In test builds keys come from a script instead of the keyboard
!if TEST {
    get_key = test_get_key
} else {
    get_key = GETIN
}

wait_key:
    jsr get_key
    beq wait_key
    rts

;---------------------------------------------------------
; Printing
;---------------------------------------------------------

!zone print_str {
; Prints the 0-terminated PETSCII string at A/Y. Preserves X.
print_str:
    sta .char+1
    sty .char+2
.char:
    lda $ffff
    beq .done
    jsr CHROUT
    inc .char+1
    bne .char
    inc .char+2
    bne .char
.done:
    rts
}

!zone print_field {
; Prints the string at A/Y cut or padded with spaces to exactly X characters.
print_field:
    sta .char+1
    sty .char+2
    stx .left
.next:
    lda .left
    beq .done
.char:
    lda $ffff
    beq .pad
    jsr CHROUT
    dec .left
    inc .char+1
    bne .next
    inc .char+2
    bne .next
.pad:
    lda #" "
    jsr CHROUT
    dec .left
    bne .pad
.done:
    rts

.left: !byte 0
}

!zone print_dec {
; Prints A (0-99) in decimal without leading zero.
print_dec:
    ldx #0
-   cmp #10
    bcc +
    sbc #10
    inx
    bne -
+   pha
    txa
    beq +
    ora #"0"
    jsr CHROUT
+   pla
    ora #"0"
    jmp CHROUT
}

; Resets the screen to the plain menu look: ROM character set, locked
; case, no reverse or quote mode, cleared.
ui_screen_menu:
    lda #COLOR_BLACK
    sta BORDER
    sta BACKGROUND
    lda #VIC_ROM_CHARSET
    sta VIC_MEMORY
    lda #COLOR_GREEN
    sta CURSOR_COLOR
    lda #0
    sta REVERSE_FLAG
    sta QUOTE_MODE
    sta INSERT_COUNT
    lda #PET_LOCK_CASE
    jsr CHROUT
    lda #PET_CLR
    jmp CHROUT

;---------------------------------------------------------
; Popup boxes
;
; A box covers the screen from its first row down to the bottom row
; and puts back whatever was underneath when it is closed, including
; the cursor, colours and the screen editor's line links. In 80
; columns the text screen is shown from the box's first row down
; while it is open. Inside the
; box every row is a separate screen line, so the KERNAL editor and
; ui_input behave predictably whatever the session printed before.
; Only one box can be open at a time.
;---------------------------------------------------------

!zone box {
BOX_BORDER_TOP    = $63
BOX_BORDER_BOTTOM = $64

; A = colour, X = first row (17-21)
box_open:
    sta .color
    stx .first_row
    jsr term_cursor_hide
    jsr s80_flush           ; 80 columns: the screen above as it is now

    sec
    jsr PLOT
    stx .cursor_row
    sty .cursor_col
    lda CURSOR_COLOR
    sta .saved_color
    lda REVERSE_FLAG
    sta .saved_reverse
    lda #0
    sta REVERSE_FLAG
    sta QUOTE_MODE
    sta INSERT_COUNT
    lda .color
    sta CURSOR_COLOR

    ldx #24
-   lda LINE_LINKS,x
    sta box_save_links,x
    dex
    bpl -

    ldx .first_row
.save_row:
    jsr .point_at_row
    lda screen_row_hi,x
    ora #$80
    sta LINE_LINKS,x
    ldy #39
-   lda (zp_a),y
.save_screen:
    sta $ffff,y
    lda (zp_b),y
.save_color:
    sta $ffff,y
    lda #" "
    sta (zp_a),y
    lda .color
    sta (zp_b),y
    dey
    bpl -
    inx
    cpx #25
    bcc .save_row

    ldx .first_row
    lda #BOX_BORDER_TOP
    jsr .fill_row
    ldx #24
    lda #BOX_BORDER_BOTTOM
    jsr .fill_row
    lda .first_row
    jmp s80_text_from

box_close:
    ldx .first_row
.restore_row:
    jsr .point_at_row
    lda .save_screen+1
    sta .load_screen+1
    lda .save_screen+2
    sta .load_screen+2
    lda .save_color+1
    sta .load_color+1
    lda .save_color+2
    sta .load_color+2
    ldy #39
.load_screen:
-   lda $ffff,y
    sta (zp_a),y
.load_color:
    lda $ffff,y
    sta (zp_b),y
    dey
    bpl -
    inx
    cpx #25
    bcc .restore_row

    ldx #24
-   lda box_save_links,x
    sta LINE_LINKS,x
    dex
    bpl -

    lda #24
    jsr s80_text_from
    lda .saved_reverse
    sta REVERSE_FLAG
    lda .saved_color
    sta CURSOR_COLOR
    ldx .cursor_row
    ldy .cursor_col
    clc
    jmp PLOT

; Points zp_a/zp_b at screen/colour row X and the save_* operands at
; that row's slot in box_save_buffer. Preserves X.
.point_at_row:
    lda screen_row_lo,x
    sta zp_a
    sta zp_b
    lda screen_row_hi,x
    sta zp_a+1
    clc
    adc #COLOR_OFFSET_HI
    sta zp_b+1

    txa
    sec
    sbc .first_row
    tay
    lda .slot_lo,y
    sta .save_screen+1
    lda .slot_hi,y
    sta .save_screen+2
    lda .slot_lo,y
    clc
    adc #40
    sta .save_color+1
    lda .slot_hi,y
    adc #0
    sta .save_color+2
    rts

; X = row, A = screen code
.fill_row:
    pha
    jsr .point_at_row
    pla
    ldy #39
-   sta (zp_a),y
    dey
    bpl -
    rts

.slot_lo: !for .i, 0, 7 { !byte <(box_save_buffer + .i * 80) }
.slot_hi: !for .i, 0, 7 { !byte >(box_save_buffer + .i * 80) }

.color:         !byte 0
.first_row:     !byte 0
.cursor_row:    !byte 0
.cursor_col:    !byte 0
.saved_color:   !byte 0
.saved_reverse: !byte 0
}

;---------------------------------------------------------
; Line input
;---------------------------------------------------------

!zone ui_input {
; Lets the user edit a line with the screen editor, starting at the
; cursor. The line may run on into the next row (80 characters).
; A/Y = default text to pre-fill, or A = Y = 0 for none.
; Returns the text 0-terminated in INPUT_BUFFER and its length in A;
; A = 0 if the line is empty or blank.
ui_input:
    sta .default+1
    sty .default+2

    sec
    jsr PLOT
    inx
    cpx #25
    bcs +
    lda screen_row_hi,x
    sta LINE_LINKS,x        ; the next row continues this one
+
    lda .default+2
    beq .read

    ldx #0
.default:
    lda $ffff,x
    beq +
    jsr CHROUT
    inx
    bne .default
+   lda #0
    sta QUOTE_MODE
    txa
    beq .read
-   lda #PET_CRSR_LEFT      ; input starts where the cursor is
    jsr CHROUT
    dex
    bne -

.read:
!if TEST {
    jsr test_before_input
}
    jsr BASIC_INLIN

    ldx #0
    ldy #0                  ; count of non-blank characters
-   lda INPUT_BUFFER,x
    beq +
    cmp #" "
    beq ++
    iny
++  inx
    bne -
+   txa
    cpy #0
    bne +
    lda #0
+   rts
}

;---------------------------------------------------------
; Online clock, counting from clock_reset
;---------------------------------------------------------

!zone clock {
clock_reset:
    sei
    lda JIFFY_LO
    sta .last
    lda JIFFY_MID
    sta .last+1
    cli
    lda #0
    sta .hours
    sta .minutes
    sta .seconds
    rts

; Advances the clock by at most one second; C=1 if it changed.
clock_tick:
    sei
    lda JIFFY_LO
    ldx JIFFY_MID
    cli
    sec
    sbc .last
    tay
    txa
    sbc .last+1
    bne .next_second        ; 256 or more jiffies behind
    cpy #60
    bcs .next_second
    clc
    rts

.next_second:
    lda .last
    clc
    adc #60
    sta .last
    bcc +
    inc .last+1
+   sed
    lda .seconds
    clc
    adc #1
    sta .seconds
    cmp #$60
    bcc .changed
    lda #0
    sta .seconds
    lda .minutes
    clc
    adc #1
    sta .minutes
    cmp #$60
    bcc .changed
    lda #0
    sta .minutes
    lda .hours
    clc
    adc #1
    sta .hours
.changed:
    cld
    sec
    rts

; Writes "hh:mm:ss" (PETSCII digits) to clock_text.
clock_format:
    ldx #0
    lda .hours
    jsr .digits
    lda .minutes
    jsr .digits
    lda .seconds
.digits:
    pha
    lsr
    lsr
    lsr
    lsr
    ora #"0"
    sta clock_text,x
    pla
    and #$0f
    ora #"0"
    sta clock_text+1,x
    inx
    inx
    inx
    rts

clock_text: !pet "00:00:00", 0

.last:    !word 0
.hours:   !byte 0
.minutes: !byte 0
.seconds: !byte 0
}

;---------------------------------------------------------
; Border flashes (bell, feedback); the bell also beeps on the SID
;---------------------------------------------------------

!zone flash {
FLASH_JIFFIES = 10
BELL_FREQUENCY = 29970      ; 1760 Hz on a PAL C64 (n * 0.0587 Hz)

; A square-wave ping that decays to silence by itself (sustain 0); the
; release when the flash ends carries on at the same rate.
ui_bell:
    lda #<BELL_FREQUENCY
    sta SID_FREQ_LO
    lda #>BELL_FREQUENCY
    sta SID_FREQ_HI
    lda #$00                ; 50 % pulse width
    sta SID_PULSE_LO
    lda #$08
    sta SID_PULSE_HI
    lda #$09                ; attack 2 ms, decay 750 ms
    sta SID_ATTACK_DECAY
    lda #$09                ; sustain 0, release 750 ms
    sta SID_SUSTAIN_RELEASE
    lda #$0f
    sta SID_VOLUME
    lda #SID_PULSE          ; a bell still ringing starts again
    sta SID_CONTROL
    lda #SID_PULSE | SID_GATE
    sta SID_CONTROL
    lda #COLOR_WHITE

; A = border colour to show briefly
ui_flash:
    sta BORDER
    lda JIFFY_LO
    clc
    adc #FLASH_JIFFIES
    sta .until
    lda #1
    sta .active
    rts

; Call regularly; ends a flash once its time is up.
ui_tick:
    lda .active
    beq +
    lda JIFFY_LO
    sec
    sbc .until
    bmi +
    lda #COLOR_BLACK
    sta BORDER
    sta .active
    lda #SID_PULSE          ; releases the bell, if it rang
    sta SID_CONTROL
+   rts

.active: !byte 0
.until:  !byte 0
}

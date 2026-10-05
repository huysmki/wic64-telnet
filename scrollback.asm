;---------------------------------------------------------
; Scrollback: rows that left the screen, and a viewer for them
;
; The terminal hands over each row just before it scrolls off the
; top, and the whole screen just before it is cleared. They are kept
; in a ring buffer that drops the oldest rows when it is full. The
; viewer shows them above the current screen and lets the user page
; through them.
;
; Rows are kept as screen codes and colours, which only mean the same
; in the character set and width they were drawn with, so the
; terminal empties the scrollback whenever the mode changes. The ring
; is smaller in 80 columns, which need some of its memory.
;
; A row is stored without its trailing blanks, as one record:
;   length, characters, colours (two per byte, low nibble first), length
; The length at both ends lets the ring be walked in either direction.
;---------------------------------------------------------

!zone scrollback {
.VIEW_ROWS = 24
.STATUS_ROW = 24
.STATUS_COLOR = COLOR_GREY

!if <SCROLLBACK_40 | <SCROLLBACK_40_END | <SCROLLBACK_80 | <SCROLLBACK_80_END {
    !error "The scrollback ring must start and end on a page"
}

; Empties the scrollback, sized for term_columns.
scrollback_clear:
    lda term_columns
    cmp #80
    beq +
    lda #>SCROLLBACK_40
    ldx #>SCROLLBACK_40_END
    bne ++
+   lda #>SCROLLBACK_80
    ldx #>SCROLLBACK_80_END
++  sta .ring_start
    stx .ring_end
    txa
    sec
    sbc .ring_start
    sta .ring_pages
    lda .ring_start
    sta .head+1
    sta .tail+1
    lda #0
    sta .head
    sta .tail
    sta .used
    sta .used+1
    sta .lines
    sta .lines+1
    rts

; Keeps the whole screen (above the status line) before it is
; cleared, without the blank rows at its bottom.
scrollback_add_screen:
    ldx term_rows
-   dex
    bmi .screen_done
    jsr .row_length
    beq -
    stx .last_row
    ldx #0
-   stx .row
    jsr scrollback_add_row
    ldx .row
    cpx .last_row
    inx
    bcc -
.screen_done:
    rts

; X = screen row to keep.
scrollback_add_row:
    jsr .row_length
    sta .length
    jsr .record_size
    sta .size
    jsr .make_room

    lda .head
    sta .write+1
    lda .head+1
    sta .write+2
    lda .length
    jsr .write
    ldy #0
-   cpy .length
    beq +
    lda (zp_a),y
    jsr .write
    iny
    bne -
+   ldy #0
-   cpy .length
    bcs +
    lda (zp_b),y
    and #$0f
    sta .packed
    iny
    lda (zp_b),y            ; past the end for an odd length: unused
    asl
    asl
    asl
    asl
    ora .packed
    jsr .write
    iny
    bne -
+   lda .length
    jsr .write
    lda .write+1
    sta .head
    lda .write+2
    sta .head+1

    lda .used
    clc
    adc .size
    sta .used
    bcc +
    inc .used+1
+   inc .lines
    bne +
    inc .lines+1
+   rts

; X = row. Points zp_a/zp_b at it and returns A = Z = its length
; without trailing blanks. Preserves X.
.row_length:
    jsr term_row_cells
    ldy term_columns
-   dey
    bmi +
    lda (zp_a),y
    cmp #" "
    beq -
+   iny
    tya
    rts

; A = row length. Returns A = size of its record.
.record_size:
    sta .tmp
    clc
    adc #1
    lsr
    clc
    adc .tmp
    adc #2
    rts

; Drops the oldest rows until .size bytes are free.
.make_room:
    lda #0
    sec
    sbc .used
    tax
    lda .ring_pages
    sbc .used+1
    bne .room
    cpx .size
    bcs .room
    lda .tail
    sta .read+1
    lda .tail+1
    sta .read+2
    jsr .read_byte
    jsr .record_size
    sta .dropped
    clc
    adc .tail
    sta .tail
    lda .tail+1
    adc #0
    jsr .wrap_up
    sta .tail+1
    lda .used
    sec
    sbc .dropped
    sta .used
    bcs +
    dec .used+1
+   lda .lines
    bne +
    dec .lines+1
+   dec .lines
    jmp .make_room
.room:
    rts

; Stores A at the write position and advances it. Preserves X and Y.
.write:
    sta $ffff
    inc .write+1
    bne +
    lda .write+2
    clc
    adc #1
    jsr .wrap_up
    sta .write+2
+   rts

; Returns A = the byte at the read position and advances it.
; Preserves X and Y.
.read_byte:
.read:
    lda $ffff
    pha
    inc .read+1
    bne +
    lda .read+2
    clc
    adc #1
    jsr .wrap_up
    sta .read+2
+   pla
    rts

; A = high byte of an address up to one ring past the ring; returns
; it moved back into the ring.
.wrap_up:
    cmp .ring_end
    bcc +
    sbc .ring_pages
+   rts

; The same for an address up to one ring before the ring.
.wrap_down:
    cmp .ring_start
    bcs +
    adc .ring_pages
+   rts

;---------------------------------------------------------
; Viewer
;
; Shows the kept rows followed by the current screen, 24 rows at a
; time, with a status line below. .top is the first row shown,
; counting from the oldest kept row. Nothing is read from the
; network meanwhile; the screen is put back on the way out. In 80
; columns the rows are drawn on the bitmap, and the current screen
; comes from its cells.
;---------------------------------------------------------

scrollback_view:
    jsr term_cursor_hide
    ldx #0
-   !for .page, 0, 3 {
        lda SCREEN + .page * $100,x
        sta scrollback_screen + .page * $100,x
        lda COLOR_RAM + .page * $100,x
        sta scrollback_colors + .page * $100,x
    }
    inx
    bne -

    lda .lines
    clc
    adc term_rows
    sta .total
    lda .lines+1
    adc #0
    sta .total+1
    lda .total
    sec
    sbc #.VIEW_ROWS
    sta .max_top
    lda .total+1
    sbc #0
    sta .max_top+1
    sta .top+1
    lda .max_top
    sta .top
    lda #.VIEW_ROWS         ; start a page back
    jsr .move_up

.view:
    jsr .draw
    jsr wait_key
    cmp #KEY_UP
    bne +
    lda #1
    jsr .move_up
    jmp .view
+   cmp #KEY_DOWN
    bne +
    lda #1
    jsr .move_down
    jmp .view
+   cmp #KEY_F1
    bne +
    lda #.VIEW_ROWS
    jsr .move_up
    jmp .view
+   cmp #KEY_F3
    bne +
    lda #.VIEW_ROWS
    jsr .move_down
    jmp .view
+   cmp #KEY_HOME
    bne +
    lda #0
    sta .top
    sta .top+1
    jmp .view
+   cmp #KEY_CLR
    bne +
    lda .max_top
    sta .top
    lda .max_top+1
    sta .top+1
    jmp .view

+   ldx #0
-   !for .page, 0, 3 {
        lda scrollback_screen + .page * $100,x
        sta SCREEN + .page * $100,x
        lda scrollback_colors + .page * $100,x
        sta COLOR_RAM + .page * $100,x
    }
    inx
    bne -
    lda term_columns
    cmp #80
    bne +
    jsr s80_touch_all
    jmp s80_flush
+   rts

; A = rows; .top - A, but not below 0.
.move_up:
    sta .tmp
    lda .top
    sec
    sbc .tmp
    sta .top
    lda .top+1
    sbc #0
    sta .top+1
    bcs +
    lda #0
    sta .top
    sta .top+1
+   rts

; A = rows; .top + A, but not beyond .max_top.
.move_down:
    clc
    adc .top
    sta .top
    bcc +
    inc .top+1
+   lda .max_top
    cmp .top
    lda .max_top+1
    sbc .top+1
    bcs +
    lda .max_top
    sta .top
    lda .max_top+1
    sta .top+1
+   rts

.draw:
    lda .top                ; a kept row at the top: find its record
    cmp .lines
    lda .top+1
    sbc .lines+1
    bcs .rows
    lda .lines
    sec
    sbc .top
    sta .count
    lda .lines+1
    sbc .top+1
    sta .count+1
    lda .head
    sta .record
    lda .head+1
    sta .record+1
-   jsr .previous_record
    lda .count
    bne +
    dec .count+1
+   dec .count
    lda .count
    ora .count+1
    bne -
    lda .record
    sta .read+1
    lda .record+1
    sta .read+2

.rows:
    lda .top
    sta .shown
    lda .top+1
    sta .shown+1
    ldx #0
.draw_row:
    stx .row
    lda .shown
    cmp .lines
    lda .shown+1
    sbc .lines+1
    bcs +
    jsr .read_record        ; leaves .read on the next record
    jmp ++
+   lda .shown
    sec
    sbc .lines
    tax
    jsr .screen_row
++  ldx .row
    jsr .show_row
    inc .shown
    bne +
    inc .shown+1
+   ldx .row
    inx
    cpx #.VIEW_ROWS
    bcc .draw_row
    jmp .draw_status

; .record = start of a record, or .head; moves it to the one before.
.previous_record:
    lda .record
    sec
    sbc #1
    sta .read+1
    lda .record+1
    sbc #0
    jsr .wrap_down
    sta .read+2
    jsr .read_byte
    jsr .record_size
    sta .tmp
    lda .record
    sec
    sbc .tmp
    sta .record
    lda .record+1
    sbc #0
    jsr .wrap_down
    sta .record+1
    rts

; Reads the record at the read position into .row_chars and
; .row_colors, padded with blanks, and points zp_a/zp_b at them.
.read_record:
    lda #<.row_chars
    sta zp_a
    lda #>.row_chars
    sta zp_a+1
    lda #<.row_colors
    sta zp_b
    lda #>.row_colors
    sta zp_b+1
    jsr .read_byte
    sta .length
    ldy #0
-   cpy .length
    beq +
    jsr .read_byte
    sta (zp_a),y
    iny
    bne -
+   ldy #0
-   cpy .length
    bcs +
    jsr .read_byte
    sta .packed
    and #$0f
    sta (zp_b),y
    iny
    lda .packed
    lsr
    lsr
    lsr
    lsr
    sta (zp_b),y            ; past the end for an odd length: blank
    iny
    bne -
+   jsr .read_byte          ; the length again
    ldy .length
-   cpy term_columns
    bcs +
    lda #" "
    sta (zp_a),y
    lda #COLOR_LIGHT_GREY
    sta (zp_b),y
    iny
    bne -
+   rts

; X = row of the current screen; points zp_a/zp_b at its cells: in
; the saved copy of the screen, or in 80 columns the terminal's.
.screen_row:
    lda term_columns
    cmp #80
    bne +
    jmp term_row_cells
+   lda screen_row_lo,x
    sta zp_a
    sta zp_b
    lda screen_row_hi,x
    clc
    adc #>(scrollback_screen - SCREEN)
    sta zp_a+1
    adc #>(scrollback_colors - scrollback_screen)
    sta zp_b+1
    rts

; X = row of the view, zp_a/zp_b = the cells to show there.
.show_row:
    lda term_columns
    cmp #80
    bne +
    lda #0
    ldy #80
    jmp s80_draw
+   lda screen_row_lo,x
    sta .to_char+1
    sta .to_color+1
    lda screen_row_hi,x
    sta .to_char+2
    clc
    adc #COLOR_OFFSET_HI
    sta .to_color+2
    ldy #39
-   lda (zp_a),y
.to_char:
    sta $ffff,y
    lda (zp_b),y
.to_color:
    sta $ffff,y
    dey
    bpl -
    rts

; " scrollback 120/345        crsr f1 f3 home"
.draw_status:
    ldx #39
    lda #" "
-   sta .status,x
    dex
    bpl -
    ldx #.TITLE_LENGTH-1
-   lda .title,x
    sta .status,x
    dex
    bpl -
    lda .top
    clc
    adc #1
    sta .number
    lda .top+1
    adc #0
    sta .number+1
    ldx #.TITLE_LENGTH
    jsr .append_number
    lda #"/"
    sta .status,x
    inx
    lda .total
    sta .number
    lda .total+1
    sta .number+1
    jsr .append_number
    ldx #.KEYS_LENGTH-1
-   lda .keys,x
    sta .status + 40 - .KEYS_LENGTH,x
    dex
    bpl -

    ldx #39
-   lda .status,x
    ora #$80
    sta SCREEN + .STATUS_ROW * 40,x
    lda #.STATUS_COLOR
    sta COLOR_RAM + .STATUS_ROW * 40,x
    dex
    bpl -
    rts

; Writes .number in decimal to .status from X on; X ends after it.
.append_number:
    ldy #4
    lda #0
    sta .started
.power:
    lda #0
    sta .digit
-   lda .number
    sec
    sbc .powers_lo,y
    pha
    lda .number+1
    sbc .powers_hi,y
    bcc +
    sta .number+1
    pla
    sta .number
    inc .digit
    bne -
+   pla
    lda .digit
    ora .started
    bne +
    cpy #0                  ; no leading zeros, but 0 itself
    bne ++
+   lda #1
    sta .started
    lda .digit
    ora #"0"
    sta .status,x
    inx
++  dey
    bpl .power
    rts

.powers_lo: !byte <1, <10, <100, <1000, <10000
.powers_hi: !byte >1, >10, >100, >1000, >10000

.title: !scr " scrollback "
.TITLE_LENGTH = * - .title
.keys:  !scr "crsr f1 f3 home "
.KEYS_LENGTH = * - .keys

.ring_start: !byte >SCROLLBACK_40 ; pages
.ring_end:   !byte >SCROLLBACK_40_END
.ring_pages: !byte >(SCROLLBACK_40_END - SCROLLBACK_40)
.head:     !word SCROLLBACK_40 ; where the next record goes
.tail:     !word SCROLLBACK_40 ; the oldest record
.used:     !word 0
.lines:    !word 0
.total:    !word 0           ; kept rows plus the rows of the screen
.max_top:  !word 0
.top:      !word 0
.shown:    !word 0
.count:    !word 0
.record:   !word 0
.number:   !word 0
.length:   !byte 0
.size:     !byte 0
.dropped:  !byte 0
.packed:   !byte 0
.tmp:      !byte 0
.row:      !byte 0
.last_row: !byte 0
.digit:    !byte 0
.started:  !byte 0
.status:   !fill 40, 0
.row_chars:  !fill 80, 0
.row_colors: !fill 80, 0
}

;---------------------------------------------------------
; 80 columns: characters 4 pixels wide on a hires bitmap
;
; Draws rows of cells (screen codes for CHARSET, bit 7 for reverse
; video, and colours) into a bitmap of 40 x 24 blocks of 8 x 8 pixels,
; two characters to a block. A block has a single colour for its
; pixels, so its two characters share one: the left one's, unless that
; is a blank. The background is black.
;
; Below the bitmap the normal text screen shows, from the status line
; or, while a popup box is open, from the box's first row: a raster
; interrupt switches the VIC to the bitmap in the top border and back
; to text mode just before that row.
;
; The glyphs are made from CHARSET when 80 columns start: each pair of
; pixels becomes one. The few characters that do not suit are drawn
; by hand (.own_glyphs).
;
; The terminal changes its cells and says which (s80_touch,
; s80_scroll_up, s80_scroll_down); s80_flush then draws all of it at
; once, typically after everything one network read brought. Drawing
; is slow on a C64, and this way rows that scroll up in one go cost a
; single move of the bitmap, and a row is drawn once, not once for
; each character.
;
; The bitmap is in the RAM under the KERNAL ROM. Writing to it needs
; nothing special; reading it (to move rows) switches the ROM off,
; with interrupt vectors in the RAM below it for meanwhile.
;---------------------------------------------------------

!zone screen80 {
.TOP_LINE   = 20            ; raster line in the top border
.FIRST_LINE = 51            ; raster line of text row 0
.BMM = $20                  ; $d011: bitmap mode
.BITMAP_D018 = (((MATRIX80 & $3fff) / $0400) << 4) | (((BITMAP80 & $3fff) / $2000) << 3)
.KERNAL_IRQ = $ea31
.KERNAL_IRQ_RETURN = $ea81  ; restores Y, X and A, then RTI
.NO_CURSOR = $ff
.CLEAN_FROM = $ff           ; .dirty_from/.dirty_to of a row with no
.CLEAN_TO   = 0             ; changes to draw
.ROWS = 24

!if ((BITMAP80 & $1fff) != 0) | ((BITMAP80 & $c000) != (MATRIX80 & $c000)) {
    !error "The bitmap and its colours must be in one VIC bank"
}

; Shows 80 blank columns above the status line.
s80_start:
    jsr .make_font
    lda #" "
    sta .left
    sta .right
    jsr .make_pattern
    lda #.NO_CURSOR
    sta .cursor_column
    ldx #23
-   lda #.CLEAN_FROM
    sta .dirty_from,x
    lda #.CLEAN_TO
    sta .dirty_to,x
    dex
    bpl -
    lda #0
    sta .pending
    sta .dirty

    lda #0
    ldx #>BITMAP80
    ldy #$20
    jsr .fill_pages
    lda #0
    ldx #>MATRIX80
    ldy #4
    jsr .fill_pages
    ldx #0                  ; text rows hidden under the bitmap: black,
    lda #COLOR_BLACK        ; as the split briefly shows part of the
-   sta COLOR_RAM,x         ; row above it in text mode
    sta COLOR_RAM + $100,x
    sta COLOR_RAM + $200,x
    sta COLOR_RAM + 24 * 40 - $100,x
    inx
    bne -
    lda #<.no_kernal_nmi
    sta $fffa
    lda #>.no_kernal_nmi
    sta $fffb
    lda #<.no_kernal_irq
    sta $fffe
    lda #>.no_kernal_irq
    sta $ffff

    sei
    lda $0314
    sta .old_irq+1
    lda $0315
    sta .old_irq+2
    lda #<.irq
    sta $0314
    lda #>.irq
    sta $0315
    lda #0
    sta .phase
    lda #24
    jsr s80_text_from
    lda #.TOP_LINE
    sta $d012
    lda $d011
    and #$7f
    sta $d011
    lda #1
    sta $d01a               ; raster interrupt on
    sta $d019
    sta .active
    cli
    rts

; Back to the text screen only.
s80_stop:
    lda .active
    beq +
    sei
    lda #0
    sta .active
    sta $d01a
    lda #1
    sta $d019
    lda .old_irq+1
    sta $0314
    lda .old_irq+2
    sta $0315
    lda $d011
    and #$ff - .BMM - $80
    sta $d011
    lda $dd00
    ora #$03                ; VIC bank 0
    sta $dd00
    cli
+   rts

; A = first row (17-24) to show from the text screen.
s80_text_from:
    asl
    asl
    asl
    clc
    adc #.FIRST_LINE - 2    ; the interrupt takes most of a line
    sta .split_line
    rts

; X = row, A = first column, Y = column after the last: those cells
; changed. Preserves X and Y.
s80_touch:
    cmp .dirty_from,x
    bcs +
    sta .dirty_from,x
+   tya
    cmp .dirty_to,x
    bcc +
    sta .dirty_to,x
+   lda #1
    sta .dirty
    rts

; All cells changed.
s80_touch_all:
    ldx #.ROWS-1
-   lda #0
    sta .dirty_from,x
    lda #80
    sta .dirty_to,x
    dex
    bpl -
    stx .dirty
    rts

; The cells of rows X+1 to Y moved up to X to Y-1; the caller then
; erases row Y. The bitmap follows at the next s80_flush, all such
; moves of one region together.
s80_scroll_up:
    stx .top
    sty .bottom
    lda .pending
    beq .new_region
    cpx .scroll_top
    bne +
    cpy .scroll_bottom
    beq .same_region
+   jsr s80_flush
.new_region:
    lda .top
    sta .scroll_top
    lda .bottom
    sta .scroll_bottom
.same_region:
    lda .pending
    cmp #.ROWS              ; from there on every row is redrawn anyway
    bcs +
    inc .pending
+   ldx .top                ; what was still to be drawn moves along
-   cpx .bottom
    bcs +
    lda .dirty_from+1,x
    sta .dirty_from,x
    lda .dirty_to+1,x
    sta .dirty_to,x
    inx
    bne -
+   lda #.CLEAN_FROM
    sta .dirty_from,x
    lda #.CLEAN_TO
    sta .dirty_to,x
    rts

; The cells of rows X to Y-1 moved down to X+1 to Y; the caller then
; erases row X. Rare enough (reverse index, inserted lines) to move
; the bitmap straight away.
s80_scroll_down:
    stx .top
    sty .bottom
    jsr s80_flush
    ldy .bottom
-   cpy .top
    beq +
    bcc +
    sty .row
    tya
    tax
    dex
    jsr s80_copy_row
    ldy .row
    dey
    jmp -
+   rts

; Brings the bitmap up to date with the cells.
s80_flush:
    lda .active
    beq .flushed
    lda .pending
    beq .draw_changes
    lda .scroll_top         ; rows .scroll_top + .pending ... up by
-   sta .row                ; .pending rows
    clc
    adc .pending
    cmp .scroll_bottom
    beq +
    bcs ++
+   tax
    ldy .row
    jsr s80_copy_row
    lda .row
    clc
    adc #1
    bne -                   ; always
++  lda #0
    sta .pending
.draw_changes:
    lda .dirty
    beq .flushed
    lda #0
    sta .dirty
    ldx #0
-   lda .dirty_from,x
    cmp .dirty_to,x
    bcs +
    pha
    ldy .dirty_to,x
    lda #.CLEAN_FROM
    sta .dirty_from,x
    lda #.CLEAN_TO
    sta .dirty_to,x
    stx .row
    jsr term_row_cells
    pla
    jsr s80_draw
    ldx .row
+   inx
    cpx #.ROWS
    bcc -
.flushed:
    rts

; X = row (0-23), zp_a/zp_b = its 80 screen codes and colours,
; A = first column, Y = column after the last. Draws the blocks that
; hold those columns. Preserves zp_a and zp_b.
s80_draw:
    sta .pair
    iny
    tya
    lsr
    sta .end_pair
    lsr .pair
    lda .pair               ; the block's address: row + pair * 8
    lsr
    lsr
    lsr
    lsr
    lsr
    sta .tmp
    lda .pair
    asl
    asl
    asl
    clc
    adc .bitmap_lo,x
    sta .store+1
    lda .bitmap_hi,x
    adc .tmp
    sta .store+2
    lda .matrix_lo,x
    clc
    adc .pair
    sta .matrix_store+1
    lda .matrix_hi,x
    adc #0
    sta .matrix_store+2

.next_pair:
    lda .pair
    asl
    tay
    lda (zp_b),y
    and #$0f
    sta .left_color
    lda (zp_a),y
    cpy .cursor_column
    bne +
    eor #$80
+   tax
    iny
    lda (zp_b),y
    and #$0f
    sta .right_color
    lda (zp_a),y
    cpy .cursor_column
    bne +
    eor #$80
+   cpx .left               ; the same pair as last time: same pattern
    bne +
    cmp .right
    beq ++
+   stx .left
    sta .right
    jsr .make_pattern
++  lda .left_color
    ldx .left
    cpx #" "
    bne +
    lda .right_color
+   asl
    asl
    asl
    asl
.matrix_store:
    sta $ffff
    ldy #7
-   lda .pattern,y
.store:
    sta $ffff,y
    dey
    bpl -

    inc .matrix_store+1
    bne +
    inc .matrix_store+2
+   lda .store+1
    clc
    adc #8
    sta .store+1
    bcc +
    inc .store+2
+   inc .pair
    lda .pair
    cmp .end_pair
    bcc .next_pair
    rts

; Like s80_draw for the one column in A, with that character in
; reverse video: the cursor.
s80_draw_cursor:
    sta .cursor_column
    tay
    iny
    jsr s80_draw
    lda #.NO_CURSOR
    sta .cursor_column
    rts

; Copies bitmap row X, and its colours, to row Y: 320 bytes, as five
; runs of 64 copied side by side.
s80_copy_row:
    lda .bitmap_lo,x
    sta .address
    lda .bitmap_hi,x
    sta .address+1
    !for .k, 0, 4 {
        lda .address
        sta .copy_runs + .k * 6 + 1
        clc
        adc #64
        sta .address
        lda .address+1
        sta .copy_runs + .k * 6 + 2
        adc #0
        sta .address+1
    }
    lda .bitmap_lo,y
    sta .address
    lda .bitmap_hi,y
    sta .address+1
    !for .k, 0, 4 {
        lda .address
        sta .copy_runs + .k * 6 + 4
        clc
        adc #64
        sta .address
        lda .address+1
        sta .copy_runs + .k * 6 + 5
        adc #0
        sta .address+1
    }
    lda .matrix_lo,x
    sta .from_matrix+1
    lda .matrix_hi,x
    sta .from_matrix+2
    lda .matrix_lo,y
    sta .to_matrix+1
    lda .matrix_hi,y
    sta .to_matrix+2

    lda #R6510_NO_KERNAL
    sta R6510
    ldx #0
.copy_runs:
    !for .k, 0, 4 {
        lda $ffff,x         ; 6 bytes each: the operands are patched
        sta $ffff,x
    }
    inx
    cpx #64
    bne .copy_runs
    lda #R6510_DEFAULT
    sta R6510

    ldx #39
.from_matrix:
-   lda $ffff,x
.to_matrix:
    sta $ffff,x
    dex
    bpl -
    rts

; .left/.right = screen codes; makes .pattern, the 8 bytes of their
; block.
.make_pattern:
    lda .left
    jsr .glyph_address
    sta .left_rows+1
    stx .left_rows+2
    lda .right
    jsr .glyph_address
    sta .right_rows+1
    stx .right_rows+2
    lda .left               ; reverse video: inverted pixels
    and #$80
    beq +
    lda #$f0
+   sta .left_mask
    lda .right
    and #$80
    beq +
    lda #$0f
+   sta .right_mask
    ldy #7
.left_rows:
-   lda $ffff,y
    and #$f0
    eor .left_mask
    sta .tmp
.right_rows:
    lda $ffff,y
    and #$0f
    eor .right_mask
    ora .tmp
    sta .pattern,y
    dey
    bpl -
    rts

; A = screen code; returns A/X = the address of its glyph.
.glyph_address:
    and #$7f
    sta .tmp
    lda #0
    asl .tmp
    rol
    asl .tmp
    rol
    asl .tmp
    rol
    adc #>FONT80
    tax
    lda .tmp
    rts

; Builds FONT80 from CHARSET (codes $00-$7f; $80-$ff are the same
; reversed): rows of 4 pixels, in both halves of each byte so that the
; left or right character of a block can be had with an AND.
.make_font:
    lda #<CHARSET
    sta zp_a
    lda #>CHARSET
    sta zp_a+1
    lda #<FONT80
    sta zp_b
    lda #>FONT80
    sta zp_b+1
    ldx #4
    ldy #0
-   lda (zp_a),y
    jsr .halve
    sta (zp_b),y
    iny
    bne -
    inc zp_a+1
    inc zp_b+1
    dex
    bne -

    ldx #0
.own_glyph:
    lda .own_glyphs,x
    cmp #.END_OF_GLYPHS
    beq .font_done
    sta zp_b
    lda #0
    asl zp_b
    rol
    asl zp_b
    rol
    asl zp_b
    rol
    adc #>FONT80
    sta zp_b+1
    inx
    ldy #0
-   lda .own_glyphs,x
    sta .tmp
    asl
    asl
    asl
    asl
    ora .tmp
    sta (zp_b),y
    inx
    iny
    cpy #8
    bne -
    beq .own_glyph
.font_done:
    rts

; A = a row of 8 pixels; returns it 4 pixels wide (pixels 1 or 2,
; 3 or 4, 5 or 6, 7: the ROM font draws on those pairs) in both
; halves. Preserves X and Y.
.halve:
    sta .tmp
    asl
    ora .tmp                ; bit 7-n: pixel n or n+1
    sta .tmp
    lda #0
    !for .i, 0, 3 {
        asl .tmp
        asl .tmp
        rol
    }
    sta .tmp
    asl
    asl
    asl
    asl
    ora .tmp
    rts

; A = value, X = first page, Y = number of pages
.fill_pages:
    stx .fill+2
    ldx #0
.fill:
    sta $ff00,x
    inx
    bne .fill
    inc .fill+2
    dey
    bne .fill
    rts

;---------------------------------------------------------
; Interrupts
;---------------------------------------------------------

; Raster interrupts switch between the bitmap and the text screen.
; The KERNAL's own (timer) interrupt still scans the keyboard, but
; lets raster interrupts in meanwhile, so that they stay on time.
.irq:
    lda $d019
    and #1
    beq .timer
    sta $d019
    lda .phase
    bne .to_text
    lda $d011
    and #$7f
    ora #.BMM
    sta $d011
    lda #.BITMAP_D018
    sta $d018
    lda $dd00
    and #$fc                ; VIC bank 3
    sta $dd00
    inc .phase
    lda .split_line
    bne .next_line          ; always
.to_text:
    lda $d011
    and #$ff - .BMM - $80
    sta $d011
    lda #VIC_CUSTOM_CHARSET
    sta $d018
    lda $dd00
    ora #$03                ; VIC bank 0
    sta $dd00
    lda #0
    sta .phase
    lda #.TOP_LINE
.next_line:
    sta $d012
    jmp .KERNAL_IRQ_RETURN
.timer:
    lda $dc0d               ; acknowledged, so it does not come again
    cli
.old_irq:
    jmp .KERNAL_IRQ         ; the handler that was there before

; Taken instead of the KERNAL's interrupt entries while the KERNAL
; ROM is switched off (in s80_copy_row): they switch it on, run the
; handler as the KERNAL would, and switch it back off after its RTI.
; RUN/STOP + RESTORE does not return: the KERNAL resets the memory
; configuration, the VIC and the interrupt vector, and starts BASIC.
; No variables, as an NMI can come in the middle of the IRQ entry.

; With the interrupted A on the stack: switches the KERNAL ROM on and
; makes the next RTI return to .back.
!macro kernal_on .back {
    lda R6510
    pha
    lda #R6510_DEFAULT
    sta R6510
    lda #>.back
    pha
    lda #<.back
    pha
    php
}

.no_kernal_irq:
    pha
    +kernal_on .kernal_off
    pha                     ; the KERNAL's IRQ entry saves A, X and Y
    txa                     ; before it jumps through $0314; its NMI
    pha                     ; handler does that itself
    tya
    pha
    jmp ($0314)
.no_kernal_nmi:
    pha
    +kernal_on .kernal_off
    jmp ($0318)
.kernal_off:
    pla
    sta R6510
    pla
    rti

.bitmap_lo: !for .r, 0, 23 { !byte <(BITMAP80 + .r * 320) }
.bitmap_hi: !for .r, 0, 23 { !byte >(BITMAP80 + .r * 320) }
.matrix_lo: !for .r, 0, 23 { !byte <(MATRIX80 + .r * 40) }
.matrix_hi: !for .r, 0, 23 { !byte >(MATRIX80 + .r * 40) }

; Screen code, then 8 rows of 4 pixels
.END_OF_GLYPHS = $ff
.own_glyphs:
    !byte $00, %.#.., %#.#., %###., %###., %#..., %.##., %...., %....  ; @
    !byte $0d, %...., %...., %#.#., %###., %###., %#.#., %#.#., %....  ; m
    !byte $17, %...., %...., %#.#., %#.#., %###., %###., %#.#., %....  ; w
    !byte $4d, %#.#., %###., %###., %#.#., %#.#., %#.#., %#.#., %....  ; M
    !byte $4e, %#..#, %##.#, %##.#, %#.##, %#.##, %#..#, %#..#, %....  ; N
    !byte $57, %#.#., %#.#., %#.#., %#.#., %###., %###., %#.#., %....  ; W
    !byte $25, %#.#., %..#., %.#.., %.#.., %#..., %#.#., %...., %....  ; %
    !byte $30, %###., %#.#., %#.#., %#.#., %#.#., %#.#., %###., %....  ; 0
    !byte $42, %##.., %#.#., %#.#., %##.., %#.#., %#.#., %##.., %....  ; B
    !byte $44, %##.., %#.#., %#.#., %#.#., %#.#., %#.#., %##.., %....  ; D
    !byte $47, %.##., %#..., %#..., %#.#., %#.#., %#.#., %.##., %....  ; G
    !byte $4a, %..#., %..#., %..#., %..#., %..#., %#.#., %.#.., %....  ; J
    !byte $4f, %.#.., %#.#., %#.#., %#.#., %#.#., %#.#., %.#.., %....  ; O
    !byte $51, %.#.., %#.#., %#.#., %#.#., %#.#., %##.., %.##., %....  ; Q
    !byte $52, %##.., %#.#., %#.#., %##.., %#.#., %#.#., %#.#., %....  ; R
    !byte SC_BACKSLASH
    !byte      %...., %#..., %#..., %.#.., %.#.., %..#., %..#., %....
    !byte SC_BACKTICK
    !byte      %#..., %.#.., %...., %...., %...., %...., %...., %....
    !byte SC_TILDE
    !byte      %...., %...., %.#.#, %#.#., %...., %...., %...., %....
    !byte SC_SHADE                                        ; ▒
    !byte      %#.#., %.#.#, %#.#., %.#.#, %#.#., %.#.#, %#.#., %.#.#
    !byte $5c, %#..., %.#.., %#..., %.#.., %#..., %.#.., %#..., %.#..  ; left half ▒
    !byte $68, %...., %...., %...., %...., %#.#., %.#.#, %#.#., %.#.#  ; lower half ▒
    !byte .END_OF_GLYPHS

.active:       !byte 0
.phase:        !byte 0      ; 0: the next interrupt is at the top
.split_line:   !byte 0
.pair:         !byte 0
.end_pair:     !byte 0
.cursor_column: !byte .NO_CURSOR
.left:         !byte 0
.right:        !byte 0
.left_color:   !byte 0
.right_color:  !byte 0
.left_mask:    !byte 0
.right_mask:   !byte 0
.tmp:          !byte 0
.pattern:      !fill 8, 0
.address:      !word 0
.row:          !byte 0
.top:          !byte 0
.bottom:       !byte 0
.pending:      !byte 0      ; rows to move the bitmap up by
.scroll_top:   !byte 0      ; in this region
.scroll_bottom: !byte 0
.dirty:        !byte 0      ; 1 if a row has changes to draw
.dirty_from:   !fill .ROWS, .CLEAN_FROM
.dirty_to:     !fill .ROWS, .CLEAN_TO
}

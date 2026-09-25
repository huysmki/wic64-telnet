;---------------------------------------------------------
; ANSI / VT100 terminal on a 40 x 24 screen
;
; Interprets the ASCII byte stream from the server, including the
; escape sequences used by BBSes (ANSI.SYS) and Unix full-screen
; programs (VT100/xterm subset), and draws directly into screen
; memory using the ASCII character set at CHARSET. Row 24 is left
; alone for the session's status line.
;
; Supported: cursor movement and addressing, erase in display/line,
; insert/delete lines and characters, scroll regions, SGR colours
; (8 + 8 bright, bold, reverse), save/restore cursor, cursor position
; and device attribute reports, DEC line drawing, autowrap and cursor
; visibility modes. Unknown sequences are parsed and ignored.
;
; The C64 has a single background colour, so a coloured ANSI
; background is shown as reverse video in that colour.
;---------------------------------------------------------

!zone ansi {
.ROWS = 24
.LAST_ROW = .ROWS - 1
.LAST_COL = 39
.MAX_PARAMS = 8
.DEFAULT_FG = 7
.NO_BG = $ff

; parser states
.TEXT     = 0
.ESC      = 1
.CSI      = 2
.OSC      = 3
.G0       = 4   ; after ESC (
.G1       = 5   ; after ESC )
.SKIP_ONE = 6   ; after ESC # or ESC %

; Full reset: default attributes and modes, cleared screen, cursor home.
ansi_reset:
    lda #0
    sta ansi_x
    sta ansi_y
    sta .pending_wrap
    sta .top
    sta .shift_out
    sta .g0_graphics
    sta .g1_graphics
    sta .state
    sta .utf8_needed
    lda #.LAST_ROW
    sta .bottom
    lda #1
    sta .autowrap
    sta .cursor_enabled
    jsr .reset_attributes
    jsr .save_cursor
    ldx #0
    ldy #.LAST_ROW
    jmp .erase_rows

; Returns the cursor cell for drawing it: X/Y = screen address,
; A = colour. C=1 if the cursor is switched off.
ansi_cursor_cell:
    lda .cursor_enabled
    bne +
    sec
    rts
+   ldx ansi_y
    lda screen_row_lo,x
    clc
    adc ansi_x
    pha
    lda screen_row_hi,x
    adc #0
    tay
    pla
    tax
    lda .draw_color
    bne +
    lda #COLOR_LIGHT_GREY   ; never draw an invisible black cursor
+   clc
    rts

;---------------------------------------------------------
; Input: bytes from the server
;---------------------------------------------------------

; Byte in CP437 (PC BBS character set)
ansi_output_cp437:
    cmp #$80
    bcs +
    jmp .ascii
+   tax
    lda cp437_to_screen-$80,x
    jmp .glyph

; Byte in UTF-8
ansi_output_utf8:
    ldx .utf8_needed
    bne .utf8_continuation
    cmp #$80
    bcs +
    jmp .ascii
+   cmp #$c0
    bcc .utf8_invalid       ; continuation byte without a start
    ldx #0
    stx .codepoint+1
    stx .utf8_too_big
    cmp #$e0
    bcs +
    and #$1f
    ldx #1
    bne .utf8_start
+   cmp #$f0
    bcs +
    and #$0f
    ldx #2
    bne .utf8_start
+   ldx #1                  ; beyond U+FFFF: shown as "?"
    stx .utf8_too_big
    ldx #3
.utf8_start:
    sta .codepoint
    stx .utf8_needed
    rts

.utf8_continuation:
    cmp #$80
    bcc .utf8_cut_short
    cmp #$c0
    bcs .utf8_cut_short
    and #$3f
    ldx #6
-   asl .codepoint
    rol .codepoint+1
    dex
    bne -
    ora .codepoint
    sta .codepoint
    dec .utf8_needed
    bne +
    jmp .show_codepoint
+   rts

; A sequence ended early: show a "?" and process the byte afresh.
.utf8_cut_short:
    pha
    lda #0
    sta .utf8_needed
    lda #"?"
    jsr .print_ascii
    pla
    jmp ansi_output_utf8

.utf8_invalid:
    lda #"?"
    jmp .print_ascii

.show_codepoint:
    lda .utf8_too_big
    bne .unknown
    lda .codepoint+1
    bne .above_latin1
    lda .codepoint
    cmp #$a0
    bcc .ignore             ; C1 controls and overlong ASCII
    tax
    lda latin1_to_ascii-$a0,x
    jmp .print_ascii

.above_latin1:
    cmp #$25
    bne .search_table
    lda .codepoint
    cmp #$a0
    bcs .search_table
    tax
    lda box_to_screen,x     ; U+2500-U+259F: box drawing and blocks
    jmp .glyph

.search_table:
    ldx #0
-   lda misc_codepoints,x
    beq .unknown
    cmp .codepoint+1
    bne +
    lda misc_codepoints+1,x
    cmp .codepoint
    bne +
    lda misc_codepoints+2,x
    jmp .glyph
+   inx
    inx
    inx
    bne -
.unknown:
    lda #"?"
    jmp .print_ascii
.ignore:
    rts

; A = printable ASCII character
.print_ascii:
    jsr ascii_to_screen

; A = screen code to print. Printable characters end any sequence.
.glyph:
    ldx #.TEXT
    stx .state
    jmp .put

; A = byte below $80: text, control code or part of a sequence
.ascii:
    ldx .state
    beq .text
    cpx #.OSC
    bne +
    jmp .osc
+   cmp #$20
    bcs +
    jmp .control            ; controls act even inside sequences
+   cpx #.ESC
    bne +
    jmp .esc
+   cpx #.CSI
    bne +
    jmp .csi
+   cpx #.SKIP_ONE
    beq .end_sequence
    ; .G0 or .G1: "0" selects DEC line drawing, anything else ASCII
    ldy #0
    cmp #"0"
    bne +
    iny
+   cpx #.G0
    bne +
    sty .g0_graphics
    jmp .end_sequence
+   sty .g1_graphics
.end_sequence:
    lda #.TEXT
    sta .state
    rts

.text:
    cmp #$20
    bcs +
    jmp .control
+   cmp #$7f
    beq .ignore
    ldx .shift_out
    ldy .g0_graphics,x      ; .g1_graphics follows .g0_graphics
    beq .print_ascii
    cmp #$60
    bcc .print_ascii
    tax
    lda dec_graphics_to_screen-$60,x
    jmp .put

.control:
    cmp #$1b
    bne +
    lda #.ESC
    sta .state
    rts
+   cmp #$0d
    bne +
    lda #0
    sta ansi_x
    sta .pending_wrap
    rts
+   cmp #$0a                ; LF, VT and FF all move down a line
    bcc +
    cmp #$0d
    bcs +
    jmp .linefeed
+   cmp #$08
    bne +
    jmp .backspace
+   cmp #$09
    bne +
    jmp .tab
+   cmp #$07
    bne +
    jmp ui_bell
+   cmp #$0e
    bne +
    lda #1
    sta .shift_out
    rts
+   cmp #$0f
    bne +
    lda #0
    sta .shift_out
    rts
+   cmp #$18                ; CAN and SUB cancel a sequence
    beq .end_sequence
    cmp #$1a
    beq .end_sequence
    rts

.osc:
    ; operating system command (e.g. window title): skipped up to BEL
    ; or ESC (the start of the ST terminator ESC \)
    cmp #$07
    beq .end_sequence
    cmp #$1b
    bne +
    lda #.ESC
    sta .state
+   rts

.esc:
    ldx #.TEXT
    stx .state
    cmp #"["
    bne +
    ldx #.CSI
    stx .state
    lda #0
    sta .param_index
    sta .private
    ldx #.MAX_PARAMS-1
-   sta .params,x
    dex
    bpl -
    rts
+   cmp #"]"
    bne +
    lda #.OSC
    sta .state
    rts
+   cmp #"("
    bne +
    lda #.G0
    sta .state
    rts
+   cmp #")"
    bne +
    lda #.G1
    sta .state
    rts
+   cmp #"#"
    beq .skip_one
    cmp #"%"
    beq .skip_one
    cmp #"7"
    bne +
    jmp .save_cursor
+   cmp #"8"
    bne +
    jmp .restore_cursor
+   cmp #"D"
    bne +
    jmp .linefeed
+   cmp #"E"
    bne +
    lda #0
    sta ansi_x
    jmp .linefeed
+   cmp #"M"
    bne +
    jmp .reverse_index
+   cmp #"c"
    bne +
    jmp ansi_reset
+   rts
.skip_one:
    lda #.SKIP_ONE
    sta .state
    rts

.csi:
    cmp #"0"
    bcc .csi_not_digit
    cmp #$3a                ; after 9
    bcs .csi_not_digit
    ; params[i] = params[i] * 10 + digit, saturating at 255
    and #$0f
    sta .digit
    ldx .param_index
    lda .params,x
    cmp #26
    bcs .saturate
    asl
    sta .times2
    asl
    asl
    adc .times2
    adc .digit
    bcs .saturate
    sta .params,x
    rts
.saturate:
    lda #255
    sta .params,x
    rts

.csi_not_digit:
    cmp #";"
    beq .next_param
    cmp #":"
    beq .next_param
    cmp #"<"
    bcc +
    cmp #$40                ; after ?
    bcs +
    lda #1                  ; < = > ? mark private sequences
    sta .private
    rts
+   cmp #"@"
    bcc .csi_ignore         ; intermediate bytes
    cmp #$7f
    bcs .csi_ignore
    ldx #.TEXT
    stx .state
    ldx .private
    bne .private_final
    ldx #.CSI_COUNT-1
-   cmp .csi_finals,x
    beq +
    dex
    bpl -
    rts
+   lda .csi_hi,x
    pha
    lda .csi_lo,x
    pha
    rts

.next_param:
    lda .param_index
    cmp #.MAX_PARAMS-1
    bcs .csi_ignore
    inc .param_index
.csi_ignore:
    rts

.private_final:
    ldy #1
    cmp #"h"
    beq .dec_mode
    dey
    cmp #"l"
    beq .dec_mode
    rts

; Y = 1 to set, 0 to reset the DEC private modes in the parameters
.dec_mode:
    ldx #0
-   lda .params,x
    cmp #25
    bne +
    sty .cursor_enabled
+   cmp #7
    bne +
    sty .autowrap
+   inx
    cpx .param_index
    bcc -
    beq -
    rts

.CSI_COUNT = 28
.csi_finals:
    !byte "A", "B", "C", "D", "E", "F", "G", "`", "H", "f", "d", "e", "a"
    !byte "J", "K", "L", "M", "P", "@", "X", "S", "T", "m", "r", "s", "u", "n", "c"
.csi_lo:
    !byte <(.cursor_up-1), <(.cursor_down-1), <(.cursor_right-1), <(.cursor_left-1)
    !byte <(.next_line-1), <(.previous_line-1), <(.column-1), <(.column-1)
    !byte <(.position-1), <(.position-1), <(.row-1), <(.cursor_down-1), <(.cursor_right-1)
    !byte <(.erase_display-1), <(.erase_line-1), <(.insert_lines-1), <(.delete_lines-1)
    !byte <(.delete_chars-1), <(.insert_chars-1), <(.erase_chars-1), <(.scroll_up-1)
    !byte <(.scroll_down-1), <(.sgr-1), <(.set_margins-1), <(.save_cursor-1)
    !byte <(.restore_cursor-1), <(.status_report-1), <(.device_attributes-1)
.csi_hi:
    !byte >(.cursor_up-1), >(.cursor_down-1), >(.cursor_right-1), >(.cursor_left-1)
    !byte >(.next_line-1), >(.previous_line-1), >(.column-1), >(.column-1)
    !byte >(.position-1), >(.position-1), >(.row-1), >(.cursor_down-1), >(.cursor_right-1)
    !byte >(.erase_display-1), >(.erase_line-1), >(.insert_lines-1), >(.delete_lines-1)
    !byte >(.delete_chars-1), >(.insert_chars-1), >(.erase_chars-1), >(.scroll_up-1)
    !byte >(.scroll_down-1), >(.sgr-1), >(.set_margins-1), >(.save_cursor-1)
    !byte >(.restore_cursor-1), >(.status_report-1), >(.device_attributes-1)

;---------------------------------------------------------
; Sequence handlers
;---------------------------------------------------------

; A = first parameter, 1 if omitted or 0
.count:
    lda .params
    bne +
    lda #1
+   rts

.cursor_up:
    ldx #0                  ; stop at the top margin when below it
    lda ansi_y
    cmp .top
    bcc +
    ldx .top
+   stx .limit
    jsr .count
    sta .n
    lda ansi_y
    sec
    sbc .n
    bcc +
    cmp .limit
    bcs ++
+   lda .limit
++  sta ansi_y
    jmp .clear_wrap

.cursor_down:
    ldx #.LAST_ROW          ; stop at the bottom margin when above it
    lda ansi_y
    cmp .bottom
    beq +
    bcs ++
+   ldx .bottom
++  stx .limit
    jsr .count
    clc
    adc ansi_y
    bcs +
    cmp .limit
    bcc ++
+   lda .limit
++  sta ansi_y
    jmp .clear_wrap

.cursor_right:
    jsr .count
    clc
    adc ansi_x
    bcs +
    cmp #.LAST_COL
    bcc ++
+   lda #.LAST_COL
++  sta ansi_x
    jmp .clear_wrap

.cursor_left:
    jsr .count
    sta .n
    lda ansi_x
    sec
    sbc .n
    bcs +
    lda #0
+   sta ansi_x
    jmp .clear_wrap

.next_line:
    jsr .cursor_down
    lda #0
    sta ansi_x
    rts

.previous_line:
    jsr .cursor_up
    lda #0
    sta ansi_x
    rts

.column:
    jsr .count
    tax
    dex
    txa
    jsr .clamp_column
    sta ansi_x
    jmp .clear_wrap

.row:
    jsr .count
    tax
    dex
    txa
    jsr .clamp_row
    sta ansi_y
    jmp .clear_wrap

.position:
    jsr .count
    tax
    dex
    txa
    jsr .clamp_row
    sta ansi_y
    lda .params+1
    beq +
    tax
    dex
    txa
+   jsr .clamp_column
    sta ansi_x
    jmp .clear_wrap

.clamp_row:
    cmp #.ROWS
    bcc +
    lda #.LAST_ROW
+   rts

.clamp_column:
    cmp #.LAST_COL+1
    bcc +
    lda #.LAST_COL
+   rts

.erase_display:
    lda .params
    beq .erase_below
    cmp #1
    beq .erase_above
    ; 2 or 3: everything; like ANSI.SYS the cursor goes home
    ldx #0
    ldy #.LAST_ROW
    jsr .erase_rows
    lda #0
    sta ansi_x
    sta ansi_y
    jmp .clear_wrap

.erase_below:
    jsr .erase_line_right
    ldx ansi_y
    inx
    ldy #.LAST_ROW
    jmp .erase_rows

.erase_above:
    jsr .erase_line_left
    ldx #0
    ldy ansi_y
    dey
    bmi +
    jmp .erase_rows
+   rts

.erase_line:
    lda .params
    beq .erase_line_right
    cmp #1
    beq .erase_line_left
    ldx ansi_y
    jmp .erase_row

.erase_line_right:
    lda ansi_x
    sta .from
    lda #.LAST_COL+1
    sta .to
    ldx ansi_y
    jmp .erase_span

.erase_line_left:
    lda #0
    sta .from
    ldx ansi_x
    inx
    stx .to
    ldx ansi_y
    jmp .erase_span

; Insert/delete lines only act inside the scroll region.
.insert_lines:
    jsr .lines_in_region
    bcs +
-   ldx ansi_y
    ldy .bottom
    jsr .scroll_rows_down
    dec .n
    bne -
+   rts

.delete_lines:
    jsr .lines_in_region
    bcs +
-   ldx ansi_y
    ldy .bottom
    jsr .scroll_rows_up
    dec .n
    bne -
+   rts

; .n = line count limited to the rest of the region, C=1 if the
; cursor is outside the region.
.lines_in_region:
    lda ansi_y
    cmp .top
    bcc .outside
    cmp .bottom
    beq +
    bcs .outside
+   lda #0
    sta ansi_x
    sta .pending_wrap
    lda .bottom
    sec
    sbc ansi_y
    tax
    inx
    stx .limit
    jsr .count
    cmp .limit
    bcc +
    lda .limit
+   sta .n
    clc
    rts
.outside:
    sec
    rts

.scroll_up:
    jsr .scroll_count
-   ldx .top
    ldy .bottom
    jsr .scroll_rows_up
    dec .n
    bne -
    rts

.scroll_down:
    jsr .scroll_count
-   ldx .top
    ldy .bottom
    jsr .scroll_rows_down
    dec .n
    bne -
    rts

.scroll_count:
    jsr .count
    cmp #.ROWS
    bcc +
    lda #.ROWS
+   sta .n
    rts

; .n = character count limited to the rest of the line
.chars_to_line_end:
    lda #.LAST_COL+1
    sec
    sbc ansi_x
    sta .limit
    jsr .count
    cmp .limit
    bcc +
    lda .limit
+   sta .n
    lda #0
    sta .pending_wrap
    ldx ansi_y
    jmp .point_at_row

.delete_chars:
    jsr .chars_to_line_end
    ldy ansi_x
-   sty .i
    tya
    clc
    adc .n
    cmp #.LAST_COL+1
    bcs +
    tay
    lda (zp_a),y
    tax
    lda (zp_b),y
    ldy .i
    sta (zp_b),y
    txa
    sta (zp_a),y
    iny
    bne -
+   lda .i
    sta .from
    lda #.LAST_COL+1
    sta .to
    ldx ansi_y
    jmp .erase_span

.insert_chars:
    jsr .chars_to_line_end
    ldy #.LAST_COL
-   sty .i
    tya
    sec
    sbc .n
    bcc +
    cmp ansi_x
    bcc +
    tay
    lda (zp_a),y
    tax
    lda (zp_b),y
    ldy .i
    sta (zp_b),y
    txa
    sta (zp_a),y
    dey
    bpl -
+   jmp .erase_n_chars

.erase_chars:
    jsr .chars_to_line_end
.erase_n_chars:
    lda ansi_x
    sta .from
    clc
    adc .n
    sta .to
    ldx ansi_y
    jmp .erase_span

.set_margins:
    jsr .count
    tax
    dex
    stx .new_top
    lda .params+1
    beq +
    cmp #.ROWS+1
    bcc ++
+   lda #.ROWS
++  tax
    dex
    cpx .new_top
    beq +
    bcc +
    stx .bottom
    lda .new_top
    sta .top
+   lda #0
    sta ansi_x
    sta ansi_y
    jmp .clear_wrap

.save_cursor:
    ldx #.SAVED_COUNT-1
-   lda ansi_x,x
    sta .saved,x
    dex
    bpl -
    rts

.restore_cursor:
    ldx #.SAVED_COUNT-1
-   lda .saved,x
    sta ansi_x,x
    dex
    bpl -
    jsr .update_colors
    jmp .clear_wrap

.status_report:
    lda .params
    cmp #6
    beq .report_position
    cmp #5
    bne +
    lda #<.ok_report        ; "terminal OK"
    ldy #>.ok_report
    jmp .send_string
+   rts

; Answers ESC [ row ; column R
.report_position:
    lda #$1b
    jsr telnet_send
    lda #"["
    jsr telnet_send
    ldx ansi_y
    inx
    txa
    jsr .send_decimal
    lda #";"
    jsr telnet_send
    ldx ansi_x
    inx
    txa
    jsr .send_decimal
    lda #"R"
    jmp telnet_send

.device_attributes:
    lda .params
    bne +
    lda #<.vt100_attributes
    ldy #>.vt100_attributes
    jmp .send_string
+   rts

.send_string:
    sta .string+1
    sty .string+2
    ldx #0
.string:
    lda $ffff,x
    beq +
    jsr telnet_send
    inx
    bne .string
+   rts

; A = 1-99
.send_decimal:
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
    jsr telnet_send
+   pla
    ora #"0"
    jmp telnet_send

.ok_report:        !text $1b, "[0n", 0
.vt100_attributes: !text $1b, "[?1;0c", 0

;---------------------------------------------------------
; Colours (SGR)
;---------------------------------------------------------

.sgr:
    ldx #0
.sgr_next:
    cpx .param_index
    beq +
    bcs .sgr_done
+   lda .params,x
    inx
    stx .i
    jsr .sgr_param
    ldx .i
    jmp .sgr_next
.sgr_done:
    jmp .update_colors

; A = one SGR parameter; may consume more via .i
.sgr_param:
    cmp #0
    bne +
    jmp .reset_attributes
+   cmp #1
    bne +
    lda #1
    sta .bold
    rts
+   cmp #2
    beq .normal_intensity
    cmp #22
    bne +
.normal_intensity:
    lda #0
    sta .bold
    rts
+   cmp #7
    bne +
    lda #1
    sta .reverse
    rts
+   cmp #27
    bne +
    lda #0
    sta .reverse
    rts
+   cmp #38
    beq .extended_color
    cmp #48
    beq .extended_color
    cmp #39
    bne +
    lda #.DEFAULT_FG
    sta .fg
    rts
+   cmp #49
    bne +
.no_background:
    lda #.NO_BG
    sta .bg
    rts
+   cmp #40
    beq .no_background
    cmp #30
    bcc .sgr_ignore
    cmp #38
    bcs +
    sbc #30-1               ; carry is clear: subtracts 30
    sta .fg
    rts
+   cmp #41
    bcc .sgr_ignore
    cmp #48
    bcs +
    sbc #40-1
    sta .bg
    rts
+   cmp #90
    bcc .sgr_ignore
    cmp #98
    bcs +
    sbc #82-1               ; 90-97 -> bright colours 8-15
    sta .fg
    rts
+   cmp #100
    bcc .sgr_ignore
    cmp #108
    bcs .sgr_ignore
    sbc #92-1
    sta .bg
.sgr_ignore:
    rts

; 38/48 ; 5 ; n (256 colours, the first 16 are used) or
; 38/48 ; 2 ; r ; g ; b (true colour, skipped)
.extended_color:
    sta .which
    ldx .i
    lda .params,x
    cmp #2
    bne +
    inx
    inx
    inx
    inx
    stx .i
    rts
+   cmp #5
    bne .sgr_ignore
    lda .params+1,x
    inx
    inx
    stx .i
    cmp #16
    bcs .sgr_ignore
    ldx .which
    cpx #38
    bne +
    sta .fg
    rts
+   cmp #0
    beq .no_background
    sta .bg
    rts

.reset_attributes:
    lda #.DEFAULT_FG
    sta .fg
    lda #0
    sta .bold
    sta .reverse
    lda #.NO_BG
    sta .bg

; Derives what .put and the erase routines draw from the attributes.
.update_colors:
    lda .fg
    ldx .bold
    beq +
    ora #8
+   tax
    lda ansi_palette,x
    sta .fg_color
    lda .bg
    bpl .with_background

    lda #" "
    sta .erase_char
    lda .fg_color
    sta .erase_color
    sta .draw_color
    lda .reverse
    beq +
    lda #$80
+   sta .draw_mask
    rts

.with_background:
    tax
    lda ansi_palette,x
    sta .erase_color
    lda #$a0
    sta .erase_char
    lda #$80
    sta .draw_mask
    lda .reverse
    beq +
    lda .fg_color
    sta .draw_color
    rts
+   lda .erase_color
    sta .draw_color
    rts

;---------------------------------------------------------
; Drawing
;---------------------------------------------------------

; A = screen code; draws it at the cursor with the current colours.
; Like xterm, writing the last column only marks a pending wrap that
; the next character carries out.
.put:
    sta .char
    lda .pending_wrap
    beq +
    lda #0
    sta .pending_wrap
    lda .autowrap
    beq +
    lda #0
    sta ansi_x
    jsr .linefeed
+   ldx ansi_y
    jsr .point_at_row
    ldy ansi_x
    lda .char
    eor .draw_mask
    sta (zp_a),y
    lda .draw_color
    sta (zp_b),y
    cpy #.LAST_COL
    bcs +
    inc ansi_x
    rts
+   lda #1
    sta .pending_wrap
    rts

.clear_wrap:
    lda #0
    sta .pending_wrap
    rts

.linefeed:
    lda #0
    sta .pending_wrap
    lda ansi_y
    cmp .bottom
    bne +
    ldx .top
    ldy .bottom
    jmp .scroll_rows_up
+   cmp #.LAST_ROW
    bcs +
    inc ansi_y
+   rts

.reverse_index:
    lda #0
    sta .pending_wrap
    lda ansi_y
    cmp .top
    bne +
    ldx .top
    ldy .bottom
    jmp .scroll_rows_down
+   cmp #0
    beq +
    dec ansi_y
+   rts

.backspace:
    lda #0
    sta .pending_wrap
    lda ansi_x
    beq +
    dec ansi_x
+   rts

.tab:
    lda ansi_x
    and #$f8
    clc
    adc #8
    jsr .clamp_column
    sta ansi_x
    rts

; Points zp_a/zp_b at screen/colour row X. Preserves X.
.point_at_row:
    lda screen_row_lo,x
    sta zp_a
    sta zp_b
    lda screen_row_hi,x
    sta zp_a+1
    clc
    adc #COLOR_OFFSET_HI
    sta zp_b+1
    rts

; X = row; erases columns .from up to (not including) .to
.erase_span:
    jsr .point_at_row
    ldy .from
-   cpy .to
    bcs +
    lda .erase_char
    sta (zp_a),y
    lda .erase_color
    sta (zp_b),y
    iny
    bne -
+   rts

; X = row
.erase_row:
    lda #0
    sta .from
    lda #.LAST_COL+1
    sta .to
    jmp .erase_span

; Erases rows X to Y (none if X > Y)
.erase_rows:
    sty .last_row
-   cpx .last_row
    beq +
    bcs ++
+   txa
    pha
    jsr .erase_row
    pla
    tax
    inx
    bne -
++  rts

; Moves rows X+1..Y up one row and clears row Y.
.scroll_rows_up:
    stx .row_index
    sty .last_row
-   ldy .row_index
    cpy .last_row
    bcs +
    ldx .row_index
    inx
    jsr .copy_row
    inc .row_index
    jmp -
+   ldx .last_row
    jmp .erase_row

; Moves rows X..Y-1 down one row and clears row X.
.scroll_rows_down:
    stx .first_row
    sty .row_index
-   ldy .row_index
    cpy .first_row
    beq +
    bcc +
    ldx .row_index
    dex
    jsr .copy_row
    dec .row_index
    jmp -
+   ldx .first_row
    jmp .erase_row

; Copies screen and colour row X to row Y.
.copy_row:
    lda screen_row_lo,x
    sta .from_screen+1
    sta .from_color+1
    lda screen_row_hi,x
    sta .from_screen+2
    clc
    adc #COLOR_OFFSET_HI
    sta .from_color+2
    lda screen_row_lo,y
    sta .to_screen+1
    sta .to_color+1
    lda screen_row_hi,y
    sta .to_screen+2
    clc
    adc #COLOR_OFFSET_HI
    sta .to_color+2
    ldy #.LAST_COL
.from_screen:
-   lda $ffff,y
.to_screen:
    sta $ffff,y
.from_color:
    lda $ffff,y
.to_color:
    sta $ffff,y
    dey
    bpl -
    rts

;---------------------------------------------------------
; State
;---------------------------------------------------------

; The cursor position and attributes are saved and restored together
; by ESC 7 / ESC 8, so they must stay together in this order.
ansi_x:   !byte 0
ansi_y:   !byte 0
.fg:      !byte .DEFAULT_FG
.bg:      !byte .NO_BG
.bold:    !byte 0
.reverse: !byte 0
.SAVED_COUNT = * - ansi_x
.saved:   !fill .SAVED_COUNT, 0

.pending_wrap:   !byte 0
.autowrap:       !byte 1
.cursor_enabled: !byte 1
.top:            !byte 0
.bottom:         !byte .LAST_ROW
.shift_out:      !byte 0
.g0_graphics:    !byte 0
.g1_graphics:    !byte 0   ; must follow .g0_graphics

.fg_color:    !byte 0
.draw_color:  !byte 0
.draw_mask:   !byte 0
.erase_char:  !byte " "
.erase_color: !byte 0

.state:       !byte .TEXT
.params:      !fill .MAX_PARAMS, 0
.param_index: !byte 0
.private:     !byte 0

.utf8_needed:  !byte 0
.utf8_too_big: !byte 0
.codepoint:    !word 0

.char:      !byte 0
.digit:     !byte 0
.times2:    !byte 0
.n:         !byte 0
.i:         !byte 0
.limit:     !byte 0
.which:     !byte 0
.from:      !byte 0
.to:        !byte 0
.new_top:   !byte 0
.first_row: !byte 0
.last_row:  !byte 0
.row_index: !byte 0
}

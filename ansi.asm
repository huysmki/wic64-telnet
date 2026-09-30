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
; insert/delete lines and characters, repeat, scroll regions, SGR
; colours (8 + 8 bright, bold, reverse; 256 and true colours shown as
; the nearest of the 16), save/restore cursor, cursor position and
; device attribute reports, DEC line drawing, the alternate screen,
; application cursor keys, autowrap and cursor visibility modes.
; Unknown sequences are parsed and ignored, strings (OSC, DCS, APC,
; PM, SOS) are skipped.
;
; The C64 has a single background colour, so a coloured ANSI
; background is shown as reverse video in that colour. Blink shows as
; a bright background instead (iCE colours, as PC BBS art expects).
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
.STRING   = 3   ; OSC, DCS, APC, PM or SOS: skipped up to BEL or ST
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
    sta .alternate
    sta ansi_app_cursor
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

; A = screen code to print. Printable characters end any sequence,
; except a string, which is skipped whole (e.g. a UTF-8 window title).
.glyph:
    ldx .state
    cpx #.STRING
    beq .ignore
    ldx #.TEXT
    stx .state
    jmp .put

; A = byte below $80: text, control code or part of a sequence
.ascii:
    ldx .state
    beq .text
    cpx #.STRING
    bne +
    jmp .skip_string
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

.skip_string:
    ; skipped up to BEL or ESC (the start of the ST terminator ESC \)
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
    sta .params_dropped
    sta .colon_mask
    ldx #.MAX_PARAMS-1
-   sta .params,x
    sta .params_hi,x
    dex
    bpl -
    rts
+   ldx #.STRING_COUNT-1
-   cmp .string_starts,x
    beq .start_string
    dex
    bpl -
    cmp #"("
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
.start_string:
    lda #.STRING
    sta .state
    rts

.STRING_COUNT = 5
.string_starts: !byte "]", "P", "X", "^", "_"    ; OSC DCS SOS PM APC

.csi:
    cmp #"0"
    bcc .csi_not_digit
    cmp #$3a                ; after 9
    bcs .csi_not_digit
    ldx .params_dropped     ; beyond .MAX_PARAMS
    bne .saturate_done
    ; params[i] = params[i] * 10 + digit (16 bits, for DEC modes such
    ; as 1049), saturating from 6400 on; handlers see them cut to 255
    and #$0f
    sta .digit
    ldx .param_index
    lda .params_hi,x
    cmp #$19
    bcs .saturate
    asl .params,x
    rol .params_hi,x        ; * 2
    lda .params,x
    sta .times2
    lda .params_hi,x
    sta .times2+1
    asl .params,x
    rol .params_hi,x
    asl .params,x
    rol .params_hi,x        ; * 8
    lda .params,x
    clc
    adc .times2
    sta .params,x
    lda .params_hi,x
    adc .times2+1
    sta .params_hi,x
    lda .params,x
    clc
    adc .digit
    sta .params,x
    bcc +
    inc .params_hi,x
+   rts
.saturate:
    lda #$ff
    sta .params,x
    sta .params_hi,x
.saturate_done:
    rts

.csi_not_digit:
    cmp #";"
    beq .next_param
    cmp #":"
    beq .sub_param
    cmp #"<"
    bcc +
    cmp #$40                ; after ?
    bcs +
    lda .private            ; < = > ? mark private sequences
    ora #1
    sta .private
    rts
+   cmp #"@"
    bcs +
    lda .private            ; intermediate bytes: none of the sequences
    ora #$80                ; with them is supported
    sta .private
    rts
+   cmp #$7f
    bcs .csi_ignore
    ldx #.TEXT
    stx .state
    ldx .private
    bne .private_final
    tay
    ldx #.MAX_PARAMS-1
-   lda .params_hi,x
    beq +
    lda #255
    sta .params,x
+   dex
    bpl -
    tya
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
    bcs +
    inc .param_index
    rts
+   lda #1
    sta .params_dropped
.csi_ignore:
    rts

; ":" separates the parts of one parameter (38:2::r:g:b). They are
; stored like separate parameters, marked in .colon_mask.
.sub_param:
    jsr .next_param
    ldx .param_index
    lda .bit_table,x
    ora .colon_mask
    sta .colon_mask
    rts

.private_final:
    bit .private
    bmi .csi_ignore         ; with intermediate bytes
    ldy #1
    cmp #"h"
    beq .dec_mode
    dey
    cmp #"l"
    beq .dec_mode
    rts

; Y = 1 to set, 0 to reset the DEC private modes in the parameters
.dec_mode:
    sty .set_mode
    ldx #0
.next_mode:
    stx .i
    lda .params_hi,x
    beq .small_mode
    cmp #>1049
    bne .mode_done
    lda .params,x
    cmp #<1047
    bne +
    jsr .alternate_screen
    jmp .mode_done
+   cmp #<1049
    bne .mode_done
    jsr .alternate_screen_1049
    jmp .mode_done
.small_mode:
    ldy .set_mode
    lda .params,x
    cmp #1
    bne +
    sty ansi_app_cursor
+   cmp #7
    bne +
    sty .autowrap
+   cmp #25
    bne +
    sty .cursor_enabled
+   cmp #47
    bne .mode_done
    jsr .alternate_screen
.mode_done:
    ldx .i
    inx
    cpx .param_index
    bcc .next_mode
    beq .next_mode
    rts

; 1049 also saves the cursor on the way in and restores it on the way out.
.alternate_screen_1049:
    lda .set_mode
    beq +
    jsr .save_cursor
    jmp .alternate_screen
+   jsr .alternate_screen
    jmp .restore_cursor

; Enters (.set_mode = 1) or leaves the alternate screen, which full-screen
; programs draw on so that the screen before them comes back when they
; exit. Rows 0-23 of the main screen are kept in alt_screen_buffer.
.alternate_screen:
    lda .set_mode
    cmp .alternate
    beq .alternate_done
    sta .alternate
    tax
    beq .leave_alternate
    ldx #0
-   !for .k, 0, 3 {
        lda SCREEN + .k * 240,x
        sta alt_screen_buffer + .k * 240,x
        lda COLOR_RAM + .k * 240,x
        sta alt_screen_buffer + 960 + .k * 240,x
    }
    inx
    cpx #240
    bne -
    ldx #0
    ldy #.LAST_ROW
    jmp .erase_rows
.leave_alternate:
-   !for .k, 0, 3 {
        lda alt_screen_buffer + .k * 240,x
        sta SCREEN + .k * 240,x
        lda alt_screen_buffer + 960 + .k * 240,x
        sta COLOR_RAM + .k * 240,x
    }
    inx
    cpx #240
    bne -
.alternate_done:
    rts

.CSI_COUNT = 29
.csi_finals:
    !byte "A", "B", "C", "D", "E", "F", "G", "`", "H", "f", "d", "e", "a"
    !byte "J", "K", "L", "M", "P", "@", "X", "S", "T", "m", "r", "s", "u", "n", "c"
    !byte "b"
.csi_lo:
    !byte <(.cursor_up-1), <(.cursor_down-1), <(.cursor_right-1), <(.cursor_left-1)
    !byte <(.next_line-1), <(.previous_line-1), <(.column-1), <(.column-1)
    !byte <(.position-1), <(.position-1), <(.row-1), <(.cursor_down-1), <(.cursor_right-1)
    !byte <(.erase_display-1), <(.erase_line-1), <(.insert_lines-1), <(.delete_lines-1)
    !byte <(.delete_chars-1), <(.insert_chars-1), <(.erase_chars-1), <(.scroll_up-1)
    !byte <(.scroll_down-1), <(.sgr-1), <(.set_margins-1), <(.save_cursor-1)
    !byte <(.restore_cursor-1), <(.status_report-1), <(.device_attributes-1)
    !byte <(.repeat-1)
.csi_hi:
    !byte >(.cursor_up-1), >(.cursor_down-1), >(.cursor_right-1), >(.cursor_left-1)
    !byte >(.next_line-1), >(.previous_line-1), >(.column-1), >(.column-1)
    !byte >(.position-1), >(.position-1), >(.row-1), >(.cursor_down-1), >(.cursor_right-1)
    !byte >(.erase_display-1), >(.erase_line-1), >(.insert_lines-1), >(.delete_lines-1)
    !byte >(.delete_chars-1), >(.insert_chars-1), >(.erase_chars-1), >(.scroll_up-1)
    !byte >(.scroll_down-1), >(.sgr-1), >(.set_margins-1), >(.save_cursor-1)
    !byte >(.restore_cursor-1), >(.status_report-1), >(.device_attributes-1)
    !byte >(.repeat-1)

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
    cmp #2                  ; 3 only clears the scrollback, which
    bne .erase_done         ; there is none of
    ldx #0
    ldy #.LAST_ROW
    jsr .erase_rows
    lda term_mode           ; like ANSI.SYS, the cursor goes home in
    cmp #TERM_ANSI          ; ANSI mode (VT100 leaves it in place)
    bne .erase_done
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
    bmi .erase_done
    jmp .erase_rows
.erase_done:
    rts

.erase_line:
    lda .params
    beq .erase_line_right
    cmp #1
    beq .erase_line_left
    cmp #2
    bne .erase_done
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
    jmp .update_colors

; Prints the last printed character again (REP).
.repeat:
    jsr .count
    sta .n
-   lda .char
    jsr .put
    dec .n
    bne -
    rts

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
-   lda .bit_table,x        ; skip what is left of a ":" group
    and .colon_mask
    beq .sgr_next
    inx
    bne -
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
+   cmp #5                  ; blink (slow or fast)
    beq +
    cmp #6
    bne ++
+   lda #1
    sta .blink
    rts
++  cmp #25
    bne +
    lda #0
    sta .blink
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

; 38/48 ; 5 ; n (256 colours) or 38/48 ; 2 ; r ; g ; b (true colour),
; shown as the nearest of the 16 ANSI colours. The ":" forms work too,
; including 38:2:<colour space>:r:g:b.
.extended_color:
    sta .which
    ldx .i
    lda .params,x
    cmp #5
    beq .indexed_color
    cmp #2
    bne .sgr_ignore
    txa                     ; a ":" group of six has a colour space
    clc                     ; before r:g:b
    adc #4
    tay
    inx
    lda .bit_table,y
    and .colon_mask
    beq +
    inx
+   lda .params,x
    sta .red
    lda .params+1,x
    sta .green
    lda .params+2,x
    sta .blue
    inx
    inx
    inx
    stx .i
    jsr .rgb_to_ansi
    jmp .set_extended_color
.indexed_color:
    lda .params+1,x
    inx
    inx
    stx .i
    jsr .color_256_to_ansi
.set_extended_color:
    ldx .which
    cpx #38
    bne +
    sta .fg
    rts
+   cmp #0
    bne +
    jmp .no_background
+   sta .bg
    rts

; A = xterm colour 0-255. Returns A = ANSI colour 0-15.
.color_256_to_ansi:
    cmp #16
    bcc .ansi_color_done
    cmp #232
    bcs .grey_256
    sbc #16-1               ; carry is clear: subtracts 16
    ldx #0                  ; 6 x 6 x 6 cube: 36 r + 6 g + b
-   cmp #36
    bcc +
    sbc #36
    inx
    bne -
+   ldy .cube_levels,x
    sty .red
    ldx #0
-   cmp #6
    bcc +
    sbc #6
    inx
    bne -
+   ldy .cube_levels,x
    sty .green
    tax
    lda .cube_levels,x
    sta .blue
    jmp .rgb_to_ansi
.grey_256:
    sbc #232                ; grey ramp: 8 + 10 * (n - 232)
    asl
    sta .times2
    asl
    asl
    adc .times2
    adc #8
    sta .red
    sta .green
    sta .blue

; .red, .green, .blue = 0-255. Returns A = the nearest ANSI colour 0-15:
; a component from 128 on is on, bright if one reaches 200, and a dim
; colour with nothing on is dark grey.
.rgb_to_ansi:
    lda #0
    sta .ansi_bits
    sta .brightest
    ldx #2
-   lda .red,x
    cmp .brightest
    bcc +
    sta .brightest
+   cmp #128
    rol .ansi_bits          ; ends with red in bit 0, blue in bit 2
    dex
    bpl -
    lda .brightest
    cmp #200
    lda .ansi_bits
    bcc +
    ora #8
    rts
+   bne .ansi_color_done
    ldx .brightest
    cpx #64
    bcc .ansi_color_done
    lda #8
.ansi_color_done:
    rts

.cube_levels: !byte 0, 95, 135, 175, 215, 255

.reset_attributes:
    lda #.DEFAULT_FG
    sta .fg
    lda #0
    sta .bold
    sta .reverse
    sta .blink
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
    lda .blink
    beq +
    lda .bg                 ; blink: the bright version of the background
    bpl ++
    lda #0
++  ora #8
    bne .with_background
+   lda .bg
    bpl .with_background

    lda #" "
    sta .erase_char
    lda .fg_color
    sta .erase_color
    sta .draw_color
    sta .block_color
    lda .reverse
    beq +
    lda #$80
+   sta .draw_mask
    eor #SC_FULL_BLOCK
    sta .block_char
    rts

; A reversed full block would show the black screen background, so a
; full block on a background is drawn unreversed in the colour it shows.
.with_background:
    tax
    lda ansi_palette,x
    sta .erase_color
    lda #$a0
    sta .erase_char
    sta .block_char
    lda #$80
    sta .draw_mask
    lda .reverse
    beq +
    lda .fg_color
    sta .draw_color
    lda .erase_color
    sta .block_color
    rts
+   lda .erase_color
    sta .draw_color
    lda .fg_color
    sta .block_color
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
    cmp #SC_FULL_BLOCK
    beq .put_block
    eor .draw_mask
    sta (zp_a),y
    lda .draw_color
.put_color:
    sta (zp_b),y
    cpy #.LAST_COL
    bcs +
    inc ansi_x
    rts
+   lda #1
    sta .pending_wrap
    rts
.put_block:
    lda .block_char
    sta (zp_a),y
    lda .block_color
    jmp .put_color

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
    lda #0
    sta .pending_wrap
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

; ESC 7 / ESC 8 save and restore everything from ansi_x up to
; .SAVED_COUNT together (cursor, attributes, wrap state, character sets)
ansi_x:          !byte 0
ansi_y:          !byte 0
.fg:             !byte .DEFAULT_FG
.bg:             !byte .NO_BG
.bold:           !byte 0
.reverse:        !byte 0
.blink:          !byte 0
.pending_wrap:   !byte 0
.shift_out:      !byte 0
.g0_graphics:    !byte 0
.g1_graphics:    !byte 0   ; must follow .g0_graphics
.SAVED_COUNT = * - ansi_x
.saved:          !fill .SAVED_COUNT, 0

; 1 when the server asked for application cursor keys (ESC O A)
ansi_app_cursor: !byte 0

.autowrap:       !byte 1
.cursor_enabled: !byte 1
.alternate:      !byte 0
.top:            !byte 0
.bottom:         !byte .LAST_ROW

.fg_color:    !byte 0
.draw_color:  !byte 0
.draw_mask:   !byte 0
.erase_char:  !byte " "
.erase_color: !byte 0
.block_char:  !byte SC_FULL_BLOCK
.block_color: !byte 0

.state:       !byte .TEXT
.params:      !fill .MAX_PARAMS, 0
.params_hi:   !fill .MAX_PARAMS, 0
.param_index: !byte 0
.params_dropped: !byte 0
.colon_mask:  !byte 0      ; bit i: parameter i followed a ":"
.private:     !byte 0      ; 1: private marker, $80: intermediate bytes
.set_mode:    !byte 0

; bit i for parameter i; beyond .MAX_PARAMS there are no parameters
.bit_table:   !byte $01, $02, $04, $08, $10, $20, $40, $80
              !fill 8, 0

.utf8_needed:  !byte 0
.utf8_too_big: !byte 0
.codepoint:    !word 0

.char:      !byte 0
.digit:     !byte 0
.times2:    !word 0
.n:         !byte 0
.i:         !byte 0
.limit:     !byte 0
.which:     !byte 0
.red:       !byte 0         ; .red, .green, .blue in this order
.green:     !byte 0
.blue:      !byte 0
.brightest: !byte 0
.ansi_bits: !byte 0
.from:      !byte 0
.to:        !byte 0
.new_top:   !byte 0
.first_row: !byte 0
.last_row:  !byte 0
.row_index: !byte 0
}

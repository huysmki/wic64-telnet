;---------------------------------------------------------
; Terminal
;
; Turns what the server sends into screen output and keystrokes into
; bytes for the server, in one of these modes:
;
;   PETSCII  Commodore BBSes: bytes go straight to the KERNAL screen
;            editor, keys are sent as typed. Full 40 x 25 screen.
;            Switches to ANSI by itself when the server draws with ANSI
;            escape codes.
;   ANSI     PC BBSes: ASCII with ANSI/VT100 escape sequences and
;            CP437 line drawing, on 40 x 24 plus a status line.
;   UTF-8    Unix hosts: like ANSI, with UTF-8 characters.
;   ANSI 80, UTF-8 80
;            The same on 80 x 24: the cells are kept in CELLS80 and
;            drawn on a bitmap (screen80.asm) instead of the screen.
;            The rows of cells are found through a table, so that
;            scrolling only reorders the table.
;
; The cursor is drawn by the terminal itself (reverse video) and is
; hidden automatically before anything touches the screen.
;---------------------------------------------------------

!zone term {
TERM_PETSCII = 0
TERM_ANSI    = 1
TERM_UTF8    = 2
TERM_ANSI80  = 3
TERM_UTF8_80 = 4
TERM_MODES   = 5

term_mode:       !byte TERM_PETSCII
term_local_echo: !byte 0
term_rows:       !byte 25
term_columns:    !byte 40
term_utf8:       !byte 0    ; 1 in the UTF-8 modes

; A = mode. Clears the screen and the scrollback and sets them up
; for the mode.
term_start:
    pha
    jsr term_cursor_hide
    jsr s80_stop
    pla
    sta term_mode
    tax
    lda .mode_columns,x
    sta term_columns
    lda .mode_utf8,x
    sta term_utf8
    jsr scrollback_clear
    lda #.NO_ESCAPE
    sta .escape_state
    lda term_mode
    bne .start_ansi

    lda #25
    sta term_rows
    jsr ui_screen_menu
    lda #PET_UNLOCK_CASE    ; BBSes may switch character sets
    jmp CHROUT

.start_ansi:
    lda #24
    sta term_rows
    jsr ui_screen_menu      ; also locks the case switch, which would
    lda #VIC_CUSTOM_CHARSET ; otherwise flip VIC_MEMORY
    sta VIC_MEMORY
    lda term_columns
    cmp #80
    bne +
    lda #>CELLS80
    jsr .number_rows
    jsr s80_start
+   jmp ansi_reset

.mode_columns: !byte 40, 40, 40, 80, 80
.mode_utf8:    !byte 0, 0, 1, 0, 1

; Back to the plain menu screen.
term_stop:
    jsr term_cursor_hide
    jsr s80_stop
    jmp ui_screen_menu

; X = row of the terminal. Points zp_a at its screen codes and zp_b at
; its colours: the screen, or in 80 columns the cells the bitmap is
; drawn from. Preserves X and Y.
term_row_cells:
    lda term_columns
    cmp #80
    beq +
    lda screen_row_lo,x
    sta zp_a
    sta zp_b
    lda screen_row_hi,x
    sta zp_a+1
    clc
    adc #COLOR_OFFSET_HI
    sta zp_b+1
    rts
+   lda term_cells_lo,x
    sta zp_a
    sta zp_b
    lda term_cells_hi,x
    sta zp_a+1
    clc
    adc #>(CELLS80_COLORS - CELLS80)
    sta zp_b+1
    rts

; 80 columns, X = top, Y = bottom row: rows X+1 to Y move up one, row
; X going to the bottom (for the caller to erase).
term_rows_up:
    sty .last_row
    lda term_cells_lo,x
    pha
    lda term_cells_hi,x
    pha
-   cpx .last_row
    bcs +
    lda term_cells_lo+1,x
    sta term_cells_lo,x
    lda term_cells_hi+1,x
    sta term_cells_hi,x
    inx
    bne -
+   pla
    sta term_cells_hi,x
    pla
    sta term_cells_lo,x
    rts

; 80 columns, X = top, Y = bottom row: rows X to Y-1 move down one, row
; Y going to the top (for the caller to erase).
term_rows_down:
    stx .first_row
    lda term_cells_lo,y
    pha
    lda term_cells_hi,y
    pha
-   cpy .first_row
    beq +
    bcc +
    lda term_cells_lo-1,y
    sta term_cells_lo,y
    lda term_cells_hi-1,y
    sta term_cells_hi,y
    dey
    jmp -
+   pla
    sta term_cells_hi,y
    pla
    sta term_cells_lo,y
    rts

; 80 columns: switches to the rows of the alternate screen (A = 1), in
; order, or back to those of the main screen as they were (A = 0).
term_alternate_rows:
    tay
    beq .main_rows
    ldx #23
-   lda term_cells_lo,x
    sta .main_lo,x
    lda term_cells_hi,x
    sta .main_hi,x
    dex
    bpl -
    lda #>ALT_CELLS80
    jmp .number_rows
.main_rows:
    ldx #23
-   lda .main_lo,x
    sta term_cells_lo,x
    lda .main_hi,x
    sta term_cells_hi,x
    dex
    bpl -
    rts

; A = first page of 24 rows of 80 cells (their colours $0800 higher);
; points the table at them in order.
.number_rows:
    sta term_cells_hi
    lda #0
    sta term_cells_lo
    tax
-   lda term_cells_lo,x
    clc
    adc #80
    sta term_cells_lo+1,x
    lda term_cells_hi,x
    adc #0
    sta term_cells_hi+1,x
    inx
    cpx #23
    bcc -
    rts

term_cells_lo:  !fill 24, 0     ; where the cells of each row are
term_cells_hi:  !fill 24, 0
.main_lo:   !fill 24, 0     ; those of the main screen meanwhile
.main_hi:   !fill 24, 0
.first_row: !byte 0
.last_row:  !byte 0

; Displays the byte from the server in A.
term_output:
    pha
    jsr term_cursor_hide
    pla
    ldx term_mode
    beq .petscii_output
    ldx term_utf8
    bne +
    jmp ansi_output_cp437
+   jmp ansi_output_utf8

; In PETSCII mode ANSI escape sequences (ESC [ ... final) are collected
; rather than printed. One that draws something means the server speaks
; ANSI, so the terminal switches to ANSI and replays it. Queries such as
; ESC [ 5 n, which BBSes send to detect ANSI terminals, are dropped
; unanswered like a real C64 terminal would, so the BBS stays in PETSCII.
.petscii_output:
    ldx .escape_state
    bne .in_escape
.petscii_char:
    cmp #$1b
    bne +
    lda #.AFTER_ESC
    sta .escape_state
    rts
+   cmp #$07
    bne +
    jmp ui_bell
+   jsr .keep_scrolled_rows
    jsr CHROUT
    lda #0                  ; a stray quote must not turn the following
    sta QUOTE_MODE          ; control codes into visible characters
    sta INSERT_COUNT
    rts

; Before a byte that makes the screen editor clear the screen or
; scroll it, puts what will disappear into the scrollback: the top
; logical line, which is one or two rows. The screen scrolls when the
; cursor is on the bottom row and the byte moves it to the next row:
; RETURN, cursor down, or anything that advances the cursor from the
; last column. Preserves A.
.keep_scrolled_rows:
    sta .byte
    cmp #PET_CLR
    bne +
    jsr scrollback_add_screen
    jmp .kept
+   ldx CURSOR_ROW
    cpx #24
    bne .kept
    cmp #$0d
    beq .keep_top_line
    cmp #$8d
    beq .keep_top_line
    cmp #KEY_DOWN
    beq .keep_top_line
    cmp #KEY_RIGHT
    beq +
    and #$7f                ; printable: $20-$7f and $a0-$ff
    cmp #$20
    bcc .kept
+   lda CURSOR_COL
    cmp #39
    beq .keep_top_line
    cmp #79
    bne .kept
.keep_top_line:
    ldx #0
    jsr scrollback_add_row
    lda LINE_LINKS+1
    bmi .kept               ; row 1 starts the next logical line
    ldx #1
    jsr scrollback_add_row
.kept:
    lda .byte
    rts

.in_escape:
    cpx #.IN_CSI
    beq .in_csi
    cmp #"["
    bne .not_csi
    lda #.IN_CSI
    sta .escape_state
    lda #0
    sta .csi_length
    rts

.in_csi:
    cmp #$20
    bcc .not_csi
    cmp #$40
    bcs .csi_final
    ldx .csi_length         ; parameter or intermediate byte
    cpx #.CSI_MAX
    bcs .not_csi
    sta .csi_bytes,x
    inc .csi_length
    rts

.csi_final:
    cmp #$7f
    bcs .not_csi
    ldx #.NO_ESCAPE
    stx .escape_state
    ldx #.DRAWING_COUNT-1
-   cmp .drawing_finals,x
    beq .switch_to_ansi
    dex
    bpl -
    rts

; Not a CSI sequence after all: drop what was collected and handle
; this byte normally (it may start a new sequence).
.not_csi:
    ldx #.NO_ESCAPE
    stx .escape_state
    jmp .petscii_char

.switch_to_ansi:
    sta .csi_final_byte
    lda #TERM_ANSI
    jsr term_start
    jsr telnet_window_changed
    lda #$1b
    jsr ansi_output_cp437
    lda #"["
    jsr ansi_output_cp437
    ldx #0
-   cpx .csi_length
    beq +
    stx .replay_index
    lda .csi_bytes,x
    jsr ansi_output_cp437
    ldx .replay_index
    inx
    bne -
+   lda .csi_final_byte
    jmp ansi_output_cp437

.NO_ESCAPE = 0
.AFTER_ESC = 1
.IN_CSI    = 2
.CSI_MAX   = 16
.DRAWING_COUNT = 10
.drawing_finals: !byte "m", "H", "f", "J", "K", "A", "B", "C", "D", "G"

; Sends the key in A (as returned by GETIN) to the server, echoing it
; locally if local echo is on.
term_key:
    ldx term_mode
    bne .ansi_key
    jsr telnet_send
    ldx term_local_echo
    beq +
    jmp term_output
+   rts

.ansi_key:
    cmp #KEY_RETURN
    bne +
    jsr telnet_send_newline
    lda term_local_echo
    beq .key_done
    lda #$0d
    jsr term_output
    lda #$0a
    jmp term_output

+   cmp #$20
    bcs .not_control
    tax
    lda KEY_MODIFIERS       ; CTRL+key goes out as an ASCII control code,
    and #$04                ; everything else as ANSI
    beq +
    txa
    jmp .emit
+   txa
.not_control:
    ldx #.CURSOR_KEY_COUNT-1
-   cmp .cursor_keys,x
    beq .cursor_key
    dex
    bpl -
    jsr petscii_key_to_ascii
    beq .key_done
    jmp .emit

.cursor_key:
    lda .cursor_finals,x
    sta .final
    lda #$1b
    jsr .emit
    lda #"["
    ldx ansi_app_cursor
    beq +
    lda #"O"                ; application cursor keys
+   jsr .emit
    lda .final

; Sends A to the server and echoes it if local echo is on.
.emit:
    pha
    jsr telnet_send
    pla
    ldx term_local_echo
    beq .key_done
    jmp term_output
.key_done:
    rts

.CURSOR_KEY_COUNT = 6
.cursor_keys:   !byte KEY_UP, KEY_DOWN, KEY_RIGHT, KEY_LEFT, KEY_HOME, KEY_CLR
.cursor_finals: !byte "A",    "B",      "C",       "D",      "H",      "F"

; Returns A/Y = the terminal type reported to the server (ASCII).
term_type_name:
    lda term_mode
    bne +
    lda #<.petscii_type
    ldy #>.petscii_type
    rts
+   lda #<.ansi_type
    ldy #>.ansi_type
    rts

.petscii_type: !text "PETSCII", 0
.ansi_type:    !text "ANSI", 0

; A = mode. Returns A/Y = its display name (PETSCII).
term_mode_name:
    tax
    lda .mode_names_lo,x
    ldy .mode_names_hi,x
    rts

.mode_names_lo: !byte <.name_petscii, <.name_ansi, <.name_utf8
                !byte <.name_ansi80, <.name_utf8_80
.mode_names_hi: !byte >.name_petscii, >.name_ansi, >.name_utf8
                !byte >.name_ansi80, >.name_utf8_80
.name_petscii: !pet "PETSCII", 0
.name_ansi:    !pet "ANSI", 0
.name_utf8:    !pet "UTF-8", 0
.name_ansi80:  !pet "ANSI 80", 0
.name_utf8_80: !pet "UTF-8 80", 0

;---------------------------------------------------------
; Cursor
;---------------------------------------------------------

term_cursor_show:
    lda .cursor_visible
    bne .cursor_done
    lda term_mode
    bne .ansi_cursor

    lda LINE_PTR
    clc
    adc CURSOR_COL
    tax
    lda LINE_PTR+1
    adc #0
    tay
    lda CURSOR_COLOR
    jmp .draw_cursor

.ansi_cursor:
    lda term_columns
    cmp #80
    beq .cursor80
    jsr ansi_cursor_cell
    bcs .cursor_done

; X/Y = screen address, A = colour
.draw_cursor:
    sta .cursor_color
    stx .read_char+1
    stx .write_char+1
    stx .read_color+1
    stx .write_color+1
    sty .read_char+2
    sty .write_char+2
    tya
    clc
    adc #COLOR_OFFSET_HI
    sta .read_color+2
    sta .write_color+2
.read_char:
    lda $ffff
    sta .saved_char
    eor #$80
    jsr .write_char
.read_color:
    lda $ffff
    sta .saved_color
    lda .cursor_color
    jsr .write_color
    lda #.ON_SCREEN
    sta .cursor_visible
.cursor_done:
    rts

; In 80 columns the bitmap is first brought up to date. The cursor's
; block is drawn with the character under the cursor reversed; to
; hide it, the cell only counts as changed, to be drawn as it is with
; the next update of the bitmap.
.cursor80:
    jsr s80_flush
    lda ansi_cursor_enabled
    beq .cursor_done
    ldx ansi_y
    stx .cursor_row
    jsr term_row_cells
    lda ansi_x
    sta .cursor_column
    jsr s80_draw_cursor
    lda #.ON_BITMAP
    sta .cursor_visible
    rts

term_cursor_hide:
    lda .cursor_visible
    beq .cursor_done
    cmp #.ON_BITMAP
    bne +
    ldx .cursor_row
    lda .cursor_column
    tay
    iny
    jsr s80_touch
    lda #0
    sta .cursor_visible
    rts
+   lda .saved_char
    jsr .write_char
    lda .saved_color
    jsr .write_color
    lda #0
    sta .cursor_visible
    rts

; Patched by .draw_cursor to point at the cursor cell
.write_char:
    sta $ffff
    rts
.write_color:
    sta $ffff
    rts

.escape_state:   !byte .NO_ESCAPE
.csi_length:     !byte 0
.csi_bytes:      !fill .CSI_MAX, 0
.csi_final_byte: !byte 0
.replay_index:   !byte 0
.byte:           !byte 0
.ON_SCREEN = 1
.ON_BITMAP = 2
.cursor_visible: !byte 0    ; 0, .ON_SCREEN or .ON_BITMAP
.cursor_row:     !byte 0
.cursor_column:  !byte 0
.cursor_color:   !byte 0
.saved_char:     !byte 0
.saved_color:    !byte 0
.final:          !byte 0
}

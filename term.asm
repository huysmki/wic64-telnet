;---------------------------------------------------------
; Terminal
;
; Turns what the server sends into screen output and keystrokes into
; bytes for the server, in one of three modes:
;
;   PETSCII  Commodore BBSes: bytes go straight to the KERNAL screen
;            editor, keys are sent as typed. Full 40 x 25 screen.
;            Switches to ANSI by itself when the server draws with ANSI
;            escape codes.
;   ANSI     PC BBSes: ASCII with ANSI/VT100 escape sequences and
;            CP437 line drawing, on 40 x 24 plus a status line.
;   UTF-8    Unix hosts: like ANSI, with UTF-8 characters.
;
; The cursor is drawn by the terminal itself (reverse video) and is
; hidden automatically before anything touches the screen.
;---------------------------------------------------------

!zone term {
TERM_PETSCII = 0
TERM_ANSI    = 1
TERM_UTF8    = 2
TERM_MODES   = 3

term_mode:       !byte TERM_PETSCII
term_local_echo: !byte 0
term_rows:       !byte 25

; A = mode. Clears the screen and sets it up for the mode.
term_start:
    sta term_mode
    jsr term_cursor_hide
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
    jmp ansi_reset

; Back to the plain menu screen.
term_stop:
    jsr term_cursor_hide
    jmp ui_screen_menu

; Displays the byte from the server in A.
term_output:
    pha
    jsr term_cursor_hide
    pla
    ldx term_mode
    beq .petscii_output
    dex
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
+   jsr CHROUT
    lda #0                  ; a stray quote must not turn the following
    sta QUOTE_MODE          ; control codes into visible characters
    sta INSERT_COUNT
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
.mode_names_hi: !byte >.name_petscii, >.name_ansi, >.name_utf8
.name_petscii: !pet "PETSCII", 0
.name_ansi:    !pet "ANSI", 0
.name_utf8:    !pet "UTF-8", 0

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
    lda #1
    sta .cursor_visible
.cursor_done:
    rts

term_cursor_hide:
    lda .cursor_visible
    beq .cursor_done
    lda .saved_char
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
.cursor_visible: !byte 0
.cursor_color:   !byte 0
.saved_char:     !byte 0
.saved_color:    !byte 0
.final:          !byte 0
}

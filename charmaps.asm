;---------------------------------------------------------
; Character set and translation tables for the ANSI modes
;
; The ANSI modes use a copy of the ROM lower/upper case set at
; CHARSET with the ASCII characters the C64 lacks drawn into slots
; that are not otherwise used. Server characters become screen codes
; for that set; line drawing and block characters map onto the C64's
; own graphics characters, anything else onto a close ASCII match.
;---------------------------------------------------------

; Screen codes in CHARSET
SC_HLINE       = $40   ; ─
SC_VLINE       = $5d   ; │
SC_CROSS       = $5b   ; ┼
SC_DOWN_RIGHT  = $70   ; ┌
SC_DOWN_LEFT   = $6e   ; ┐
SC_UP_RIGHT    = $6d   ; └
SC_UP_LEFT     = $7d   ; ┘
SC_VERT_RIGHT  = $6b   ; ├
SC_VERT_LEFT   = $73   ; ┤
SC_DOWN_HORIZ  = $72   ; ┬
SC_UP_HORIZ    = $71   ; ┴
SC_FULL_BLOCK  = $a0
SC_LOWER_HALF  = $62
SC_UPPER_HALF  = $e2
SC_LEFT_HALF   = $61
SC_RIGHT_HALF  = $e1
SC_SHADE       = $66
SC_DARK_SHADE  = $e6

; Slots that receive the missing ASCII characters
SC_BACKSLASH   = $1c   ; was £
SC_CARET       = $1e   ; was ↑
SC_UNDERSCORE  = $1f   ; was ←
SC_BACKTICK    = $6a
SC_LEFT_BRACE  = $74
SC_PIPE        = $75
SC_RIGHT_BRACE = $76
SC_TILDE       = $7a

!zone charset_init {
CHARGEN_LOWER = $d800   ; ROM lower/upper case set with the ROM banked in

; Builds CHARSET: copies the ROM set and draws the extra characters.
charset_init:
    sei
    lda $01
    pha
    lda #$33                ; character ROM visible at $d000
    sta $01
    ldx #0
.copy:
    !for .page, 0, 7 {
        lda CHARGEN_LOWER + .page * $100,x
        sta CHARSET + .page * $100,x
    }
    inx
    bne .copy
    pla
    sta $01
    cli

    ldy #0
.next_glyph:
    lda .glyphs,y
    beq .done
    ; target = CHARSET + slot * 8
    sta zp_a
    lda #0
    asl zp_a
    rol
    asl zp_a
    rol
    asl zp_a
    rol
    adc #>CHARSET
    sta zp_a+1
    iny
    ldx #0
-   lda .glyphs,y
    sta .row,x
    iny
    inx
    cpx #8
    bne -
    sty .index
    ldy #7
-   lda .row,y
    sta (zp_a),y
    dey
    bpl -
    ldy .index
    jmp .next_glyph
.done:
    rts

.index: !byte 0
.row:   !fill 8, 0

; slot, then 8 rows of pixels; 0 ends the list
.glyphs:
    !byte SC_BACKSLASH,   $00, $60, $30, $18, $0c, $06, $03, $00
    !byte SC_CARET,       $18, $3c, $66, $00, $00, $00, $00, $00
    !byte SC_UNDERSCORE,  $00, $00, $00, $00, $00, $00, $00, $ff
    !byte SC_BACKTICK,    $30, $18, $0c, $00, $00, $00, $00, $00
    !byte SC_LEFT_BRACE,  $0e, $18, $18, $70, $18, $18, $0e, $00
    !byte SC_PIPE,        $18, $18, $18, $18, $18, $18, $18, $00
    !byte SC_RIGHT_BRACE, $70, $18, $18, $0e, $18, $18, $70, $00
    !byte SC_TILDE,       $00, $00, $3b, $6e, $00, $00, $00, $00
    !byte 0
}

!zone ascii_to_screen {
; Converts printable ASCII in A ($20-$7e) to a CHARSET screen code.
ascii_to_screen:
    cmp #$40
    bcc .same               ; space, digits, punctuation
    beq .at
    cmp #$5b
    bcc .same               ; A-Z
    cmp #$60
    bcc .low_bits           ; [ \ ] ^ _ -> $1b-$1f
    beq .backtick
    cmp #$7b
    bcc .low_bits           ; a-z -> $01-$1a
    tax
    lda .braces-$7b,x
.same:
    rts
.at:
    lda #0
    rts
.low_bits:
    and #$1f
    rts
.backtick:
    lda #SC_BACKTICK
    rts

.braces: !byte SC_LEFT_BRACE, SC_PIPE, SC_RIGHT_BRACE, SC_TILDE
}

; ANSI colour 0-15 (8 normal, 8 bright) -> C64 colour
ansi_palette:
    ;     black red  green yellow blue magenta cyan white
    !byte $00,  $02, $05,  $08,   $06, $04,    $03, $0f
    !byte $0b,  $0a, $0d,  $07,   $0e, $04,    $03, $01

; CP437 $80-$ff -> screen code
cp437_to_screen:
    !scr "CueaaaacEeeiiiAA"                 ; $80 Çüéâäàåçêëèïîì ÄÅ
    !scr "EaAooouuyOUcLYPf"                 ; $90 ÉæÆôöòûùÿÖÜ¢£¥₧ƒ
    !scr "aiounNao?--??!<>"                 ; $a0 áíóúñÑªº¿⌐¬½¼¡«»
    ; $b0 ░▒▓│┤╡╢╖╕╣║╗╝╜╛┐
    !byte SC_SHADE, SC_SHADE, SC_DARK_SHADE, SC_VLINE, SC_VERT_LEFT, SC_VERT_LEFT
    !byte SC_VERT_LEFT, SC_DOWN_LEFT, SC_DOWN_LEFT, SC_VERT_LEFT, SC_VLINE
    !byte SC_DOWN_LEFT, SC_UP_LEFT, SC_UP_LEFT, SC_UP_LEFT, SC_DOWN_LEFT
    ; $c0 └┴┬├─┼╞╟╚╔╩╦╠═╬╧
    !byte SC_UP_RIGHT, SC_UP_HORIZ, SC_DOWN_HORIZ, SC_VERT_RIGHT, SC_HLINE
    !byte SC_CROSS, SC_VERT_RIGHT, SC_VERT_RIGHT, SC_UP_RIGHT, SC_DOWN_RIGHT
    !byte SC_UP_HORIZ, SC_DOWN_HORIZ, SC_VERT_RIGHT, SC_HLINE, SC_CROSS
    !byte SC_UP_HORIZ
    ; $d0 ╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀
    !byte SC_UP_HORIZ, SC_DOWN_HORIZ, SC_DOWN_HORIZ, SC_UP_RIGHT, SC_UP_RIGHT
    !byte SC_DOWN_RIGHT, SC_DOWN_RIGHT, SC_CROSS, SC_CROSS, SC_UP_LEFT
    !byte SC_DOWN_RIGHT, SC_FULL_BLOCK, SC_LOWER_HALF, SC_LEFT_HALF
    !byte SC_RIGHT_HALF, SC_UPPER_HALF
    !scr "abGpSsutOOOdoone"                 ; $e0 αßΓπΣσµτΦΘΩδ∞φε∩
    ; $f0 ≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ and no-break space
    !scr "=+><"
    !byte SC_PIPE, SC_PIPE
    !scr "/"
    !byte SC_TILDE
    !scr "o..vn2"
    !byte SC_FULL_BLOCK
    !scr " "

; U+2500-U+259F -> screen code
box_to_screen:
    ; U+2500 ─━│┃ and dashed lines ┄┅┆┇┈┉┊┋
    !byte SC_HLINE, SC_HLINE, SC_VLINE, SC_VLINE, SC_HLINE, SC_HLINE
    !byte SC_VLINE, SC_VLINE, SC_HLINE, SC_HLINE, SC_VLINE, SC_VLINE
    !fill 4, SC_DOWN_RIGHT      ; U+250C ┌ (light/heavy variants)
    !fill 4, SC_DOWN_LEFT       ; U+2510 ┐
    !fill 4, SC_UP_RIGHT        ; U+2514 └
    !fill 4, SC_UP_LEFT         ; U+2518 ┘
    !fill 8, SC_VERT_RIGHT      ; U+251C ├
    !fill 8, SC_VERT_LEFT       ; U+2524 ┤
    !fill 8, SC_DOWN_HORIZ      ; U+252C ┬
    !fill 8, SC_UP_HORIZ        ; U+2534 ┴
    !fill 16, SC_CROSS          ; U+253C ┼
    !byte SC_HLINE, SC_HLINE, SC_VLINE, SC_VLINE    ; U+254C ╌╍╎╏
    !byte SC_HLINE, SC_VLINE    ; U+2550 ═║
    !fill 3, SC_DOWN_RIGHT      ; U+2552 ╒╓╔
    !fill 3, SC_DOWN_LEFT       ; U+2555 ╕╖╗
    !fill 3, SC_UP_RIGHT        ; U+2558 ╘╙╚
    !fill 3, SC_UP_LEFT         ; U+255B ╛╜╝
    !fill 3, SC_VERT_RIGHT      ; U+255E ╞╟╠
    !fill 3, SC_VERT_LEFT       ; U+2561 ╡╢╣
    !fill 3, SC_DOWN_HORIZ      ; U+2564 ╤╥╦
    !fill 3, SC_UP_HORIZ        ; U+2567 ╧╨╩
    !fill 3, SC_CROSS           ; U+256A ╪╫╬
    ; U+256D ╭╮╯╰╱╲╳
    !byte SC_DOWN_RIGHT, SC_DOWN_LEFT, SC_UP_LEFT, SC_UP_RIGHT
    !byte $2f, SC_BACKSLASH, $58
    ; U+2574 half lines ╴╵╶╷╸╹╺╻╼╽╾╿
    !byte SC_HLINE, SC_VLINE, SC_HLINE, SC_VLINE, SC_HLINE, SC_VLINE
    !byte SC_HLINE, SC_VLINE, SC_HLINE, SC_VLINE, SC_HLINE, SC_VLINE
    ; U+2580 ▀▁▂▃▄▅▆▇█▉▊▋▌▍▎▏
    !byte SC_UPPER_HALF, $64, $6f, $79, SC_LOWER_HALF, $f8, $f7, $e3
    !byte SC_FULL_BLOCK, SC_FULL_BLOCK, SC_FULL_BLOCK, SC_LEFT_HALF
    !byte SC_LEFT_HALF, SC_LEFT_HALF, $65, $65
    ; U+2590 ▐░▒▓▔▕▖▗▘▙▚▛▜▝▞▟
    !byte SC_RIGHT_HALF, SC_SHADE, SC_SHADE, SC_DARK_SHADE, $63, $67, $7b, $6c
    !byte $7e, $fc, $7f, $ec, $fb, $7c, $ff, $fe
box_to_screen_end:
!if box_to_screen_end - box_to_screen != $a0 {
    !error "box_to_screen must cover U+2500-U+259F"
}

; U+00A0-U+00FF -> nearest ASCII
latin1_to_ascii:
    !text " !cL*Y|S", $22, "ca<--r-"         ; $a0
    !text "o+23", $27, "uP.,1o>????"         ; $b0
    !text "AAAAAAACEEEEIIII"                 ; $c0
    !text "DNOOOOOxOUUUUYPs"                 ; $d0
    !text "aaaaaaaceeeeiiii"                 ; $e0
    !text "dnooooo/ouuuuypy"                 ; $f0

; Other code points worth showing: high byte, low byte, screen code;
; high byte 0 ends the table
misc_codepoints:
    !byte $20, $10, $2d,  $20, $11, $2d,  $20, $12, $2d   ; hyphens and dashes
    !byte $20, $13, $2d,  $20, $14, $2d,  $20, $15, $2d
    !byte $20, $18, $27,  $20, $19, $27,  $20, $1a, $2c   ; quotes
    !byte $20, $1c, $22,  $20, $1d, $22,  $20, $1e, $22
    !byte $20, $22, $2a,  $20, $26, $2e                   ; • …
    !byte $20, $32, $27,  $20, $33, $22                   ; ′ ″
    !byte $20, $39, $3c,  $20, $3a, $3e                   ; ‹ ›
    !byte $20, $ac, $45                                   ; €
    !byte $21, $22, $54                                   ; ™
    !byte $21, $90, $3c,  $21, $91, SC_CARET              ; arrows
    !byte $21, $92, $3e,  $21, $93, $16
    !byte $22, $12, $2d,  $22, $1a, $16                   ; − √
    !byte $22, $48, SC_TILDE                              ; ≈
    !byte $22, $64, $3c,  $22, $65, $3e                   ; ≤ ≥
    !byte $25, $a0, SC_FULL_BLOCK,  $25, $aa, SC_FULL_BLOCK   ; ■ ▪
    !byte $25, $b2, SC_CARET,  $25, $b6, $3e              ; ▲ ▶
    !byte $25, $ba, $3e,  $25, $bc, $16                   ; ► ▼
    !byte $25, $c0, $3c,  $25, $c4, $3c                   ; ◀ ◄
    !byte $25, $c6, $2a,  $25, $cb, $0f,  $25, $cf, $2a   ; ◆ ○ ●
    !byte 0

; DEC special graphics, ASCII $60-$7e -> screen code
dec_graphics_to_screen:
    !byte $2a, SC_SHADE, $2e, $2e, $2e, $2e, $0f, $2b    ; ◆▒␉␌␍␊°±
    !byte $2e, $2e, SC_UP_LEFT, SC_DOWN_LEFT            ; ␤␋┘┐
    !byte SC_DOWN_RIGHT, SC_UP_RIGHT, SC_CROSS          ; ┌└┼
    !byte $63, SC_HLINE, SC_HLINE, SC_HLINE, $64        ; ⎺⎻─⎼⎽
    !byte SC_VERT_RIGHT, SC_VERT_LEFT, SC_UP_HORIZ      ; ├┤┴
    !byte SC_DOWN_HORIZ, SC_VLINE                       ; ┬│
    !byte $3c, $3e, $10, $3d, $4c, $2e                  ; ≤≥π≠£·

!zone petscii_key_to_ascii {
; Converts a key from GETIN to ASCII for the ANSI modes. Keys without
; an ASCII meaning return A = 0 (Z=1). Besides the obvious ones:
;   £ \   shift+£ |   ↑ ^   shift+↑ ~   ← ESC   shift+- _
;   shift+@ `   shift+* {   shift++ }   DEL = ASCII DEL
petscii_key_to_ascii:
    cmp #KEY_DEL
    beq .delete
    cmp #$20
    bcc .none
    cmp #$41
    bcc .same               ; space, digits, punctuation, @
    cmp #$5b
    bcc .to_lower           ; letters
    cmp #$5f
    bcc .same               ; [ £ ] ↑ are [ \ ] ^ in ASCII
    beq .escape             ; ←
    cmp #$61
    bcc .special
    cmp #$7b
    bcc .to_upper
    cmp #$c1
    bcc .special
    cmp #$db
    bcc .to_upper           ; shifted letters
.special:
    ldx #.SPECIAL_COUNT-1
-   cmp .special_keys,x
    beq +
    dex
    bpl -
.none:
    lda #0
    rts
+   lda .special_ascii,x
.same:
    rts
.to_lower:
    ora #$20
    rts
.to_upper:
    and #$5f
    rts
.escape:
    lda #$1b
    rts
.delete:
    lda #$7f
    rts

.SPECIAL_COUNT = 7
.special_keys:  !byte $a9, $dd, $de, $ff, $ba, $c0, $db
.special_ascii: !byte "|", "_", "~", "~", "`", "{", "}"
}

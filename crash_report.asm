;---------------------------------------------------------
; The crash report itself (see crash.asm)
;
; Runs at CRASH_REPORT, in the RAM under the I/O area, with all RAM
; switched in ($01 = $34), so it reads the receive buffer under the
; BASIC ROM and the code at PC as RAM. crash.asm has put the screen in
; text mode, cleared it and recorded the registers.
;---------------------------------------------------------

!zone crash_report {
.NMI_RAM_VECTOR = $fffa

    lda #<crash_ignore      ; another NMI meanwhile, with the RAM's
    sta .NMI_RAM_VECTOR     ; vectors in: no effect
    lda #>crash_ignore
    sta .NMI_RAM_VECTOR+1

    ldx crash_s             ; above crash.asm's two bytes: P, PC
    lda $0102,x
    sta .a
    lda crash_x
    sta .x
    lda crash_y
    sta .y
    lda crash_memory
    sta .memory
    txa
    clc
    adc #5
    sta .s
    lda $0104,x
    ldy $0105,x
    cmp #<s80_nmi_return    ; through the 80 columns' entry for while
    bne +                   ; the KERNAL ROM is off: what it pushed
    cpy #>s80_nmi_return    ; (P, .back, $01, A) comes first
    bne +
    lda $0106,x
    sta .memory
    lda $0107,x
    sta .a
    txa
    clc
    adc #10
    sta .s
    inx
    inx
    inx
    inx
    inx
    lda $0104,x
    ldy $0105,x
+   sta .pc
    sty .pc+1
    lda $0103,x
    sta .p

    ldx #0
    jsr .row
    ldx #.TITLE
    jsr .label
    ldx #2
    jsr .row
    ldx #.REGISTERS
    jsr .label
    ldx #3
    jsr .row
    lda .pc+1
    jsr .hex_digits
    lda .pc
    jsr .hex
    ldx #0
-   lda .a,x                ; A, X, Y, P, S, $01
    stx .count
    jsr .hex
    ldx .count
    inx
    cpx #6
    bne -

    ldx #4                  ; the code at PC (in RAM)
    jsr .row
    ldx #.CODE
    jsr .label
    lda .pc
    ldx .pc+1
    jsr .point
    jsr .dump

    ldx #6
    jsr .row
    ldx #.STACK
    jsr .label
    ldx .s
    inx
    txa
    ldx #$01
    jsr .point
    lda #7
    jsr .dump_rows

    ldx #12
    jsr .row
    ldx #.RX
    jsr .label
    lda receive_next+1
    jsr .hex_digits
    lda receive_next
    jsr .hex
    ldx #.END
    jsr .label
    lda receive_end+1
    jsr .hex_digits
    lda receive_end
    jsr .hex
    jsr .point_before_rx    ; the 32 bytes before it
    lda #13
    jsr .dump_rows
    ldx #17                 ; and as characters
    jsr .row
    jsr .point_before_rx
-   jsr .peek
    and #$3f                ; roughly readable
    sta (zp_a),y
    iny
    cpy #32
    bne -

    ldx #19
    jsr .row
    ldx #.MODE
    jsr .label
    lda term_mode
    jsr .hex
    ldx #.NET
    jsr .label
    lda net_status
    jsr .hex
    ldx #.SINK
    jsr .label
    lda telnet_sink+1
    jsr .hex_digits
    lda telnet_sink
    jsr .hex
    ldx #20                 ; the WiC64 response being received
    jsr .row
    ldx #.SIZE
    jsr .label
    lda wic64_response_size+1
    jsr .hex_digits
    lda wic64_response_size
    jsr .hex
    ldx #.PAGE
    jsr .label
    lda wic64_destination_pointer_pages+1
    jsr .hex_digits
    lda wic64_destination_pointer_pages
    jsr .hex

    ldx #22
    jsr .row
    ldx #.PHOTO
    jsr .label
    ldx #23
    jsr .row
    ldx #.RESET
    jsr .label
    rts

; Points .peek at the 32 bytes before what receive.asm hands on next
.point_before_rx:
    lda receive_next
    sec
    sbc #32
    pha
    lda receive_next+1
    sbc #0
    tax
    pla
; A/X = the address .peek reads from next
.point:
    sta .peek+1
    stx .peek+2
    rts

; Four rows of 8 bytes from .peek's address in hex, from row A on
.dump_rows:
    sta .row_number
    lda #4
    sta .count
-   ldx .row_number
    jsr .row
    jsr .dump
    inc .row_number
    dec .count
    bne -
    rts

; X = row: zp_a points at it on the screen, Y = 0
.row:
    lda #<SCREEN
    sta zp_a
    lda #>SCREEN
    sta zp_a+1
    ldy #0
-   dex
    bmi +
    lda zp_a
    clc
    adc #40
    sta zp_a
    bcc -
    inc zp_a+1
    bne -                   ; always
+   rts

; Shows the label at .labels + X
.label:
-   lda .labels,x
    beq +
    sta (zp_a),y
    iny
    inx
    bne -
+   rts

; Shows 8 bytes from .peek's address in hex
.dump:
    ldx #8
-   jsr .peek
    stx .bytes_left
    jsr .hex
    ldx .bytes_left
    dex
    bne -
    rts

; Returns the byte at its operand in A, and moves on to the next
.peek:
    lda $ffff
    inc .peek+1
    bne +
    inc .peek+2
+   rts

; Shows A in hex and a space
.hex:
    jsr .hex_digits
    iny
    rts
.hex_digits:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr .digit
    pla
    and #$0f
.digit:
    cmp #10
    bcc +
    sbc #9                  ; C=1: 10 -> "A"
    bne ++                  ; always
+   ora #$30
++  sta (zp_a),y
    iny
    rts

.labels:
.TITLE = * - .labels
    !scr "wic64 telnet: crash report", 0
.REGISTERS = * - .labels
    !scr "pc   a  x  y  p  s  01", 0
.CODE = * - .labels
    !scr "code ", 0
.STACK = * - .labels
    !scr "stack", 0
.RX = * - .labels
    !scr "rx ", 0
.END = * - .labels
    !scr " end ", 0
.MODE = * - .labels
    !scr "mode ", 0
.NET = * - .labels
    !scr " net ", 0
.SINK = * - .labels
    !scr " sink ", 0
.SIZE = * - .labels
    !scr "wic64 size ", 0
.PAGE = * - .labels
    !scr " page ", 0
.PHOTO = * - .labels
    !scr "please take a photo of this screen.", 0
.RESET = * - .labels
    !scr "then press a key to return to basic.", 0
!if * - .labels > 256 {
    !error "The crash report's labels must fit in 256 bytes"
}

.pc:     !word 0
.a:      !byte 0            ; in the order shown
.x:      !byte 0
.y:      !byte 0
.p:      !byte 0
.s:      !byte 0
.memory: !byte 0
.count:       !byte 0
.row_number:  !byte 0
.bytes_left:  !byte 0
}

;---------------------------------------------------------
; Printing the screen (the session menu's P)
;
; Sends the terminal's rows to the printer, device 4 on the serial bus,
; as PETSCII, each followed by RETURN: the 25 rows of PETSCII mode, the
; 24 of the ANSI modes (without the status line), in 80 columns the 80
; characters of each row. Commodore printers print the C64's character
; set, in the case the screen shows; reverse video goes as RVS ON/OFF,
; colours are lost. Spaces at the end of a row are left out.
;
; The border flashes green once it is printed, red if no printer
; answers.
;---------------------------------------------------------

!zone print {
.FILE = 4
.DEVICE = 4
.UPPER_LOWER = 7            ; secondary addresses: the printer's case
.UPPER_GRAPHICS = 0
.RVS_ON = $12
.RVS_OFF = $92

print_screen:
    lda #.DEVICE
    jsr device_present      ; else CHKOUT could still go on
    bcc +
    jmp .failed
+   lda #0
    jsr SETNAM
    ldy #.UPPER_LOWER
    lda term_mode           ; the ANSI modes show upper and lower case;
    bne +                   ; PETSCII mode the set the BBS chose
    lda VIC_MEMORY
    and #$02
    bne +
    ldy #.UPPER_GRAPHICS
+   lda #.FILE
    ldx #.DEVICE
    jsr SETLFS
    jsr OPEN
    bcs .failed
    ldx #.FILE
    jsr CHKOUT
    bcs .failed

    lda #0
    sta .row
.next_row:
    lda #0
    sta .reverse
    ldx .row
    jsr term_row_cells
    ldy term_columns        ; the last character that isn't a space
-   dey
    bmi .row_done
    lda (zp_a),y
    cmp #" "
    beq -
    sty .last
    ldy #0
.next_cell:
    lda (zp_a),y
    and #$80
    cmp .reverse
    beq +
    sta .reverse
    lda #.RVS_OFF
    bcc ++                  ; (from cmp: the new state is 0)
    lda #.RVS_ON
++  jsr CHROUT
+   lda (zp_a),y
    jsr .to_petscii
    jsr CHROUT
    iny
    cpy .last
    beq .next_cell
    bcc .next_cell
.row_done:
    lda #$0d                ; which also ends reverse on the printer
    jsr CHROUT
    inc .row
    lda .row
    cmp term_rows
    bcc .next_row

    jsr .close
    lda #COLOR_GREEN
    jmp ui_flash

.failed:
    jsr .close
    lda #COLOR_RED
    jmp ui_flash

.close:
    jsr CLRCHN
    lda #.FILE
    jmp CLOSE

; A = screen code; returns the PETSCII code for it
.to_petscii:
    and #$7f
    cmp #$20
    bcc .plus_40            ; @, A-Z, [ ... : $40-$5f
    cmp #$40
    bcc .same               ; space, digits, punctuation
    cmp #$60
    bcs .plus_40            ; graphics: $a0-$bf
    ora #$80                ; graphics, or upper case: $c0-$df
.same:
    rts
.plus_40:
    clc
    adc #$40
    rts

.row:     !byte 0
.last:    !byte 0
.reverse: !byte 0           ; $80 while sending reverse video
}

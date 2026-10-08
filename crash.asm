;---------------------------------------------------------
; Crash report: RUN/STOP + RESTORE shows where the client was
;
; Instead of the KERNAL's warm start (back to BASIC), RUN/STOP +
; RESTORE stops the client and shows, on the text screen with a red
; border:
;
;   PC     where the CPU was, with A, X, Y, the status register P, the
;          stack pointer S and the memory configuration ($01)
;   CODE   the 8 bytes at PC (as RAM)
;   STACK  32 bytes from the top of the stack: return addresses show
;          the calls that led there
;   RX     how far the last read has been handed on (and its end),
;          with the 32 bytes before it: what the server sent last
;   MODE   the terminal mode, the last WiC64 status and where the
;          server's data goes (telnet_sink)
;
; Only a reset gets out of it. RESTORE on its own does nothing, as
; before. If the CPU has jammed (an illegal opcode), nothing reacts at
; all, RUN/STOP + RESTORE neither.
;
; The report (crash_report.asm) is copied to CRASH_REPORT, in the RAM
; under the I/O area, at start-up: only what has to see the I/O area
; is here. The copying (crash_setup) runs once, where it was loaded,
; as the high part then moves over it.
;---------------------------------------------------------

!zone crash {
.NMI_VECTOR = $0318
.CIA1_PORT_A = $dc00
.CIA1_PORT_B = $dc01
.IOINIT = $ff84
.CINT = $ff81

; From the KERNAL's NMI entry, which only did SEI
crash_nmi:
    pha
    lda .CIA1_PORT_A
    pha
    lda #$7f                ; the row with RUN/STOP
    sta .CIA1_PORT_A
    lda .CIA1_PORT_B
    bpl .report
    pla                     ; RESTORE alone: carry on
    sta .CIA1_PORT_A
    pla
crash_ignore:
    rti

.report:
    sei                     ; (already, from the KERNAL)
    stx crash_x
    sty crash_y
    tsx
    stx crash_s
    lda R6510
    sta crash_memory
    lda #<crash_ignore      ; only once
    sta .NMI_VECTOR
    lda #>crash_ignore
    sta .NMI_VECTOR+1
    jsr .IOINIT             ; the KERNAL's own start-up: VIC bank 0,
    jsr .CINT               ; text mode, cleared screen
    lda #COLOR_RED
    sta BORDER
    lda #COLOR_BLACK
    sta BACKGROUND
    sta SID_VOLUME
    lda #R6510_ALL_RAM
    sta R6510
    jsr CRASH_REPORT
    lda #R6510_DEFAULT
    sta R6510
-   jmp -                   ; until the reset

crash_x:      !byte 0       ; at the NMI, for crash_report.asm
crash_y:      !byte 0
crash_s:      !byte 0       ; the stack pointer in .report
crash_memory: !byte 0       ; $01
}

; crash_setup: copies the report into place and takes over the NMI.
; The code is placed after the report in the program file (main.asm).
!macro crash_setup {
    lda #<crash_report_load
    sta zp_a
    lda #>crash_report_load
    sta zp_a+1
    lda #<CRASH_REPORT
    sta zp_b
    lda #>CRASH_REPORT
    sta zp_b+1
    sei
    lda #R6510_ALL_RAM      ; writes to the RAM, not to the I/O
    sta R6510
    ldx #CRASH_REPORT_PAGES
    ldy #0
-   lda (zp_a),y
    sta (zp_b),y
    iny
    bne -
    inc zp_a+1
    inc zp_b+1
    dex
    bne -
    lda #R6510_DEFAULT
    sta R6510
    lda #<crash_nmi
    sta $0318
    lda #>crash_nmi
    sta $0319
    cli
    rts
}

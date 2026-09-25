;---------------------------------------------------------
; Telnet protocol (RFC 854)
;
; Separates the server's data from Telnet commands and answers
; option negotiation. The client never starts a negotiation itself,
; so servers that don't speak Telnet (many C64 BBSes) see nothing
; but plain data. When asked, it agrees to:
;
;   BINARY (0)  both directions, needed for 8-bit PETSCII and UTF-8
;   ECHO   (1)  server echoes what we type (turns local echo off)
;   SGA    (3)  both directions, character-at-a-time mode
;   TTYPE (24)  reports "PETSCII" or "ANSI" depending on the mode
;   NAWS  (31)  reports the window size: 40 x 25 (PETSCII) or 40 x 24
;
; Everything else is refused.
;---------------------------------------------------------

!zone telnet {
TN_SE   = 240
TN_BRK  = 243
TN_IP   = 244
TN_AYT  = 246
TN_SB   = 250
TN_WILL = 251
TN_WONT = 252
TN_DO   = 253
TN_DONT = 254
TN_IAC  = 255

OPT_BINARY = 0
OPT_ECHO   = 1
OPT_SGA    = 3
OPT_TTYPE  = 24
OPT_NAWS   = 31

TTYPE_IS   = 0
TTYPE_SEND = 1

; receive states
.DATA     = 0
.IAC      = 1
.OPTION   = 2   ; after IAC WILL/WONT/DO/DONT
.SUB      = 3   ; inside IAC SB ... IAC SE
.SUB_IAC  = 4

.SUB_MAX = 8

; Option table: .local_on/.remote_on track what is currently agreed
; so that repeated requests are not answered again (no loops).
.OPTION_COUNT = 5
.BINARY_INDEX = 0
.NAWS_INDEX   = 4
.options:   !byte OPT_BINARY, OPT_ECHO, OPT_SGA, OPT_TTYPE, OPT_NAWS
.we_do:     !byte 1,          0,        1,       1,         1
.they_may:  !byte 1,          1,        1,       0,         0
.local_on:  !fill .OPTION_COUNT, 0
.remote_on: !fill .OPTION_COUNT, 0

; Call before each new connection.
telnet_reset:
    lda #.DATA
    sta .state
    ldx #.OPTION_COUNT-1
-   sta .local_on,x
    sta .remote_on,x
    dex
    bpl -
    rts

; Takes the next byte from the server in A. Preserves X and Y.
telnet_receive:
    stx .x
    sty .y
    ldx .state
    bne .command

    cmp #TN_IAC
    beq .enter_iac
    jsr term_output
    jmp .exit

.enter_iac:
    lda #.IAC
    sta .state
    jmp .exit

.command:
    cpx #.IAC
    bne .not_iac
    ldx #.DATA
    stx .state
    cmp #TN_IAC
    bne +
    jsr term_output         ; IAC IAC is a literal $ff
    jmp .exit
+   cmp #TN_SB
    bne +
    ldx #.SUB
    stx .state
    ldx #0
    stx .sub_length
    jmp .exit
+   cmp #TN_WILL
    bcc .exit               ; NOP, GA and friends need no action
    sta .verb
    ldx #.OPTION
    stx .state
    jmp .exit

.not_iac:
    cpx #.OPTION
    bne .not_option
    ldx #.DATA
    stx .state
    jsr .negotiate
    jmp .exit

.not_option:
    cpx #.SUB
    bne .sub_iac
    cmp #TN_IAC
    bne .sub_store
    ldx #.SUB_IAC
    stx .state
    jmp .exit

.sub_iac:
    cmp #TN_IAC
    bne +
    ldx #.SUB               ; IAC IAC inside SB is a literal $ff
    stx .state
    jmp .sub_store
+   ldx #.DATA
    stx .state
    cmp #TN_SE
    bne .exit
    jsr .subnegotiation
    jmp .exit

.sub_store:
    ldx .sub_length
    cpx #.SUB_MAX
    bcs .exit
    sta .sub_buffer,x
    inc .sub_length

.exit:
    ldx .x
    ldy .y
    rts

; A = option, .verb = WILL/WONT/DO/DONT
.negotiate:
    sta .option
    ldx #.OPTION_COUNT-1
-   cmp .options,x
    beq +
    dex
    bpl -                   ; X = $ff: unknown option
+   lda .verb
    cmp #TN_DO
    beq .do
    cmp #TN_DONT
    beq .dont
    cmp #TN_WILL
    beq .will

.wont:
    cpx #$ff
    beq .done
    lda .remote_on,x
    beq .done
    lda #0
    sta .remote_on,x
    lda #TN_DONT
    jmp .send_verb

.do:
    cpx #$ff
    beq .refuse_do
    lda .we_do,x
    beq .refuse_do
    lda .local_on,x
    bne .done
    lda #1
    sta .local_on,x
    lda #TN_WILL
    jsr .send_verb
    lda .option
    cmp #OPT_NAWS
    bne .done
    jmp .send_window_size
.refuse_do:
    lda #TN_WONT
    jmp .send_verb

.dont:
    cpx #$ff
    beq .done
    lda .local_on,x
    beq .done
    lda #0
    sta .local_on,x
    lda #TN_WONT
    jmp .send_verb

.will:
    cpx #$ff
    beq .refuse_will
    lda .they_may,x
    beq .refuse_will
    lda .remote_on,x
    bne .done
    lda #1
    sta .remote_on,x
    lda .option
    cmp #OPT_ECHO
    bne +
    lda #0
    sta term_local_echo     ; the server echoes from now on
+   lda #TN_DO
    jmp .send_verb
.refuse_will:
    lda #TN_DONT
    jmp .send_verb

.done:
    rts

; Sends IAC, A, .option
.send_verb:
    pha
    lda #TN_IAC
    jsr net_send
    pla
    jsr net_send
    lda .option
    jmp net_send

.subnegotiation:
    lda .sub_length
    cmp #2
    bcc .done
    lda .sub_buffer
    cmp #OPT_TTYPE
    bne .done
    lda .sub_buffer+1
    cmp #TTYPE_SEND
    bne .done

    lda #TN_SB
    jsr .send_command
    lda #OPT_TTYPE
    jsr net_send
    lda #TTYPE_IS
    jsr net_send
    jsr term_type_name
    sta .name+1
    sty .name+2
    ldx #0
.name:
    lda $ffff,x
    beq +
    jsr net_send
    inx
    bne .name
+   jmp .end_subnegotiation

; Reports the terminal size if the server asked for it (NAWS).
telnet_window_changed:
    lda .local_on+.NAWS_INDEX
    bne .send_window_size
    rts
.send_window_size:
    lda #TN_SB
    jsr .send_command
    lda #OPT_NAWS
    jsr net_send
    lda #0
    jsr net_send
    lda #40
    jsr net_send
    lda #0
    jsr net_send
    lda term_rows
    jsr net_send
.end_subnegotiation:
    lda #TN_SE

; Sends IAC followed by the command in A (e.g. TN_BRK, TN_IP, TN_AYT).
telnet_send_command:
.send_command:
    pha
    lda #TN_IAC
    jsr net_send
    pla
    jmp net_send

; Sends the data byte in A, escaping $ff. Preserves X and Y.
telnet_send:
    cmp #TN_IAC
    bne +
    jsr net_send
+   jmp net_send

; Sends the Telnet end-of-line: CR NUL, or a bare CR in binary mode.
telnet_send_newline:
    lda #$0d
    jsr net_send
    lda .local_on+.BINARY_INDEX
    bne +
    lda #0
    jmp net_send
+   rts

.state:      !byte 0
.verb:       !byte 0
.option:     !byte 0
.sub_length: !byte 0
.sub_buffer: !fill .SUB_MAX, 0
.x:          !byte 0
.y:          !byte 0
}

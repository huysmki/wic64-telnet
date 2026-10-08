;---------------------------------------------------------
; Session: one connection from connect to hang-up
;
; Runs the loop that moves data between the network and the terminal,
; handles the session keys (F1 hang up, F3 line input, F5 local echo,
; F7 session menu, SHIFT F7 scrollback), keeps the online clock and status line up to date
; and deals with network failures: timeouts are retried quietly a few
; times, anything else asks the user whether to retry or give up.
;---------------------------------------------------------

!zone session {
.AUTO_RETRIES = 3
.HOST_MAX = 80
.STATUS_ROW = 24
.STATUS_COLOR = COLOR_GREY
.MENU_COLOR = COLOR_GREEN
.ERROR_COLOR = COLOR_RED

; A/Y = "host:port" (0-terminated), X = terminal mode.
; Returns when the user hangs up or gives up.
session_run:
    sta .copy+1
    sty .copy+2
    stx .mode
    ldx #0
.copy:
    lda $ffff,x
    sta .host,x
    beq +
    inx
    cpx #.HOST_MAX
    bcc .copy
    lda #0
    sta .host,x
+   lda #.AUTO_RETRIES
    sta .retries

.connect:
    lda #0
    sta .online
    jsr term_stop
    +print .connecting_text
    +print .host
    +print .ellipsis
    lda #<.host
    ldy #>.host
    jsr net_open
    bcs .failed

    jsr telnet_reset
    lda #0
    sta term_local_echo
    lda .mode
    jsr term_start
    jsr clock_reset
    lda #1
    sta .online
    jsr .draw_status

.loop:
    jsr ui_tick
    jsr clock_tick
    bcc +
    jsr .draw_status
+   jsr term_cursor_show
    jsr net_poll
    bcs .failed
    lda xfer_offered        ; a BBS waits to send a file
    beq +
    jsr xfer_offer
+   lda #.AUTO_RETRIES
    sta .retries
    jsr .handle_keys
    bcc .loop

.hang_up:
    jsr term_cursor_hide
    jsr net_close
    jmp term_stop

.failed:
    jsr term_cursor_hide
    lda net_status
    cmp #NET_TIMEOUT
    bne .ask
    dec .retries
    beq .ask
    jmp .retry

.ask:
    lda #.AUTO_RETRIES
    sta .retries
    jsr net_error_text
    jsr .ask_retry
    bcs .give_up
    lda net_status          ; a lost WiFi or network connection
    cmp #WIC64_CONNECTION_ERROR ; also lost the TCP connection
    beq .reconnect
    cmp #WIC64_NETWORK_ERROR
    beq .reconnect
.retry:
    lda .online
    beq .reconnect
    jmp .loop
.reconnect:
    jmp .connect

.give_up:
    lda .online
    beq +
    jsr net_close
+   jmp term_stop

; Returns C=1 to hang up.
.handle_keys:
    jsr get_key
    bne +
    clc
    rts
+   cmp #KEY_F1
    bne +
    sec
    rts
+   cmp #KEY_F3
    bne +
    jsr .line_input
    jmp .handle_keys
+   cmp #KEY_F5
    bne +
    jsr .toggle_echo
    jmp .handle_keys
+   cmp #KEY_F7
    bne +
    jsr .session_menu
    bcc .handle_keys
    rts
+   cmp #KEY_F8
    bne +
    jsr scrollback_view
    jmp .handle_keys
+   jsr term_key
    jmp .handle_keys

.toggle_echo:
    lda term_local_echo
    eor #1
    sta term_local_echo
    beq +
    lda #COLOR_GREEN
    jsr ui_flash
    jmp .draw_status
+   lda #COLOR_RED
    jsr ui_flash
    jmp .draw_status

; Lets the user type a whole line (up to 80 characters) and sends it.
.line_input:
    lda #.MENU_COLOR
    ldx #21
    jsr box_open
    +plot 1, 22
    lda #0
    tay
    jsr ui_input
    pha
    jsr box_close
    pla
    beq .line_done
    ldx #0
-   lda INPUT_BUFFER,x
    beq +
    stx .index
    jsr term_key
    ldx .index
    inx
    bne -
+   lda #KEY_RETURN
    jmp term_key
.line_done:
    rts

; Shows the connection details and the less common actions.
; Returns C=1 to hang up.
.session_menu:
    lda #.MENU_COLOR
    ldx #17
    jsr box_open
    +plot 1, 18
    lda #<.host
    ldy #>.host
    ldx #38
    jsr print_field
    +plot 1, 19
    +print .mode_label
    lda term_mode
    jsr term_mode_name
    ldx #9
    jsr print_field
    +print .echo_label
    lda #<.off_text
    ldy #>.off_text
    ldx term_local_echo
    beq +
    lda #<.on_text
    ldy #>.on_text
+   ldx #5
    jsr print_field
    jsr clock_format
    +print clock_text
    +plot 1, 20
    +print .menu_line1
    +plot 1, 21
    +print .menu_line2
    +plot 1, 22
    +print .menu_line3
    +plot 1, 23
    +print .menu_line4

    jsr wait_key
    pha
    jsr box_close
    pla
    cmp #"M"
    bne +
    jsr .next_mode
    clc
    rts
+   cmp #"E"
    bne +
    jsr .toggle_echo
    clc
    rts
+   cmp #"H"
    bne +
    sec
    rts
+   cmp #"S"
    bne +
    jsr scrollback_view
    clc
    rts
+   cmp #"D"
    bne +
    jsr xfer_download
    clc
    rts
+   ldx #.COMMAND_COUNT-1
-   cmp .command_keys,x
    beq +
    dex
    bpl -
    clc
    rts
+   lda .commands,x
    jsr telnet_send_command
    clc
    rts

.COMMAND_COUNT = 3
.command_keys: !byte "B", "I", "A"
.commands:     !byte TN_BRK, TN_IP, TN_AYT

.next_mode:
    ldx term_mode
    inx
    cpx #TERM_MODES
    bcc +
    ldx #0
+   stx .mode
    txa
    jsr term_start
    jsr telnet_window_changed
    jmp .draw_status

; Draws the status line in the ANSI modes (PETSCII uses all 25 rows).
.draw_status:
    lda term_mode
    bne +
    rts
+   ldx #39
    lda #" "
-   sta .status,x
    dex
    bpl -

    ldx #0
-   lda .host,x
    beq +
    jsr petscii_to_screen
    sta .status+1,x
    inx
    cpx #17
    bcc -
+
    lda term_mode
    jsr term_mode_name
    sta .mode_name+1
    sty .mode_name+2
    ldx #0
.mode_name:
    lda $ffff,x
    beq +
    jsr petscii_to_screen
    sta .status+19,x
    inx
    bne .mode_name
+
    lda term_local_echo
    beq +
    ldx #3
-   lda .echo_screen,x
    sta .status+27,x
    dex
    bpl -
+
    jsr clock_format
    ldx #7
-   lda clock_text,x
    jsr petscii_to_screen
    sta .status+32,x
    dex
    bpl -

    ldx #39
-   lda .status,x
    ora #$80
    sta SCREEN + .STATUS_ROW * 40,x
    lda #.STATUS_COLOR
    sta COLOR_RAM + .STATUS_ROW * 40,x
    dex
    bpl -
    rts

; Asks whether to retry after the failure described at A/Y.
; Returns C=1 to give up.
.ask_retry:
    pha
    tya
    pha
    lda #.ERROR_COLOR
    ldx #21
    jsr box_open
    +plot 1, 22
    pla
    tay
    pla
    ldx #38
    jsr print_field
    +plot 20, 23
    +print .retry_prompt
-   jsr wait_key
    cmp #KEY_F1
    beq +
    cmp #KEY_F3
    bne -
+   pha
    jsr box_close
    pla
    cmp #KEY_F1
    beq +
    clc
    rts
+   sec
    rts

.connecting_text: !pet 13, "Connecting to ", 0
.ellipsis:        !pet "...", 13, 0
.mode_label:      !pet "Mode ", PET_WHITE, 0
.echo_label:      !pet PET_GREEN, "Echo ", PET_WHITE, 0
.on_text:         !pet "on", 0
.off_text:        !pet "off", 0
.menu_line1:      !pet PET_WHITE, "M", PET_GREEN, " next mode    "
                  !pet PET_WHITE, "E", PET_GREEN, " local echo", 0
.menu_line2:      !pet PET_WHITE, "S", PET_GREEN, " scrollback   "
                  !pet PET_WHITE, "H", PET_GREEN, " hang up", 0
.menu_line3:      !pet PET_WHITE, "B", PET_GREEN, " send break   "
                  !pet PET_WHITE, "I", PET_GREEN, " interrupt", 0
.menu_line4:      !pet PET_WHITE, "D", PET_GREEN, " download     "
                  !pet PET_WHITE, "A", PET_GREEN, " are you there", 0
.retry_prompt:    !pet PET_YELLOW, "F1 ", PET_RED, "Abort  "
                  !pet PET_YELLOW, "F3 ", PET_RED, "Retry", 0
.echo_screen:     !scr "echo"

.mode:    !byte 0
.online:  !byte 0
.retries: !byte 0
.index:   !byte 0
.host:    !fill .HOST_MAX + 1, 0
.status:  !fill 40, 0
}

!zone petscii_to_screen {
; Converts a PETSCII character in A to a screen code for the lower/upper
; case set.
petscii_to_screen:
    cmp #$20
    bcc .unprintable
    cmp #$40
    bcc .same               ; space, digits, punctuation
    cmp #$60
    bcc .minus_40           ; @, lower case letters, [ £ ] ↑ ←
    cmp #$80
    bcc .minus_20           ; $60-$7f show the same as $c0-$df
    cmp #$a0
    bcc .unprintable
    cmp #$c0
    bcc .minus_40           ; $a0-$bf graphics
    cmp #$e0
    bcc .minus_80           ; upper case letters, graphics
    cmp #$ff
    bcc .minus_80           ; $e0-$fe show the same as $a0-$be
    lda #$5e                ; π
    rts
.same:
    rts
.minus_20:
    sec
    sbc #$20
    rts
.minus_40:
    sec
    sbc #$40
    rts
.minus_80:
    sec
    sbc #$80
    rts
.unprintable:
    lda #" "
    rts
}

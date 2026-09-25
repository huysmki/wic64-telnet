server = $fb

ron = $12
roff = $92

key_f1 = $85
key_f3 = $86
key_f5 = $87
key_f7 = $88

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp init

wic64_include_enter_portal = 1
!src "wic64.h"
!src "wic64.asm"

!macro jcs .addr {
    bcc +
    jmp .addr
+
}

!macro jne .addr {
    beq +
    jmp .addr
+
}

!macro jeq .addr {
    bne +
    jmp .addr
+
}

!macro pointer .pointer, .addr {
    lda #<.addr
    sta .pointer
    lda #>.addr
    sta .pointer+1
}

!macro add16 .addr {
    clc
    adc .addr
    sta .addr
    lda #$00
    adc .addr+1
    sta .addr+1
}

!macro print .addr {
    lda #<.addr
    ldy #>.addr
    jsr $ab1e
}

!macro print_pointer .pointer {
    ldy #$00
-   lda (.pointer),y
    beq .done
    jsr $ffd2
    iny
    bne -
.done
}

!macro newline {
    lda #$0d
    jsr $ffd2
}

!macro paragraph {
    lda #$0d
    jsr $ffd2
    jsr $ffd2
}

!macro each_server .callback {
    lda #<.callback
    sta each_server_callback
    lda #>.callback
    sta each_server_callback+1
    jsr each_server
}

!macro plot .x, .y {
    ldy #.x
    ldx #.y
    clc
    jsr $fff0
}

!macro open_box .color {
    lda #.color
    sta box_color
    jsr open_box
}

!macro close_box {
    jsr close_box
}

init:
    +wic64_detect
    +jcs device_not_present
    +jne legacy_firmware_detected

    +wic64_dont_disable_irqs

    +wic64_execute set_transfer_timeout, $05
    +wic64_execute set_remote_timeout, $05
main:
    jsr init_screen
    jsr clear_screen

    +print menu_title
    +each_server print_server
    +newline

    jsr count_servers
    clc
    adc #"0"
    ldx #$02
    sta keybindings_text, x
    +print keybindings_text

-   jsr $ffe4
    beq -

    cmp #$5f
    +jeq return_to_portal

    cmp #$0d
    +jeq input_server_and_connect

    sec
    sbc #"1"
    jsr get_server
    beq -

    ldy #$00
-   lda (server),y
    sta open_request_payload,y
    beq +
    iny
    jmp -

+   sty open_request_size

connect:
    jsr clear_screen

    +pointer retry_action, connect
    +wic64_execute open_request, response, $05
    +jcs timeout
    +jne error

    jsr clear_screen

    +wic64_set_store_instruction jsr_print_character
    +pointer retry_action, read

read:
    +wic64_execute read_request, $05
    +jcs timeout
    +jne error
lda #$03
sta retry
scan:
    jsr $ffe4
    beq read

    cmp #key_f1
    +jeq quit

    cmp #key_f3
    +jeq input_line_and_write

write_character:
    sta write_request_payload
    lda #$01
    sta write_request_size

write:
    +wic64_execute write_request, $05
    +jcs timeout
    +jne error
lda #$03
sta retry
    jmp read

input_line_and_write:
    jsr input

    jsr is_input_empty_or_blank
    +jeq read

    ldy #$00
-   lda $0200,y
    beq +
    sta write_request_payload,y
    iny
    jmp -

+   sty write_request_size
    jmp write

quit:
    +wic64_reset_store_instruction
    +wic64_execute close_request, $05
    +jcs timeout
    +jne error
    jmp main

input: !zone input {
    +open_box $05
    jsr $a560
    +close_box
    rts
}

box: !zone box {
.screen_pos = $0400+21*40
.color_pos = $d800+21*40

open_box:
    jsr save_cursor_pos
    +plot 0, 22

    lda $0286
    sta .cursor_color
    lda box_color
    sta $0286

    lda $c7
    sta .reverse
    lda #$00
    sta $c7

    ldy #$00
-   lda .screen_pos,y
    sta .screen,y
    lda #$20
    sta .screen_pos,y

    lda .color_pos,y
    sta .color,y
    lda box_color
    sta .color_pos,y

    iny
    cpy #$4*40
    bne -

    lda #$63
    ldy #$27
-   sta .screen_pos,y
    dey
    bpl -

    lda #$64
    ldy #$27
-   sta .screen_pos+3*40,y
    dey
    bpl -
    rts

close_box:
    ldy #$00
-   lda .screen,y
    sta .screen_pos,y

    lda .color,y
    sta .color_pos,y

    iny
    cpy #4*40
    bne -

    lda .reverse
    sta $c7

    lda .cursor_color
    sta $0286

    jsr restore_cursor_pos
    rts

box_color: !byte $00
.cursor_color: !byte $00
.reverse: !byte $00
.screen: !fill 4*40, 0
.color: !fill 4*40, 0
}

is_input_empty_or_blank: !zone is_input_empty_or_blank {
    ldy #00
    sty .blank
-   lda $0200,y
    beq .done
    cmp #$20
    beq +
    lda #$01
    sta .blank
    jmp .done
 +  iny
    cpy #$50
    bne -

.done
    lda .blank
    rts

.blank: !byte $00
}

input_server_and_connect:
    +print server_prompt
    jsr $a560

    jsr is_input_empty_or_blank
    +jeq main

+   ldy #$00
-   lda $0200,y
    sta open_request_payload,y
    beq +
    iny
    jmp -

+   sty open_request_size

    jmp connect

return_to_portal:
    +wic64_enter_portal
    jmp main

jsr_print_character:
    jsr print_character

print_character: !zone print_character {
    stx .x
    sty .y

    cmp #$ff ; TODO: handle telnet IAC properly
    beq +
    jsr $ffd2

+   ldx .x
    ldy .y
    rts

.x: !byte $00
.y: !byte $00
}

!zone safe_restore_cursor_pos {
save_cursor_pos:
    sec
    jsr $fff0
    stx .x
    sty .y
    rts

restore_cursor_pos:
    ldx .x
    ldy .y
    clc
    jsr $fff0
    rts

.x: !byte $00
.y: !byte $00
}

device_not_present:
    +newline
    +print device_not_present_error
    rts

legacy_firmware_detected:
    +newline
    +print legacy_firmware_error
    +paragraph
    +print legacy_firmware_hint
    rts

error:
    lda wic64_status
    cmp #$03 ; WiFi connection lost = reconnect on retry
    bne +

-   +pointer retry_action, connect
    jmp ++

+   cmp #$04 ; Network error => reconnect on retry
    beq -

++  +wic64_reset_store_instruction
    +wic64_execute error_request, response, $05
    +jcs timeout

    +open_box $02
    +print response
    jmp retry_or_abort

timeout:
   dec retry            ; immer erst 3x automatisch den Wiederverbindungsversuch probieren, bevor die Fehlermeldung erscheint
   beq +
;inc $d020
   jmp ++
+
    +open_box $02
    +print timeout_error
    jmp retry_or_abort

retry_or_abort: !zone retry_or_abort {
    +plot 40-.prompt_length-2, 24
    +print .prompt

.scan:
    jsr $ffe4
    beq .scan

    cmp #key_f3
    bne +

    +close_box
++
retry_action = *+1
    jmp read

+   cmp #key_f1
    bne .scan

    +close_box
    jmp main

.prompt: !pet $9e, "F1 ", $1c, "Abort ", $9e, "F3 ", $1c, "Retry", $00
.prompt_length = * - .prompt - 5
}

init_screen:
    lda #$00
    sta $d020
    sta $d021

    lda #$05
    sta $0286

    lda #$0e
    jsr $ffd2

    jsr clear_screen
    rts

clear_screen:
    lda #$93
    jsr $ffd2
    rts

each_server: !zone each_server {
    +pointer server, servers
    lda #$ff
    sta .index
    ldy #$ff

.callback:
    iny
    tya
    +add16 server

    ldy #$00
    lda (server),y
    cmp #$ff
    beq .done

    inc .index
    lda .index
each_server_callback = *+1
    jsr $0000
    bcc .done

    ldy #$00
-   lda (server),y
    beq .callback
    iny
    jmp -

.done
    rts

.index: !byte $00
}

get_server: !zone get_server {
    sta .wanted
    +each_server .callback
    ldy #$00
    lda (server),y
    cmp #$ff
    rts

.callback:
    cmp .wanted
    bne .continue
    clc
    rts

.continue:
    sec
    rts

.wanted: !byte $00
}

count_servers: !zone count_servers {
   lda #$00
   sta .count
   +each_server .callback
   lda .count
   rts

.callback:
    inc .count
    sec
    rts

.count: !byte $00
}

print_server: !zone print_server {
    clc
    adc #"1"
    jsr $ffd2

    lda #")"
    jsr $ffd2

    lda #" "
    jsr $ffd2

    ldy #$00
-   lda (server),y
    beq .done
    jsr $ffd2
    iny
    bne -
 .done
    +newline
    sec
    rts

.index: !byte $00
}

retry: !byte $03

error_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $00

open_request: !byte "R", WIC64_TCP_OPEN
open_request_size: !byte $00, $00
open_request_payload: !fill 256, 0

read_request: !byte "R", WIC64_TCP_READ, $00, $00

write_request: !byte "R", WIC64_TCP_WRITE
write_request_size: !byte $00, $00
write_request_payload: !fill 81, 0

set_transfer_timeout: !byte "R", WIC64_SET_TRANSFER_TIMEOUT, $01, $00, $05
set_remote_timeout: !byte "R", WIC64_SET_REMOTE_TIMEOUT, $01, $00, $05

close_request !byte "R", WIC64_TCP_CLOSE, $00, $00

menu_title: !pet ron, "  -- WiC64 Simple Telnet Client 2.0 --  ", roff, $0d, $00

keybindings_text:
!pet "1-?) Connect to server from list", $0d ; TODO: count servers and set actual count here
!pet "RET) Enter server (host:port)", $0d
!pet "ESC) Return to WiC64 portal", $0d
!pet $0d
!pet "In a telnet session:", $0d
!pet $0d
!pet "F1) Close session and return", $0d
!pet "F3) Enter line of input (80 chars max)", $0d
!pet $0d
!pet "When using F3, you may have to hit", $0d
!pet "RETURN twice to proceed", $0d
!pet $0d
!byte $00

server_prompt: !pet "server> ", $00

servers:
!pet "13th.hoyvision.com:6400", $00
!pet "cib.dyndns.org:6405", $00
!pet "darklevel.hopto.org:64128", $00
!pet "rapidfire.hopto.org:64128", $00
!pet "raveolution.hopto.org:64128", $00
!pet "8bit.hoyvision.com:6400", $00
!pet "bbs.retrocampus.com:6510", $00
!byte $ff

timeout_error: !pet "Transfer timeout", $00
device_not_present_error: !pet "?wic64 not present or unresponsive", $00
legacy_firmware_error: !pet "?legacy firmware detected", $00
legacy_firmware_hint: !pet "firmware 2.0.0 or later required", $00

response:
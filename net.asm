;---------------------------------------------------------
; Network transport: one TCP connection through the WiC64
;
; Bytes for the server are queued with net_send and go out on the
; next net_poll, which then reads whatever the server has sent and
; hands each byte to telnet_receive.
;
; Every request costs the WiC64 work (its firmware starts and ends a
; task for each transfer), and reading nonstop meant some 90 requests
; a second even on an idle connection. So while reads bring nothing,
; net_poll waits longer and longer between them, up to
; NET_IDLE_JIFFIES; anything received or sent ends the wait.
;
; Routines that talk to the WiC64 return with carry set on failure.
; net_status then holds the WiC64 status code, or NET_TIMEOUT if the
; device did not answer in time; net_error_text describes it.
;---------------------------------------------------------

!zone net {
NET_TIMEOUT = $ff
NET_TX_SIZE = 250
NET_REQUEST_TIMEOUT = $05
NET_IDLE_JIFFIES = 8        ; at most 8/60 s between reads that bring
                            ; nothing

net_status: !byte 0

; Returns C=1 if no WiC64 answers, otherwise Z=0 if its firmware is
; too old (before 2.0.0) and Z=1 if it is ready.
net_init:
    +wic64_detect
    bcs +
    bne +
    +wic64_dont_disable_irqs
    +wic64_execute .set_transfer_timeout, net_response, NET_REQUEST_TIMEOUT
    +wic64_execute .set_remote_timeout, net_response, NET_REQUEST_TIMEOUT
    lda #0
    clc
+   rts

; Opens a connection to the "host:port" string at A/Y (0-terminated).
net_open:
    sta .host+1
    sty .host+2
    ldy #0
.host:
    lda $ffff,y
    beq +
    sta .open_payload,y
    iny
    bne .host
+   sty .open_size
    lda #0
    sta .tx_length
    sta .idle_wait
    +wic64_execute .open_request, net_response, NET_REQUEST_TIMEOUT
    jmp .result

net_close:
    +wic64_execute .close_request, net_response, NET_REQUEST_TIMEOUT
    jmp .result

; Queues A for the server. Preserves X and Y. Bytes beyond the queue
; size are dropped; the queue empties on every net_poll.
net_send:
    sty .y
    ldy .tx_length
    cpy #NET_TX_SIZE
    bcs +
    sta .tx_payload,y
    inc .tx_length
+   ldy .y
    rts

; Sends the queued bytes, then passes everything received to
; telnet_receive; or, while the connection is idle, does nothing until
; it is time to read again.
net_poll:
    lda .tx_length
    bne .write
    lda JIFFY_LO
    sec
    sbc .last_read
    cmp .idle_wait
    bcs .read
    clc                     ; not yet
    rts

.write:
    sta .tx_size
    +wic64_execute .write_request, net_response, NET_REQUEST_TIMEOUT
    jsr .result
    bcs .poll_done
    lda #0
    sta .tx_length
    sta .idle_wait          ; an answer is likely to follow soon

.read:
    +wic64_set_store_instruction .deliver
    +wic64_execute .read_request, net_response, NET_REQUEST_TIMEOUT
    php
    pha
    +wic64_reset_store_instruction
    lda JIFFY_LO
    sta .last_read
    pla
    plp
    jsr .result
    bcs .poll_done
    lda wic64_response_size
    ora wic64_response_size+1
    beq .nothing_read
    lda #0                  ; data: read again straight away
    sta .idle_wait
    rts                     ; C=0
.nothing_read:
    lda .idle_wait          ; wait 1, 2, 4, ... jiffies
    asl
    bne +
    lda #1
+   cmp #NET_IDLE_JIFFIES + 1
    bcc +
    lda #NET_IDLE_JIFFIES
+   sta .idle_wait
    clc
.poll_done:
    rts

; Not called: wic64_set_store_instruction copies this one 3-byte
; instruction into the WiC64 receive loop, which then calls
; telnet_receive with each received byte in A (it must preserve X and
; Y). It has to be a jsr, and nothing after it is part of it.
.deliver:
    jsr telnet_receive

; Turns the outcome of a WiC64 request (C = timeout, A = status) into
; C=1 on any failure, recording net_status.
.result:
    bcs .timeout
    sta net_status
    cmp #1
    rts
.timeout:
    lda #NET_TIMEOUT
    sta net_status
    sec
    rts

; Returns A/Y = description of the last failure (PETSCII, 0-terminated).
net_error_text:
    lda net_status
    cmp #NET_TIMEOUT
    beq .timeout_text
    +wic64_execute .status_request, net_response, NET_REQUEST_TIMEOUT
    bcs .timeout_text
    ldy wic64_response_size
    lda wic64_response_size+1
    beq +
    ldy #$ff
+   lda #0                  ; the message is 0-terminated PETSCII;
    sta net_response,y      ; this only guards against a missing 0
    lda #<net_response
    ldy #>net_response
    rts
.timeout_text:
    lda #<.timeout_message
    ldy #>.timeout_message
    rts

.timeout_message: !pet "WiC64 did not answer in time", 0

.y: !byte 0
.last_read: !byte 0         ; JIFFY_LO at the last read
.idle_wait: !byte 0         ; jiffies to wait after it

.set_transfer_timeout: !byte "R", WIC64_SET_TRANSFER_TIMEOUT, $01, $00, NET_REQUEST_TIMEOUT
.set_remote_timeout:   !byte "R", WIC64_SET_REMOTE_TIMEOUT, $01, $00, NET_REQUEST_TIMEOUT
.status_request:       !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $00
.read_request:         !byte "R", WIC64_TCP_READ, $00, $00
.close_request:        !byte "R", WIC64_TCP_CLOSE, $00, $00

.open_request: !byte "R", WIC64_TCP_OPEN
.open_size:    !byte $00, $00
.open_payload: !fill 256, 0

.write_request: !byte "R", WIC64_TCP_WRITE
.tx_size:       !byte $00, $00
.tx_payload:    !fill NET_TX_SIZE, 0
.tx_length:     !byte 0
}


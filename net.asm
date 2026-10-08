;---------------------------------------------------------
; Network transport: one TCP connection through the WiC64
;
; Bytes for the server are queued with net_send and go out on the
; next net_poll, which then reads whatever the server has sent and
; hands each byte to telnet_receive.
;
; A read is received whole into NET_RX_BUFFER first and only handed
; on after the transfer: when the WiC64 sends a response, it releases
; the port a few milliseconds after offering the last byte, so a C64
; that is still busy with the byte before (clearing or scrolling the
; screen) would read $ff instead of it.
;
; File transfers take the server's bytes one at a time instead
; (net_read_byte), as a protocol waits for particular answers, and send
; their own answers at once (net_flush). Whatever a transfer leaves in
; the buffer goes to telnet_receive with the next net_poll.
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
;
; A timeout of n waits about n - 1 seconds. Now and then a handshake
; between the C64 and the WiC64 gets lost and both sides wait for the
; other. The firmware gives up on the transfer after 1.3 s;
; NET_POLL_TIMEOUT gives up after it, so that the next request
; finds the WiC64 ready again. Opening a connection takes the firmware
; up to some 12 s (looking up the name, then 5 s to connect), and
; NET_OPEN_TIMEOUT waits for its answer, so that a failure shows the
; WiC64's own error message.
;---------------------------------------------------------

!zone net {
NET_TIMEOUT = $ff
NET_TX_SIZE = 250
NET_REQUEST_TIMEOUT = $05
NET_POLL_TIMEOUT = $03
NET_OPEN_TIMEOUT = $0f
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
    sta .rx_left
    sta .rx_left+1
    +wic64_execute .open_request, net_response, NET_OPEN_TIMEOUT
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
    lda .rx_left            ; left over from a file transfer
    ora .rx_left+1
    beq +
    jmp .deliver_rest
+   lda .tx_length
    bne .write
    lda JIFFY_LO
    sec
    sbc .last_read
    cmp .idle_wait
    bcs .read
    clc                     ; not yet
    rts

.write:
    jsr net_flush
    bcs .poll_done
    lda #0
    sta .idle_wait          ; an answer is likely to follow soon

.read:
    +wic64_execute .read_request, NET_RX_BUFFER, NET_POLL_TIMEOUT
    php
    pha
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
    jmp .deliver
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

; Hands the wic64_response_size bytes in NET_RX_BUFFER to
; telnet_receive. Returns C=0.
.deliver:
    jsr .rewind
.deliver_rest:
-   jsr .take_byte
    jsr telnet_receive
    lda .rx_left
    ora .rx_left+1
    bne -
    clc
    rts

; Sends the bytes queued with net_send now. Returns C=1 on failure.
net_flush:
    lda .tx_length
    bne +
    clc
    rts
+   sta .tx_size
    +wic64_execute .write_request, net_response, NET_REQUEST_TIMEOUT
    jsr .result
    bcs +
    lda #0
    sta .tx_length
+   rts

; Returns C=0 and the server's next byte in A, as it came (Telnet
; commands included), reading from the WiC64 when the buffer is empty;
; C=1 if nothing has come in, or the WiC64 did not answer.
net_read_byte:
    lda .rx_left
    ora .rx_left+1
    bne .take_byte
    +wic64_execute .read_request, NET_RX_BUFFER, NET_POLL_TIMEOUT
    jsr .result
    bcs +
    lda wic64_response_size
    ora wic64_response_size+1
    sec
    beq +
    jsr .rewind
    jmp .take_byte
+   rts

; Points at the start of what the last read brought.
.rewind:
    lda #<NET_RX_BUFFER
    sta .rx+1
    lda #>NET_RX_BUFFER
    sta .rx+2
    lda wic64_response_size
    sta .rx_left
    lda wic64_response_size+1
    sta .rx_left+1
    rts

; Returns the next byte from NET_RX_BUFFER in A, C=0. Preserves X
; and Y.
.take_byte:
    lda #R6510_NO_BASIC     ; the buffer is under the BASIC ROM
    sta R6510
.rx:
    lda $ffff
    pha
    lda #R6510_DEFAULT
    sta R6510
    inc .rx+1
    bne +
    inc .rx+2
+   lda .rx_left
    bne +
    dec .rx_left+1
+   dec .rx_left
    pla
    clc
    rts

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
.rx_left:    !word 0         ; bytes still to hand on
.last_read: !byte 0         ; JIFFY_LO at the last read
.idle_wait: !byte 0         ; jiffies to wait after it

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


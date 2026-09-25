;---------------------------------------------------------
; Test harness: stands in for net.asm in test builds
;
; The "server" plays back test_rx (40 bytes per poll) and everything
; the client sends is logged at TEST_TX_LOG. Keys come from test_keys:
;
;   any other byte  returned as a key press
;   TK_IDLE, n      no key for n calls
;   TK_WAIT_RX      no key until test_rx has been played back
;   TK_TYPE, n, ... puts n keys into the KERNAL keyboard buffer when
;                   the next line input starts (max 10)
;   TK_FAIL, s      the next net_poll fails with WiC64 status s
;   TK_END          stop: sets TEST_DONE and returns no keys
;
; TEST_DONE ($02) is 1 once the script has ended.
;---------------------------------------------------------

!zone fake_net {
NET_TIMEOUT = $ff
TEST_TX_LOG = $9000
TEST_DONE = $02
TK_END     = $f0
TK_IDLE    = $f1
TK_WAIT_RX = $f2
TK_TYPE    = $f3
TK_FAIL    = $f4
.RX_CHUNK  = 40

!ifndef SCENARIO {
    SCENARIO = 1
}

net_status: !byte 0

net_init:
    lda #0
    sta TEST_DONE
    clc
    rts

net_open:
    lda #<test_rx
    sta .rx+1
    lda #>test_rx
    sta .rx+2
    lda #0
    sta net_status
    clc
    rts

net_close:
    clc
    rts

net_send:
    sty .y
.tx:
    sta TEST_TX_LOG
    inc .tx+1
    bne +
    inc .tx+2
+   ldy .y
    rts

net_poll:
    lda .fail_status
    beq +
    sta net_status
    lda #0
    sta .fail_status
    sec
    rts
+   ldx #.RX_CHUNK
.rx:
    lda $ffff
    ldy .rx+1
    cpy #<test_rx_end
    bne +
    ldy .rx+2
    cpy #>test_rx_end
    beq .poll_done
+   inc .rx+1
    bne +
    inc .rx+2
+   stx .x
    jsr telnet_receive
    ldx .x
    dex
    bne .rx
.poll_done:
    clc
    rts

net_error_text:
    lda #<.error
    ldy #>.error
    rts
.error: !pet "Test error", 0

.rx_done:
    lda .rx+1
    cmp #<test_rx_end
    bne +
    lda .rx+2
    cmp #>test_rx_end
+   rts

test_get_key:
    lda .idle
    beq .next
    dec .idle
    lda #0
    rts
.next:
    jsr .fetch
    cmp #TK_END
    bne +
    lda #1
    sta TEST_DONE
    dec .key+1              ; stay on TK_END
    lda #0
    rts
+   cmp #TK_IDLE
    bne +
    jsr .fetch
    sta .idle
    lda #0
    rts
+   cmp #TK_WAIT_RX
    bne +
    jsr .rx_done
    beq ++
    dec .key+1              ; ask again next time
++  lda #0
    rts
+   cmp #TK_TYPE
    bne +
    dec .key+1              ; handled by test_before_input
    lda #0
    rts
+   cmp #TK_FAIL
    bne +
    jsr .fetch
    sta .fail_status
    lda #0
+   rts

test_before_input:
    jsr .fetch
    cmp #TK_TYPE
    bne .not_type
    jsr .fetch
    tax
    ldy #0
-   jsr .fetch
    sta $0277,y
    iny
    dex
    bne -
    sty $c6
    rts
.not_type:
    dec .key+1
    rts

; Returns the next script byte (script is < 256 bytes).
.fetch:
.key:
    lda test_keys
    inc .key+1
    rts

.x:    !byte 0
.y:    !byte 0
.idle: !byte 0
.fail_status: !byte 0
}

!src "test/scenarios.asm"

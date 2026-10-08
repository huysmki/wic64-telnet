;---------------------------------------------------------
; What a read from the WiC64 brought, handed on a byte at a time
;
; A read lands in NET_RX_BUFFER, in the RAM under the BASIC ROM.
; receive_start makes its bytes the ones to hand on; receive_deliver
; passes whatever is left of them to telnet_receive, and receive_byte
; takes one (file transfers read the server's bytes one at a time).
; The benchmark (test/bench.asm) plays its data back through here
; too, so that it measures the same loop as a real connection.
;---------------------------------------------------------

!zone receive {

; A/Y = the number of bytes at NET_RX_BUFFER to hand on. Returns Z=1
; if there are none.
receive_start:
    clc
    adc #<NET_RX_BUFFER
    sta .end
    tya
    adc #>NET_RX_BUFFER
    sta .end+1
    lda #<NET_RX_BUFFER
    sta .rx+1
    lda #>NET_RX_BUFFER
    sta .rx+2
; Returns Z=1 once every byte has been handed on.
receive_pending:
    lda .rx+1
    cmp .end
    bne +
    lda .rx+2
    cmp .end+1
+   rts

; Hands the bytes still to come (at least one) to telnet_receive.
; Returns C=0. The BASIC ROM stays off meanwhile, so what
; telnet_receive calls must leave R6510 as it finds it.
receive_deliver:
    lda #R6510_NO_BASIC
    sta R6510
.rx:
    lda $ffff
    inc .rx+1
    bne +
    inc .rx+2
+   jsr telnet_receive
    lda .rx+1
    cmp .end
    bne .rx
    lda .rx+2
    cmp .end+1
    bne .rx
    lda #R6510_DEFAULT
    sta R6510
    clc
    rts

; Returns the next byte in A, C=0 (receive_pending has said there is
; one). Preserves X and Y.
receive_byte:
    lda #R6510_NO_BASIC
    sta R6510
    lda .rx+1
    sta .byte+1
    lda .rx+2
    sta .byte+2
    inc .rx+1
    bne .byte
    inc .rx+2
.byte:
    lda $ffff
    pha
    lda #R6510_DEFAULT
    sta R6510
    pla
    clc
    rts

.end: !word 0               ; just past the last byte

receive_next = .rx + 1      ; for the crash report
receive_end = .end
}

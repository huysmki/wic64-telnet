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
    sta .left
    sty .left+1
    lda #<NET_RX_BUFFER
    sta .rx+1
    lda #>NET_RX_BUFFER
    sta .rx+2
; Returns Z=1 once every byte has been handed on.
receive_pending:
    lda .left
    ora .left+1
    rts

; Hands the bytes still to come (at least one) to telnet_receive.
; Returns C=0.
receive_deliver:
-   jsr receive_byte
    jsr telnet_receive
    lda .left
    ora .left+1
    bne -
    clc
    rts

; Returns the next byte in A, C=0 (receive_pending has said there is
; one). Preserves X and Y.
receive_byte:
    lda #R6510_NO_BASIC
    sta R6510
.rx:
    lda $ffff
    pha
    lda #R6510_DEFAULT
    sta R6510
    inc .rx+1
    bne +
    inc .rx+2
+   lda .left
    bne +
    dec .left+1
+   dec .left
    pla
    clc
    rts

.left: !word 0              ; bytes still to hand on
}

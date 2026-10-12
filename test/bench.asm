;---------------------------------------------------------
; Benchmark: how fast the client shows what a server sends
;
; Build with -DTEST=1 -DBENCH=<n> (make bench runs them all):
;
;   1  ANSI 80: frames of an animation, each drawn from the top of the
;      screen with most of it unchanged (like Telehack's starwars)
;   2  UTF-8 80: the same frames
;   3  ANSI 80: BBS text, with colours and CP437 blocks, that scrolls
;   4  ANSI 40: the same text
;
; The fake server hands bench_data (made by tools/bench_data.py) to the
; client BENCH_READS times, each time as one read through receive.asm,
; like a real connection. CIA 2's timers count the cycles from the first
; read until the script ends, after the last bitmap update; the WiC64
; transfer itself is not part of it. tools/run_test.py reports
; bench_cycles per byte of bench_bytes.
;---------------------------------------------------------

!zone bench {
BENCH_READS = 4
CIA2_TIMER_A = $dd04
CIA2_TIMER_B = $dd06
CIA2_CONTROL_A = $dd0e
CIA2_CONTROL_B = $dd0f

test_rx:                    ; no scenario data: bench_poll reads instead
test_rx_end:
test_rx_transfers: !word test_rx_end
test_rx_holds:     !word 0

!align 255, 0
test_keys:
!if BENCH = 1 {
    !byte KEY_DOWN, "T", "T", "T"   ; server 2 -> ANSI 80
} else if BENCH = 2 {
    !text KEY_DOWN, KEY_DOWN, "T", "T", "T", "T"   ; server 3 -> UTF-8 80
} else if BENCH = 3 {
    !byte KEY_DOWN, "T", "T", "T"   ; server 2 -> ANSI 80
} else {
    !byte KEY_DOWN, "T"             ; server 2 -> ANSI
}
    !byte KEY_RETURN
    !byte TK_WAIT_RX
    !byte TK_IDLE, 5
    !byte TK_END

; net_poll: the next read, if any
bench_poll:
    lda .reads_left
    bne +
    clc
    rts
+   cmp #BENCH_READS
    bne +
    jsr .start_timers
+   dec .reads_left
    lda #<(bench_data_end - bench_data)
    ldy #>(bench_data_end - bench_data)
    jsr receive_start
    jmp receive_deliver

; Z=1 once every read has been handed on
bench_done:
    lda .reads_left
    rts

; Timer A counts cycles, timer B how often A has gone round
.start_timers:
    lda #$ff
    sta CIA2_TIMER_A
    sta CIA2_TIMER_A+1
    sta CIA2_TIMER_B
    sta CIA2_TIMER_B+1
    lda #%01010001          ; B: count A's underflows, load, start
    sta CIA2_CONTROL_B
    lda #%00010001          ; A: count cycles, load, start
    sta CIA2_CONTROL_A
    rts

bench_stop:
    lda #0
    sta CIA2_CONTROL_A
    sta CIA2_CONTROL_B
    ldx #3
-   lda CIA2_TIMER_A,x
    eor #$ff                ; counted down from $ffffffff
    sta bench_cycles,x
    dex
    bpl -
    rts

.reads_left:  !byte BENCH_READS
bench_cycles: !fill 4, 0    ; timer A, then timer B: B * 65536 + A

!if * > NET_RX_BUFFER {
    !error "The benchmark runs into NET_RX_BUFFER"
}

; The data is where a read puts it
* = NET_RX_BUFFER
bench_data:
!if BENCH <= 2 {
    !binary "build/bench_frames.bin"
} else {
    !binary "build/bench_text.bin"
}
bench_data_end:
bench_bytes = BENCH_READS * (bench_data_end - bench_data)
!if bench_data_end > $c000 {
    !error "The benchmark data does not fit in NET_RX_BUFFER"
}
}

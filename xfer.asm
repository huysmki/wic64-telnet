;---------------------------------------------------------
; File downloads: XMODEM and Punter
;
; xfer_download asks for the protocol and a file name, receives the
; file onto the drive the program was loaded from, and shows how far
; it got; RUN/STOP stops it.
;
; XMODEM is what PC BBSes (and most others) offer: 128-byte blocks
; with a checksum, or with a CRC, and 1 KB blocks (XMODEM-1K), all
; chosen by the sender once the receiver asks for CRC. XMODEM pads the
; last block with $1a, which stays in the file, as with CCGMS: XMODEM
; doesn't say where the file ends.
;
; Punter (C1) is the protocol of Commodore BBSes. It sends the file
; type (PRG, SEQ or USR) in a block of its own, then blocks of up to
; 255 bytes, each with two checksums, and both sides agree on every
; step with three-letter codes (GOO, BAD, ACK, S/B, SYN). This follows
; the variant of CCGMS, as in CGTerm's punter.c by Per Olofsson with
; Michael Steil's changes for CCGMS.
;
; All that the server sends passes xfer_watch on its way to the
; terminal, which starts receiving a file (xfer_offer, called by the
; session) when a BBS is waiting to send one:
;
; - Punter: the BBS repeats GOO until the terminal answers; three in a
;   row start it.
; - Multi-Punter: several files, each announced by a header of TABs
;   (CCGMS sends 16, Image BBS 5), the name and type (NAME,P) and RETURN,
;   repeated until the terminal starts receiving; a header that starts
;   with CTRL-D ends them. The file is saved under that name without
;   asking, and the box closes at once, ready for the next header.
;
; After a download that stopped or failed, neither starts one again until
; the server has sent something else, as the BBS keeps asking.
;
; The transfer takes the server's bytes itself (net_read_byte), passed
; through the Telnet layer only if the server speaks Telnet, and puts
; telnet_sink back when it is done.
;---------------------------------------------------------

!zone xfer {
.FILE = 2                   ; logical file and secondary address
.NAME_MAX = 16
.BOX_ROW = 20               ; rows 21-23 inside the box
.TITLE_ROW = 21
.PROGRESS_ROW = 22
.STATUS_ROW = 23

.SOH = $01
.STX = $02
.EOT = $04
.ACK = $06
.NAK = $15
.CAN = $18
.SUB = $1a
.CRC_REQUEST = $43          ; "C" in ASCII

.SECOND = 60                ; jiffies
.XMODEM = 0
.PUNTER = 1

; Passes A from the server on to the terminal, looking for a
; Multi-Punter header and for GOOGOOGOO
xfer_watch:
    sta .watched
    cmp #$09                ; TAB
    bne .not_tab
    lda .tabs
    bmi +
    inc .tabs
+   lda #0
    sta .header_length
    jmp .pass
.not_tab:
    ldx .tabs
    cpx #2
    bcc .no_header
    cmp #0                  ; NULs in between are skipped
    beq .pass
    cmp #$0d
    beq .header_end
    ldx .header_length
    cpx #.NAME_MAX + 2
    bcs .no_header          ; too long for a name
    sta .mp_header,x
    inc .header_length
    bcc .pass               ; always
.header_end:
    ldx .header_length      ; at least a letter, the comma and the type
    cpx #3
    bcc .no_header
    lda .mp_header-2,x
    cmp #","
    bne .no_header
    lda .mp_header-1,x
    ldy #2
-   cmp .type_letters,y     ; P, S or U
    beq +
    dey
    bpl -
    bmi .no_header          ; always
+   lda .mp_header
    cmp #$04                ; CTRL-D: no more files
    beq .no_header
    dex
    dex
    stx .header_name_length
    lda #0
    sta .tabs
    lda .declined
    bne .pass
    inc xfer_offered
    bne .pass               ; always
.no_header:
    lda #0
    sta .tabs
    lda .watched
    ldx .goos
    cmp .goo_goo_goo,x
    beq +
    ldx #0
    stx .declined           ; something else: may start again
    cmp .goo_goo_goo        ; a G may start GOOs
    bne ++
+   inx
    cpx #9
    bcc ++
    ldx #0
    ldy .declined
    bne ++
    inc xfer_offered
++  stx .goos
.pass:
    lda .watched
    jmp term_output

; Receives the file a BBS is waiting to send with Punter
xfer_offer:
    lda #0
    sta xfer_offered
    ldx .header_name_length ; named by a Multi-Punter header?
    stx .named
    sta .header_name_length
    sta .name,x
-   dex
    bmi +
    lda .mp_header,x
    sta .name,x
    jmp -
+   jsr .open_box
    lda #.PUNTER
    sta .protocol
    jmp .start

.open_box:
    lda #COLOR_GREEN
    ldx #.BOX_ROW
    jmp box_open

; Asks what to download and receives it.
xfer_download:
    lda #0
    sta .named
    jsr .open_box
    +plot 1, .TITLE_ROW
    +print .protocol_text
    +plot 1, .PROGRESS_ROW
    +print .protocol_choice
    jsr wait_key
    ldx #.XMODEM
    cmp #"X"
    beq +
    ldx #.PUNTER
    cmp #"P"
    beq +
    jmp box_close
+   stx .protocol
    txa
    bne .start              ; Punter: the sender says the file type
    jsr .clear_rows
    +plot 1, .TITLE_ROW
    +print .type_text
    +plot 1, .PROGRESS_ROW
    +print .type_choice
--  jsr wait_key
    ldx #2
-   cmp .type_keys,x
    beq +
    dex
    bpl -
    bmi --
+   inx
    stx .file_type

.start:
    jsr .clear_rows
    +plot 1, .TITLE_ROW
    +print .receiving_text
    lda #0
    sta .bytes
    sta .bytes+1
    sta .bytes+2
    sta .file_open
    sta .mailbox_full
    jsr .show_progress
    lda #<.stop_text
    ldy #>.stop_text
    jsr .status

    lda telnet_sink
    sta .saved_sink
    lda telnet_sink+1
    sta .saved_sink+1
    lda #<.take_from_telnet
    sta telnet_sink
    lda #>.take_from_telnet
    sta telnet_sink+1

    tsx
    stx .saved_stack
    lda .protocol
    bne +
    jsr .xmodem
    jmp .finish
+   jsr .punter
    jmp .finish

; Ends the transfer with the message at A/Y (from any depth: the
; stack is taken back to where the transfer started).
.fail:
    ldx .saved_stack
    txs
.finish:
    sta .message
    sty .message+1
    lda .saved_sink
    sta telnet_sink
    lda .saved_sink+1
    sta telnet_sink+1
    lda .file_open
    beq +
    jsr .close_file
    bcc +
    lda #<disk_status       ; the drive's error tops the message
    sta .message
    lda #>disk_status
    sta .message+1
+   lda .message+1          ; received: now it gets its name
    cmp #>.done_text
    bne .unsuccessful
    lda .message
    cmp #<.done_text
    bne .unsuccessful
    jsr .rename
    sta .message
    sty .message+1
    lda .named              ; one of several files: on to the next
    beq .show_message
    jmp box_close
.unsuccessful:
    inc .declined           ; the BBS keeps asking: wait for it to stop
.show_message:
    lda .message
    ldy .message+1
    jsr .status
    jsr wait_key
    jmp box_close

; Asks for the file's name and renames it from .temp_name, asking again
; while the drive refuses, its message above (63, FILE EXISTS). The row
; below the name stays empty: the screen editor would read it as more
; of the name. Returns A/Y = the message to show.
.rename:
    lda .named
    bne .rename_now         ; named by the sender
    lda #<.name_text
    ldy #>.name_text
.ask_name:
    sta .message
    sty .message+1
-   jsr .clear_rows
    +plot 1, .TITLE_ROW
    lda .message
    ldy .message+1
    jsr print_str
    +plot 1, .PROGRESS_ROW
    lda #0
    tay
    jsr ui_input
    cmp #0
    beq -                   ; a name it must have: the next download
    jsr .take_name          ; deletes .temp_name
.rename_now:
    ldx #0
    lda #<.rename_command
    ldy #>.rename_command
    jsr .append
    lda #<.name
    ldy #>.name
    jsr .append
    lda #<.equals_temp
    ldy #>.equals_temp
    jsr .disk_command_with
    lda #<disk_status
    ldy #>disk_status
    bcs .ask_name
    jsr .clear_rows
    lda #<.done_text
    ldy #>.done_text
    rts

; Appends the string at A/Y to .command, then sends it to the drive
; (X = its length so far). C=1 if the drive reports an error.
.disk_command_with:
    jsr .append
    txa
    ldx #<.command
    ldy #>.command
    jmp disk_command

; Appends the 0-terminated string at A/Y to .command at X
.append:
    sta .from+1
    sty .from+2
    ldy #0
.from:
-   lda $ffff,y
    beq +
    sta .command,x
    inx
    iny
    bne -
+   rts

;---------------------------------------------------------
; XMODEM
;---------------------------------------------------------

.xmodem:
    lda #1
    sta .expected
    sta .crc_mode
    lda #0
    sta .tries
    jsr .open_file

    ; Asks for CRC four times, then for a checksum
.start_xmodem:
    lda #.CRC_REQUEST
    ldx .crc_mode
    bne +
    lda #.NAK
+   jsr .send_byte
    ldx #<(3 * .SECOND)
    ldy #>(3 * .SECOND)
    jsr .get_byte
    bcc .header
    inc .tries
    lda .tries
    cmp #4
    bne +
    lda #0
    sta .crc_mode
+   lda .tries
    cmp #10
    bcc .start_xmodem
    lda #<.no_answer_text
    ldy #>.no_answer_text
    jmp .fail

.next_block:
    ldx #<(10 * .SECOND)
    ldy #>(10 * .SECOND)
    jsr .get_byte
    bcc *+5
    jmp .retry
.header:
    cmp #.EOT
    bne +
    lda #.ACK
    jsr .send_byte
    lda #<.done_text
    ldy #>.done_text
    rts
+   cmp #.CAN
    bne +
    jsr .get_second_byte
    bcc *+5
    jmp .retry
    cmp #.CAN
    beq *+5
    jmp .retry
    lda #<.cancelled_text
    ldy #>.cancelled_text
    jmp .fail
+   ldx #>128
    cmp #.SOH
    beq +
    ldx #>1024
    cmp #.STX
    beq *+5
    jmp .retry
+   stx .size+1             ; 128 ($0080) or 1024 ($0400)
    lda #0
    sta .size
    cpx #0
    bne +
    lda #128
    sta .size
+
    jsr .get_second_byte    ; block number, then its complement
    bcc *+5
    jmp .retry
    sta .block_number
    jsr .get_second_byte
    bcc *+5
    jmp .retry
    eor .block_number
    cmp #$ff
    beq *+5
    jmp .retry

    jsr .rewind_buffer
    lda #0
    sta .crc
    sta .crc+1
    sta .sum
    lda .size
    sta .count
    lda .size+1
    sta .count+1
-   jsr .get_second_byte
    bcc *+5
    jmp .retry
    jsr .store_byte
    jsr .add_to_crc
    lda .count
    bne +
    dec .count+1
+   dec .count
    lda .count
    ora .count+1
    bne -

    jsr .get_second_byte    ; CRC (high byte first) or checksum
    bcc *+5
    jmp .retry
    ldx .crc_mode
    beq .check_sum
    cmp .crc+1
    beq *+5
    jmp .retry
    jsr .get_second_byte
    bcc *+5
    jmp .retry
    cmp .crc
    beq *+5
    jmp .retry
    jmp .block_good
.check_sum:
    cmp .sum
    beq *+5
    jmp .retry

.block_good:
    lda .block_number
    cmp .expected
    beq +
    clc
    adc #1
    cmp .expected           ; the block before again: our ACK got lost
    beq .acknowledge
    jsr .send_cancel
    lda #<.lost_track_text
    ldy #>.lost_track_text
    jmp .fail
+   jsr .save_xmodem_block
    inc .expected
    lda #0
    sta .tries
    jsr .count_block
.acknowledge:
    lda #.ACK
    jsr .send_byte
    jmp .next_block

; A broken or missing block: waits until the line is quiet, then asks
; for it again.
.retry:
    inc .tries
    lda .tries
    cmp #10
    bcc +
    jsr .send_cancel
    lda #<.errors_text
    ldy #>.errors_text
    jmp .fail
+
.retry_quiet:               ; anything still coming is thrown away
    ldx #<.SECOND
    ldy #>.SECOND
    jsr .get_byte
    bcc .retry_quiet
    lda #.NAK
    jsr .send_byte
    jmp .next_block

; A = the next byte of a block, C=1 if it does not come within 1 s
.get_second_byte:
    ldx #<.SECOND
    ldy #>.SECOND
    jmp .get_byte

; Adds A to the CRC (CCITT, $1021) or the checksum, whichever is used
.add_to_crc:
    pha
    clc
    adc .sum
    sta .sum
    pla
    eor .crc+1
    sta .crc+1
    ldx #8
-   asl .crc
    rol .crc+1
    bcc +
    lda .crc+1
    eor #$10
    sta .crc+1
    lda .crc
    eor #$21
    sta .crc
+   dex
    bne -
    rts

; Writes the block to the file
.save_xmodem_block:
    jsr .select_file
    lda .size
    ldx .size+1
    jsr .write_buffer
    jmp CLRCHN

.send_cancel:
    ldx #3
-   lda #.CAN
    jsr telnet_send
    dex
    bne -
    jmp net_flush

;---------------------------------------------------------
; Punter
;---------------------------------------------------------

; First the file type block, then the file, each ended by the same
; handshake. As in CCGMS, codes are looked for in a sliding window of
; three bytes, so that stray bytes and repeated codes do no harm.
.punter:
    lda #8                  ; the file type block: one byte of data
    sta .block_size
    lda #0
    sta .saving
    jsr .punter_part
    jsr .open_file
    lda #7                  ; the file's first block has no data
    sta .block_size
    inc .saving
    jsr .punter_part
    lda #<.done_text
    ldy #>.done_text
    rts

; Receives blocks up to the last one and the handshake after it
.punter_part:
    lda #0
    sta .end_flag
    sta .tries
    lda #.goo - .codes
.punter_next:
    jsr .punter_block       ; A = the answer to the block before
    lda .end_flag
    beq +
    rts
+   jsr .block_checksums
    ldx #3
-   lda .sum,x
    cmp TRANSFER_BUFFER,x
    bne .punter_bad
    dex
    bpl -
    lda #0
    sta .tries
    lda .saving
    bne +
    lda TRANSFER_BUFFER + 7 ; 1 PRG, 2 SEQ, 3 USR
    sta .file_type
    jmp .punter_last
+   jsr .save_punter_block
    jsr .count_block
    lda TRANSFER_BUFFER + 6 ; block number $ffxx: the last one
    cmp #$ff
    bne +
.punter_last:
    inc .end_flag
+   lda TRANSFER_BUFFER + 4 ; the size of the next block
    sta .block_size
    lda #.goo - .codes
    bne .punter_next        ; always
.punter_bad:
    inc .tries
    lda .tries
    cmp #10
    bcc +
    lda #<.errors_text
    ldy #>.errors_text
    jmp .fail
+   lda #.bad - .codes
    bne .punter_next        ; always

; Answers with the code at A (GOO or BAD), and once the sender has
; acknowledged it, asks for the next block (S/B) and receives it; after
; the last block, ends the transfer instead.
.punter_block:
    sta .send_code_low
    lda #8
    sta .waits
.send_answer:
    jsr .count_wait
    lda #2
    sta .handshakes
    lda .send_code_low
    jsr .send_code
-   lda #.ack - .codes
    jsr .accept
    bcc .request_block
    dec .handshakes
    bne -
    beq .send_answer        ; always

.request_block:
    jsr .count_wait
    lda #.sb - .codes
    jsr .send_code
    lda .end_flag
    beq +
    lda .send_code_low
    cmp #.goo - .codes
    beq .punter_end
+   ldx #0
    stx .count
-   ldx #<(2 * .SECOND)
    ldy #>(2 * .SECOND)
    jsr .get_byte
    bcc +
    lda .count              ; nothing at all: ask again; part of a
    beq .request_block      ; block: its checksum fails
    rts
+   ldx .count
    sta TRANSFER_BUFFER,x
    inx
    stx .count
    cpx #3                  ; an ACK on its own instead of a block:
    bne +                   ; the sender missed our S/B
    lda #.ack - .codes
    jsr .window_holds_code_buffer
    bne +
    ldx #3
    ldy #0
    jsr .get_byte
    bcs .request_block
    ldx .count
    sta TRANSFER_BUFFER,x
    inc .count
+   ldx .count
    cpx .block_size
    bcc -
    rts

.punter_end:
    lda #.syn - .codes
    jsr .accept
    bcs .request_block      ; no SYN yet: S/B again
    lda #10
    sta .handshakes
-   lda #.syn - .codes
    jsr .send_code
    lda #.sb - .codes
    jsr .accept
    bcc +
    dec .handshakes
    bne -
+   rts

; Gives up after .waits tries
.count_wait:
    dec .waits
    bne +
    lda #<.no_answer_text
    ldy #>.no_answer_text
    jmp .fail
+   rts

; Waits for the code at A, ignoring other bytes. C=1 if it does not
; come: no byte for three seconds, or 24 other bytes (a sender that
; keeps repeating its code may read ours out of step, and only gets
; back in step once we pause).
.accept:
    sta .wait_code_low
    lda #0
    sta .window
    sta .window+1
    lda #24
    sta .accept_left
-   ldx #<(3 * .SECOND)
    ldy #>(3 * .SECOND)
    jsr .get_byte
    bcs ++
.accept_byte:
    dec .accept_left
    sec
    beq ++
    ldx .window+1
    stx .window
    ldx .window+2
    stx .window+1
    sta .window+2
    ldy .wait_code_low
    ldx #0
--  lda .codes,y
    cmp .window,x
    bne -
    iny
    inx
    cpx #3
    bne --
    ldx #3                  ; the code: done once the line is quiet
    ldy #0
    jsr .get_byte
    bcc .accept_byte
    clc
++  rts

; Z=1 if TRANSFER_BUFFER starts with the code at A (offset in .codes)
.window_holds_code_buffer:
    tay
    ldx #0
-   lda .codes,y
    cmp TRANSFER_BUFFER,x
    bne +
    iny
    inx
    cpx #3
    bne -
+   rts

; .sum = additive checksum, .clc = cyclic one, of block bytes 4 on
.block_checksums:
    lda #0
    sta .sum
    sta .sum+1
    sta .clc
    sta .clc+1
    ldx #4
-   lda TRANSFER_BUFFER,x
    clc
    adc .sum
    sta .sum
    bcc +
    inc .sum+1
+   lda TRANSFER_BUFFER,x
    eor .clc
    sta .clc
    asl .clc                ; rotated left by one, bit 15 into bit 0
    rol .clc+1
    lda .clc
    adc #0
    sta .clc
    inx
    cpx .block_size
    bne -
    rts

.save_punter_block:
    lda .block_size
    sec
    sbc #7
    beq +
    pha
    jsr .select_file
    lda #<(TRANSFER_BUFFER + 7)
    sta .load+1
    lda #>(TRANSFER_BUFFER + 7)
    sta .load+2
    pla
    ldx #0
    jsr .write_bytes
    jmp CLRCHN
+   rts

; Sends the code at A (its offset in .codes)
.send_code:
    tay
    ldx #3
-   lda .codes,y
    jsr telnet_send
    iny
    dex
    bne -
    jmp net_flush

;---------------------------------------------------------
; Receiving and sending
;---------------------------------------------------------

; Returns the server's next byte in A with C=0, or C=1 if none comes
; within X/Y jiffies. RUN/STOP ends the transfer. Changes X and Y.
.get_byte:
    jsr .now
    txa
    clc
    adc .jiffies
    sta .deadline
    tya
    adc .jiffies+1
    sta .deadline+1
.wait_for_byte:
    jsr STOP
    bne +
    jmp .stopped
+   jsr net_read_byte
    bcs .nothing_yet
    ldx telnet_negotiated
    bne +
    rts                     ; C=0: a server without Telnet
+   jsr telnet_receive      ; Telnet commands are answered and
    lda .mailbox_full       ; dropped; data lands in .mailbox
    beq .wait_for_byte
    lda #0
    sta .mailbox_full
    lda .mailbox
    clc
    rts
.nothing_yet:
    jsr .now
    lda .jiffies
    cmp .deadline
    lda .jiffies+1
    sbc .deadline+1
    bmi .wait_for_byte
    sec
    rts

; .jiffies = the low 16 bits of the jiffy clock
.now:
    sei
    lda JIFFY_LO
    sta .jiffies
    lda JIFFY_MID
    sta .jiffies+1
    cli
    rts

; telnet_sink during a transfer
.take_from_telnet:
    sta .mailbox
    lda #1
    sta .mailbox_full
    rts

.send_byte:
    jsr telnet_send
    jmp net_flush

.stopped:
    lda .protocol
    bne +
    jsr .send_cancel
+   lda #<.stopped_text
    ldy #>.stopped_text
    jmp .fail

;---------------------------------------------------------
; The file
;---------------------------------------------------------

; Takes the name typed into INPUT_BUFFER (A = its length)
.take_name:
    cmp #.NAME_MAX + 1
    bcc +
    lda #.NAME_MAX
+   tax
    lda #0
    sta .name,x
-   dex
    bmi +
    lda INPUT_BUFFER,x
    sta .name,x
    jmp -
+   rts

; Opens .name as .file_type (1 PRG, 2 SEQ, 3 USR) for writing, and
; the drive's command channel, which stays open while the file is (see
; book.asm)
.open_file:
    ldx #0                  ; what a download before may have left
    lda #<.scratch_command
    ldy #>.scratch_command
    jsr .append
    lda #<.temp_name
    ldy #>.temp_name
    jsr .disk_command_with
    jsr disk_open_command_channel
    bcs .no_drive
    ldx #0
-   lda .temp_name,x
    beq +
    sta .open_name,x
    inx
    bne -
+   lda #","
    sta .open_name,x
    ldy .file_type
    dey
    cpy #3
    bcc +
    ldy #0                  ; an unknown type from the sender: PRG
+   lda .type_letters,y
    sta .open_name+1,x
    lda #","
    sta .open_name+2,x
    lda #"W"
    sta .open_name+3,x
    txa
    clc
    adc #4
    ldx #<.open_name
    ldy #>.open_name
    jsr SETNAM
    lda #.FILE
    ldx disk_device
    ldy #.FILE
    jsr SETLFS
    jsr OPEN
    bcs .no_drive
    lda #1
    sta .file_open
    jsr disk_read_open_status
    bcs .disk_error
    rts
.no_drive:
    jsr .close_both         ; KERNAL keeps a file that failed to open
    lda #<.no_drive_text
    ldy #>.no_drive_text
    jmp .fail_open
.disk_error:
    jsr .close_both
    lda #<disk_status
    ldy #>disk_status
.fail_open:
    ldx .protocol
    bne +
    pha
    tya
    pha
    jsr .send_cancel
    pla
    tay
    pla
+   jmp .fail

; Closes the file and the command channel without asking the drive
.close_both:
    lda #.FILE
    jsr CLOSE
    lda #15
    jsr CLOSE
    lda #0
    sta .file_open
    rts

; Closes the file and the command channel. C=1 if the drive reports
; an error.
.close_file:
    lda #.FILE
    jsr CLOSE
    lda #0
    sta .file_open
    jsr disk_read_open_status
    php
    lda #15
    jsr CLOSE
    plp
    rts

.select_file:
    ldx #.FILE
    jmp CHKOUT

; Writes X/A bytes from the start of TRANSFER_BUFFER
.write_buffer:
    pha
    lda #<TRANSFER_BUFFER
    sta .load+1
    lda #>TRANSFER_BUFFER
    sta .load+2
    pla

; Writes X/A bytes from .load on (A = low byte, X = high byte)
.write_bytes:
    sta .left
    stx .left+1
-   lda .left
    ora .left+1
    beq +
.load:
    lda $ffff
    jsr CHROUT
    inc .load+1
    bne ++
    inc .load+2
++  lda .left
    bne ++
    dec .left+1
++  dec .left
    jmp -
+   rts

.rewind_buffer:
    lda #<TRANSFER_BUFFER
    sta .store+1
    lda #>TRANSFER_BUFFER
    sta .store+2
    rts

.store_byte:
.store:
    sta $ffff
    inc .store+1
    bne +
    inc .store+2
+   rts

;---------------------------------------------------------
; Screen
;---------------------------------------------------------

; Counts a block saved: .size bytes for XMODEM, .block_size - 7 for
; Punter
.count_block:
    lda .protocol
    bne +
    lda .size
    ldx .size+1
    jmp ++
+   lda .block_size
    sec
    sbc #7
    ldx #0
++  clc
    adc .bytes
    sta .bytes
    txa
    adc .bytes+1
    sta .bytes+1
    bcc .show_progress
    inc .bytes+2

.show_progress:
    +plot 1, .PROGRESS_ROW
    lda #<.received_text
    ldy #>.received_text
    jsr print_str
    lda .bytes
    sta print_number_value
    lda .bytes+1
    sta print_number_value+1
    lda .bytes+2
    sta print_number_value+2
    ldx #8
    jsr print_number
    lda #<.bytes_text
    ldy #>.bytes_text
    jmp print_str

; Prints the message at A/Y in the status row
.status:
    pha
    tya
    pha
    +plot 1, .STATUS_ROW
    pla
    tay
    pla
    ldx #38
    jmp print_field

.clear_rows:
    ldx #.TITLE_ROW
-   stx .row
    ldy #1
    clc
    jsr PLOT
    lda #<.empty_text
    ldy #>.empty_text
    ldx #38
    jsr print_field
    ldx .row
    inx
    cpx #.STATUS_ROW + 1
    bne -
    rts

;---------------------------------------------------------
; Data
;---------------------------------------------------------

.goo_goo_goo:    !text "GOOGOOGOO"
xfer_offered:    !byte 0    ; 1: the session calls xfer_offer
.goos:           !byte 0    ; how much of GOOGOOGOO came so far
.declined:       !byte 0
.watched:        !byte 0
.tabs:           !byte 0    ; TABs in a row, up to 128
.mp_header:      !fill .NAME_MAX + 2, 0 ; NAME,T of a Multi-Punter header
.header_length:  !byte 0
.header_name_length: !byte 0 ; of the name for the next file, or 0

.codes:                     ; Punter codes, by their offset here; none
    !byte 0                 ; at 0 (0: no code)
.goo:     !text "GOO"
.bad:     !text "BAD"
.ack:     !text "ACK"
.sb:      !text "S/B"
.syn:     !text "SYN"

.type_keys:    !byte "P", "S", "U"
.type_letters: !byte "P", "S", "U"

.protocol_text:   !pet "Download with", 0
.protocol_choice: !pet PET_WHITE, "X", PET_GREEN, " XMODEM   "
                  !pet PET_WHITE, "P", PET_GREEN, " Punter (Commodore)", 0
.name_text:       !pet "File name:", 0
.scratch_command: !pet "s0:", 0
.rename_command:  !pet "r0:", 0
.equals_temp:     !pet "="
.temp_name:       !pet "download.tmp", 0
.type_text:       !pet "File type:", 0
.type_choice:     !pet PET_WHITE, "P", PET_GREEN, " PRG   "
                  !pet PET_WHITE, "S", PET_GREEN, " SEQ   "
                  !pet PET_WHITE, "U", PET_GREEN, " USR", 0
.receiving_text:  !pet "Receiving", 0
.stop_text:       !pet "RUN/STOP stops", 0
.received_text:   !pet "Received", 0
.bytes_text:      !pet " bytes", 0
.done_text:       !pet "Done", 0
.stopped_text:    !pet "Stopped", 0
.cancelled_text:  !pet "Cancelled", 0
.no_answer_text:  !pet "No answer", 0
.errors_text:     !pet "Too many errors", 0
.lost_track_text: !pet "Blocks out of order", 0
.no_drive_text:   !pet "No disk drive", 0
.empty_text:      !byte 0

; Variables, in the cassette buffer (see defs.asm). .sum and .clc are
; compared with a Punter block header together.
!set .v = XFER_VARIABLES
.protocol = .v : !set .v = .v + 1
.file_type = .v : !set .v = .v + 1
.file_open = .v : !set .v = .v + 1
.name = .v : !set .v = .v + 17
.open_name = .v : !set .v = .v + 20
.command = .v : !set .v = .v + 3 + 16 + 14
.saved_sink = .v : !set .v = .v + 2
.saved_stack = .v : !set .v = .v + 1
.message = .v : !set .v = .v + 2
.mailbox = .v : !set .v = .v + 1
.mailbox_full = .v : !set .v = .v + 1
.jiffies = .v : !set .v = .v + 2
.deadline = .v : !set .v = .v + 2
.bytes = .v : !set .v = .v + 3
.row = .v : !set .v = .v + 1
.tries = .v : !set .v = .v + 1
.count = .v : !set .v = .v + 2
.left = .v : !set .v = .v + 2
.size = .v : !set .v = .v + 2
.expected = .v : !set .v = .v + 1
.block_number = .v : !set .v = .v + 1
.crc_mode = .v : !set .v = .v + 1
.crc = .v : !set .v = .v + 2
.sum = .v : !set .v = .v + 2
.clc = .v : !set .v = .v + 2
.saving = .v : !set .v = .v + 1
.block_size = .v : !set .v = .v + 1
.handshakes = .v : !set .v = .v + 1
.waits = .v : !set .v = .v + 1
.send_code_low = .v : !set .v = .v + 1
.wait_code_low = .v : !set .v = .v + 1
.end_flag = .v : !set .v = .v + 1
.named = .v : !set .v = .v + 1
.window = .v : !set .v = .v + 3
.accept_left = .v : !set .v = .v + 1
!if .v > XFER_VARIABLES_END {
    !error "The file transfer variables do not fit"
}
}

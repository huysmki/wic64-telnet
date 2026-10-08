;---------------------------------------------------------
; Address book: the start screen
;
; Lists up to 16 servers, each with the terminal mode to use, lets
; the user pick, add, edit, delete and re-type them, and keeps the
; list in the file "telnet.cfg" on the disk drive the program was
; loaded from (device 8 if none). The file is read at start-up and
; written when the user presses S.
;---------------------------------------------------------

BOOK_ENTRY_SIZE = 40        ; host, 0-terminated, then the mode
BOOK_ENTRY_MODE = BOOK_ENTRY_SIZE - 1

!macro book_entry .host, .mode {
    .start = *
    !pet .host
    !fill BOOK_ENTRY_MODE - (* - .start), 0
    !byte .mode
}

!zone book {
.MAX_ENTRIES = 16
.HOST_MAX = 38
!if .HOST_MAX + 1 > 39 {
    !error "book_open_host has room for 39 bytes"
}
.ENTRY_SIZE = BOOK_ENTRY_SIZE
.ENTRY_MODE = BOOK_ENTRY_MODE
.FIRST_ROW = 2
.MESSAGE_ROW = 18
.HOST_COLUMNS = 27
.BOX_COLOR = COLOR_GREEN

; Loads the saved address book, if there is one.
book_init:
    lda LAST_DEVICE
    cmp #8
    bcc +
    cmp #31
    bcc ++
+   lda #8
++  sta disk_device
    lda #0
    jsr SETMSG              ; no KERNAL "SEARCHING/LOADING" messages

    lda #.filename_length
    ldx #<.filename
    ldy #>.filename
    jsr SETNAM
    lda #1
    ldx disk_device
    ldy #0                  ; load to the address given below
    jsr SETLFS
    lda #0
    ldx #<book_load_buffer
    ldy #>book_load_buffer
    jsr LOAD
    bcs .load_done
    cpx #<(book_load_buffer + .FILE_SIZE)
    bne .load_done
    cpy #>(book_load_buffer + .FILE_SIZE)
    bne .load_done
    ldx #.MAGIC_LENGTH-1
-   lda book_load_buffer,x
    cmp .file,x
    bne .load_done
    dex
    bpl -
    lda book_load_buffer + (.count - .file)
    cmp #.MAX_ENTRIES+1
    bcs .load_done

    ldx #0                  ; copy exactly .FILE_SIZE bytes:
-   lda book_load_buffer,x  ; two full pages...
    sta .file,x
    lda book_load_buffer + $100,x
    sta .file + $100,x
    inx
    bne -
    ldx #.FILE_SIZE - $200  ; ...and the rest
-   lda book_load_buffer + $1ff,x
    sta .file + $1ff,x
    dex
    bne -
.load_done:
    rts

; Runs the start screen until the user picks a server.
; Returns C=0 with A/Y = "host:port" and X = terminal mode to connect,
; or C=1 to go to the WiC64 portal.
book_menu:
    jsr .draw
.key:
    jsr wait_key
    ldx #.KEY_COUNT-1
-   cmp .keys,x
    beq +
    dex
    bpl -
    cmp #"1"
    bcc .key
    cmp #$3a                ; after 9
    bcs .key
    sbc #$30                ; carry is clear: subtracts "1"
    cmp .count
    bcs .key
    sta .selected
    jmp .connect_selected
+   lda .handlers_hi,x
    pha
    lda .handlers_lo,x
    pha
    rts

.KEY_COUNT = 11
.keys:
    !byte KEY_DOWN, KEY_UP, KEY_RETURN, "N", "E", "D", "T", "S", "O"
    !byte KEY_ARROW_LEFT, KEY_HOME
.handlers_lo:
    !byte <(.down-1), <(.up-1), <(.connect_selected-1), <(.new-1), <(.edit-1)
    !byte <(.delete-1), <(.next_type-1), <(.save-1), <(.open-1)
    !byte <(.portal-1), <(.top-1)
.handlers_hi:
    !byte >(.down-1), >(.up-1), >(.connect_selected-1), >(.new-1), >(.edit-1)
    !byte >(.delete-1), >(.next_type-1), >(.save-1), >(.open-1)
    !byte >(.portal-1), >(.top-1)

.down:
    ldx .selected
    inx
    cpx .count
    bcs +
    stx .selected
    jsr .draw_entries
+   jmp .key

.up:
    ldx .selected
    beq +
    dex
    stx .selected
    jsr .draw_entries
+   jmp .key

.top:
    lda #0
    sta .selected
    jsr .draw_entries
    jmp .key

.connect_selected:
    lda .count
    beq .key_again
    ldx .selected
    jsr .entry_address
    ldy #.ENTRY_MODE
    lda (zp_a),y
    tax
    lda zp_a
    ldy zp_a+1
    clc
    rts

.portal:
    sec
    rts

.open:
    lda #0
    tay
    jsr .ask_host
    bcs .key_again
    jsr .take_host
    lda #<book_open_host
    ldy #>book_open_host
    ldx #TERM_PETSCII
    clc
    rts

.new:
    lda .count
    cmp #.MAX_ENTRIES
    bcc +
    lda #<.full_message
    ldy #>.full_message
    jmp .show_message
+   lda #0
    tay
    jsr .ask_host
    bcs .key_again
    ldx .count
    stx .selected
    inc .count
    jsr .store_host
    lda #TERM_PETSCII
    sta (zp_a),y
    jmp .changed

.edit:
    lda .count
    beq .key_again
    ldx .selected
    jsr .entry_address
    lda zp_a
    ldy zp_a+1
    jsr .ask_host
    bcs .key_again
    ldx .selected
    jsr .store_host
    jmp .changed

.key_again:
    jmp .key

.delete:
    lda .count
    beq .key_again
    lda #.BOX_COLOR
    ldx #20
    jsr box_open
    +plot 1, 22
    +print .delete_prompt
    ldx .selected
    jsr .entry_address
    lda zp_a
    ldy zp_a+1
    ldx #22
    jsr print_field
    +print .yes_no
    jsr wait_key
    pha
    jsr box_close
    pla
    cmp #"Y"
    beq +
    jmp .key
+

    ; move the following entries up
    ldx .selected
    jsr .entry_address
    lda zp_a
    clc
    adc #.ENTRY_SIZE
    sta zp_b
    lda zp_a+1
    adc #0
    sta zp_b+1
    lda .count
    sec
    sbc .selected
    tax
    dex                     ; entries after the selected one
    beq .deleted
--  ldy #.ENTRY_SIZE-1
-   lda (zp_b),y
    sta (zp_a),y
    dey
    bpl -
    lda zp_b
    sta zp_a
    clc
    adc #.ENTRY_SIZE
    sta zp_b
    lda zp_b+1
    sta zp_a+1
    adc #0
    sta zp_b+1
    dex
    bne --
.deleted:
    dec .count
    lda .selected           ; keep the selection on an existing entry
    cmp .count
    bcc +
    lda .count
    beq +
    dec .selected
+   jmp .changed

.next_type:
    lda .count
    bne +
    jmp .key
+
    ldx .selected
    jsr .entry_address
    ldy #.ENTRY_MODE
    lda (zp_a),y
    clc
    adc #1
    cmp #TERM_MODES
    bcc +
    lda #0
+   sta (zp_a),y
    jmp .changed

.changed:
    lda #<.unsaved_message
    ldy #>.unsaved_message
.show_message:
    sta .message
    sty .message+1
    jsr .draw
    jmp .key

.save:
    lda #<.saving_message
    ldy #>.saving_message
    sta .message
    sty .message+1
    jsr .draw_message
    jsr .write_file
    sta .message
    sty .message+1
    jsr .draw_message
    jmp .key

;---------------------------------------------------------

; X = entry index; points zp_a at the entry.
.entry_address:
    lda #0
    sta zp_a+1
    txa
    asl                     ; * 8
    asl
    asl
    sta zp_a
    asl                     ; * 32
    asl
    rol zp_a+1
    clc
    adc zp_a                ; * 40
    sta zp_a
    lda zp_a+1
    adc #>.entries
    sta zp_a+1
    lda zp_a
    clc
    adc #<.entries
    sta zp_a
    bcc +
    inc zp_a+1
+   rts

; Asks for a host with the default text at A/Y (A = Y = 0 for none).
; Returns C=1 if the user entered nothing.
.ask_host:
    pha
    tya
    pha
    lda #.BOX_COLOR
    ldx #20
    jsr box_open
    +plot 1, 21
    +print .host_prompt
    +plot 1, 22
    pla
    tay
    pla
    jsr ui_input
    pha
    jsr box_close
    pla
    bne +
    sec
    rts
+   clc
    rts

; Copies the input line into entry X without leading spaces, cut to
; .HOST_MAX characters. Leaves zp_a on the entry and Y on its mode.
.store_host:
    jsr .entry_address
    jsr .skip_spaces
    ldy #0
-   lda INPUT_BUFFER,x
    beq +
    sta (zp_a),y
    inx
    iny
    cpy #.HOST_MAX
    bcc -
+   lda #0
-   sta (zp_a),y
    iny
    cpy #.ENTRY_MODE
    bcc -
    rts

; Copies the input line to book_open_host like .store_host does.
.take_host:
    jsr .skip_spaces
    ldy #0
-   lda INPUT_BUFFER,x
    sta book_open_host,y
    beq +
    inx
    iny
    cpy #.HOST_MAX
    bcc -
    lda #0
    sta book_open_host,y
+   rts

; Returns X = index of the first non-blank character of the input.
.skip_spaces:
    ldx #0
-   lda INPUT_BUFFER,x
    cmp #" "
    bne +
    inx
    bne -
+   rts

;---------------------------------------------------------
; Drawing
;---------------------------------------------------------

.draw:
    jsr ui_screen_menu
    +print .title
    jsr .draw_entries
    +plot 0, 19
    +print .help
    jmp .draw_message

.draw_entries:
    lda .count
    bne +
    +plot 3, .FIRST_ROW + 1
    +print .empty_message
    rts
+   ldx #0
.draw_entry:
    stx .index
    txa
    clc
    adc #.FIRST_ROW
    tax
    ldy #0
    clc
    jsr PLOT
    lda #PET_GREEN
    jsr CHROUT
    ldx .index
    cpx .selected
    bne +
    lda #PET_RVS_ON
    jsr CHROUT
    lda #PET_WHITE
    jsr CHROUT
+   lda .index
    cmp #9
    bcs +
    lda #" "
    jsr CHROUT
+   lda .index
    clc
    adc #1
    jsr print_dec
    lda #" "
    jsr CHROUT
    ldx .index
    jsr .entry_address
    lda zp_a
    ldy zp_a+1
    ldx #.HOST_COLUMNS
    jsr print_field
    lda #" "
    jsr CHROUT
    ldy #.ENTRY_MODE
    lda (zp_a),y
    jsr term_mode_name
    ldx #8
    jsr print_field
    lda #PET_RVS_OFF
    jsr CHROUT
    ldx .index
    inx
    cpx .count
    bcc .draw_entry
    rts

.draw_message:
    +plot 0, .MESSAGE_ROW
    lda #PET_GREY
    jsr CHROUT
    lda .message
    ldy .message+1
    ldx #39
    jmp print_field

;---------------------------------------------------------
; Disk
;---------------------------------------------------------

; Replaces "telnet.cfg" on disk with the current list. The list is
; written to "telnet.tmp" first and only renamed once it is on disk
; completely, so a failed save leaves the old file alone.
; Returns A/Y = message describing the result.
.write_file:
    lda #.scratch_tmp_length ; left over from an earlier failed save
    ldx #<.scratch_tmp
    ldy #>.scratch_tmp
    jsr disk_command
    bcs .disk_failed

    lda #.tmp_filename_length
    ldx #<.tmp_filename
    ldy #>.tmp_filename
    jsr SETNAM
    lda #1
    ldx disk_device
    ldy #0
    jsr SETLFS
    lda #<.file
    sta zp_a
    lda #>.file
    sta zp_a+1
    lda #zp_a
    ldx #<.file_end
    ldy #>.file_end
    jsr SAVE
    bcs .kernal_error
    jsr disk_read_status
    bcs .drive_error_message

    lda #.scratch_length
    ldx #<.scratch
    ldy #>.scratch
    jsr disk_command
    bcs .disk_failed
    lda #.rename_length
    ldx #<.rename
    ldy #>.rename
    jsr disk_command
    bcs .disk_failed
    lda #<.saved_message
    ldy #>.saved_message
    rts

.disk_failed:
    bne .drive_error_message
.kernal_error:
    cmp #5
    bne +
    lda #<.no_drive_message
    ldy #>.no_drive_message
    rts
+
.unknown_disk_error:
    lda #<.disk_error_message
    ldy #>.disk_error_message
    rts

.drive_error_message:
    lda disk_status
    beq .unknown_disk_error
    lda #<disk_status
    ldy #>disk_status
    rts

; Sends the DOS command at X/Y (length A) and reads the drive status
; (also for file transfers).
; Returns C=1 on failure: Z=1 if the drive could not be reached
; (A = KERNAL error), Z=0 if it reported an error.
disk_command:
    jsr SETNAM
    lda #15
    ldx disk_device
    ldy #15
    jsr SETLFS
    jsr OPEN
    php
    pha
    lda #15
    jsr CLOSE
    pla
    plp
    bcs .command_failed
    jsr disk_read_status
    lda #1                  ; Z=0: the drive reported the error
    rts
.command_failed:
    ldx #0                  ; Z=1: A = KERNAL error
    rts

; Reads the drive's status message into disk_status (0-terminated,
; empty if the drive could not be reached). Returns C=1 if it reports
; an error. Also used by file transfers.
disk_read_status:
    jsr disk_open_command_channel
    bcs .status_failed
    jsr disk_read_open_status
    php
    lda #15
    jsr CLOSE
    plp
    rts

; Opens the drive's command channel as logical file 15. C=1 if the
; drive could not be reached.
disk_open_command_channel:
    lda #0
    jsr SETNAM
    lda #15
    ldx disk_device
    ldy #15
    jsr SETLFS
    jmp OPEN

; The same as disk_read_status, from the command channel opened with
; disk_open_command_channel. While another file on the drive is open,
; the channel must stay open: closing it closes all of the drive's files.
disk_read_open_status:
    ldx #15
    jsr CHKIN
    bcs .status_failed
    ldy #0
-   jsr CHRIN
    cmp #$0d
    beq +
    sta disk_status,y
    iny
    jsr READST
    bne +
    cpy #39
    bcc -
+   lda #0
    sta disk_status,y
    jsr CLRCHN
    ; "00" is OK, "01" follows a scratch, anything from "20" is an error
    lda disk_status
    cmp #"2"
    rts

.status_failed:
    jsr CLRCHN
    lda #15
    jsr CLOSE
    lda #0                  ; no status text
    sta disk_status
    sec
    rts

;---------------------------------------------------------
; Data
;---------------------------------------------------------

disk_device: !byte 8         ; the drive the program was loaded from
.selected: !byte 0
.index:    !byte 0
.message:  !word .empty_text

; The saved file: magic, entry count, entries
.file:
    !text "WTB1"
.MAGIC_LENGTH = * - .file
.count: !byte 9
.entries:
    +book_entry "8bit.hoyvision.com:6502", TERM_PETSCII
    +book_entry "particlesbbs.dyndns.org:6400", TERM_PETSCII
    +book_entry "cottonwoodbbs.dyndns.org:6502", TERM_PETSCII
    +book_entry "rapidfire.hopto.org:64128", TERM_PETSCII
    +book_entry "raveolution.hopto.org:64128", TERM_PETSCII
    +book_entry "bbs.fozztexx.com:23", TERM_PETSCII
    +book_entry "bbs.retrocampus.com:6510", TERM_PETSCII
    +book_entry "vert.synchro.net:23", TERM_ANSI
    +book_entry "telehack.com:23", TERM_UTF8_80
    !fill (.MAX_ENTRIES - 9) * .ENTRY_SIZE, 0
.file_end:
.FILE_SIZE = .file_end - .file
!if .FILE_SIZE <= $200 | .FILE_SIZE > $2ff {
    !error "book_init copies the file in two pages plus a remainder"
}

.filename: !pet "telnet.cfg"
.filename_length = * - .filename
.tmp_filename: !pet "telnet.tmp"
.tmp_filename_length = * - .tmp_filename
.scratch:  !pet "s0:telnet.cfg"
.scratch_length = * - .scratch
.scratch_tmp: !pet "s0:telnet.tmp"
.scratch_tmp_length = * - .scratch_tmp
.rename:   !pet "r0:telnet.cfg=telnet.tmp"
.rename_length = * - .rename


.title:
    !pet PET_RVS_ON, PET_LIGHT_GREEN
    !pet "        WiC64 Telnet Client 3.2        ", PET_RVS_OFF, 0
.help:
    !pet PET_WHITE, "RETURN", PET_GREEN, "/", PET_WHITE, "1-9", PET_GREEN, " connect  "
    !pet PET_WHITE, "CRSR", PET_GREEN, " select", 13
    !pet PET_WHITE, "N", PET_GREEN, "ew ", PET_WHITE, "E", PET_GREEN, "dit "
    !pet PET_WHITE, "D", PET_GREEN, "elete ", PET_WHITE, "T", PET_GREEN, "ype "
    !pet PET_WHITE, "S", PET_GREEN, "ave to disk", 13
    !pet PET_WHITE, "O", PET_GREEN, "pen other host  "
    !pet PET_WHITE, "_", PET_GREEN, " WiC64 portal", 13, 13
    !pet "Online: ", PET_WHITE, "F1", PET_GREEN, " hang up  "
    !pet PET_WHITE, "F3", PET_GREEN, " type a line", 13
    !pet "        ", PET_WHITE, "F5", PET_GREEN, " echo     "
    !pet PET_WHITE, "F7", PET_GREEN, " menu", 0
.empty_message:   !pet "No servers yet. Press N to add one.", 0
.host_prompt:     !pet "Server as host:port, e.g. bbs.org:23", 0
.delete_prompt:   !pet "Delete ", PET_WHITE, 0
.yes_no:          !pet PET_GREEN, "? (Y/N)", 0
.full_message:    !pet "The list is full (16 servers).", 0
.unsaved_message: !pet "Changed. Press S to save to disk.", 0
.saving_message:  !pet "Saving...", 0
.saved_message:   !pet "Saved.", 0
.no_drive_message:   !pet "No disk drive found.", 0
.disk_error_message: !pet "Disk error.", 0
.empty_text:      !byte 0
}

;---------------------------------------------------------
; Address book: the start screen
;
; Lists up to 16 servers, each with a name, the terminal mode to use,
; its host and a login (user name and password, which a session sends
; on F4 and F6), lets the user pick, add, edit, delete and re-type
; them, and keeps the list in the file "telnet.cfg" on the disk drive
; the program was loaded from (device 8 if none). The file is read at
; start-up and written when the user presses S; files from older
; versions, without names (3.2 and older) or logins, are read too.
;
; The list is kept in BOOK_STORE, in the RAM under the I/O area, as a
; session needs the rest of the memory; the start screen works on a
; copy at BOOK_LIST.
;---------------------------------------------------------

BOOK_ENTRY_SIZE = 100       ; host, 0-terminated, the mode, then the
BOOK_ENTRY_MODE = 39        ; name, user name and password,
BOOK_ENTRY_NAME = 40        ; 0-terminated (each may be empty)
BOOK_ENTRY_USER = 60
BOOK_ENTRY_PASSWORD = 80

!macro book_entry .host, .mode, .name {
    .start = *
    !pet .host
    !fill BOOK_ENTRY_MODE - (* - .start), 0
    !byte .mode
    !pet .name
    !fill BOOK_ENTRY_SIZE - (* - .start), 0
}

!zone book {
.MAX_ENTRIES = 16
.HOST_MAX = 38
.FIELD_MAX = 19            ; name, user name, password
!if .HOST_MAX + 1 > 39 {
    !error "book_open_host has room for 39 bytes"
}
.ENTRY_SIZE = BOOK_ENTRY_SIZE
.ENTRY_MODE = BOOK_ENTRY_MODE
.FIRST_ROW = 2
.MESSAGE_ROW = 18
.LABEL_COLUMNS = 27
.BOX_COLOR = COLOR_GREEN

; The file, as it is at BOOK_LIST: magic, entry count, entries
.MAGIC_LENGTH = 4
.count   = BOOK_LIST + .MAGIC_LENGTH
.entries = .count + 1
.FILE_SIZE = .entries + .MAX_ENTRIES * .ENTRY_SIZE - BOOK_LIST
.file_end = BOOK_LIST + .FILE_SIZE
.PAGES = (.FILE_SIZE + $ff) >> 8
BOOK_FILE_SIZE = .FILE_SIZE
; The name to load and save the list as, 0-terminated: right after it,
; so that it is kept and fetched with it
book_file_name = BOOK_LIST + .FILE_SIZE
BOOK_FILE_NAME_MAX = 16
!if .FILE_SIZE + BOOK_FILE_NAME_MAX + 1 > .PAGES * $100 {
    !error "The file name doesn't fit after the list"
}
; Older files: entries as the first 40 bytes now (before names) or the
; first 60 (before logins)
.VERSIONS = 3

; Loads the saved address book, if there is one.
; The drive is the one the program was loaded from, or drive 8
; (disk_tools.asm's drive_init, in the overlay).
book_init:
    jsr .fetch
    jmp drive_init

; Loads the file named with SETNAM (disk_tools.asm's file_name) from
; disk_device into the list. Returns C=0 if it was there.
book_load:
    lda #0
    jsr SETMSG              ; no KERNAL "SEARCHING/LOADING" messages
    lda #1
    ldx disk_device
    ldy #0                  ; load to the address given below
    jsr SETLFS
    lda #0
    ldx #<book_load_buffer
    ldy #>book_load_buffer
    jsr LOAD
    bcs .load_done
    stx .loaded_end
    sty .loaded_end+1
    ldx #.MAGIC_LENGTH-2    ; "WTB", then the version
-   lda book_load_buffer,x
    cmp .magic,x
    bne .load_done
    dex
    bpl -
    ldx #.VERSIONS-1        ; WTB1, WTB2 or WTB3
-   lda book_load_buffer + .MAGIC_LENGTH-1
    cmp .versions,x
    beq +
    dex
    bpl -
    bmi .load_done          ; always
+   lda .loaded_end
    cmp .file_ends_lo,x
    bne .load_done
    lda .loaded_end+1
    cmp .file_ends_hi,x
    bne .load_done
    lda book_load_buffer + .MAGIC_LENGTH
    cmp #.MAX_ENTRIES+1
    bcs .load_done
    lda .entry_sizes,x
    sta .loaded_entry_size
    jmp .convert
.load_done:
    sec
    rts

; Puts the loaded file into the list, entry by entry, and keeps it.
.convert:
    lda #<BOOK_LIST         ; an empty list (exactly: the file name is
    sta zp_a                ; after it)...
    lda #>BOOK_LIST
    sta zp_a+1
    ldx #.FILE_SIZE >> 8
    lda #0
    tay
-   sta (zp_a),y
    iny
    bne -
    inc zp_a+1
    dex
    bne -
    ldy #(.FILE_SIZE & $ff) - 1
-   sta (zp_a),y
    dey
    bpl -
!if (.FILE_SIZE & $ff) = 0 | (.FILE_SIZE & $ff) > $80 {
    !error "The list's last page doesn't suit the loop above"
}
    ldx #.MAGIC_LENGTH-1
-   lda .magic,x
    sta BOOK_LIST,x
    dex
    bpl -
    lda book_load_buffer + .MAGIC_LENGTH
    sta .count
    lda #<(book_load_buffer + .MAGIC_LENGTH + 1)
    sta zp_a                ; ...and the entries copied into it
    lda #>(book_load_buffer + .MAGIC_LENGTH + 1)
    sta zp_a+1
    lda #<.entries
    sta zp_b
    lda #>.entries
    sta zp_b+1
    ldx .count
    beq .converted
--  ldy #0
-   lda (zp_a),y
    sta (zp_b),y
    iny
    cpy .loaded_entry_size
    bcc -
    lda zp_a
    clc
    adc .loaded_entry_size
    sta zp_a
    bcc +
    inc zp_a+1
+   lda zp_b
    clc
    adc #.ENTRY_SIZE
    sta zp_b
    bcc +
    inc zp_b+1
+   dex
    bne --
.converted:
    jsr .keep
    clc
    rts

; Runs the start screen until the user picks a server.
; Returns C=0 with A/Y = "host:port" and X = terminal mode to connect,
; and book_label = what to call it (its name, or else its host); or
; C=1 to go to the WiC64 portal.
book_menu:
    jsr .fetch
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

.KEY_COUNT = 15
.keys:
    !byte KEY_DOWN, KEY_UP, KEY_RETURN, "N", "E", "D", "T", "S", "O"
    !byte KEY_ARROW_LEFT, KEY_HOME, "$", "@", "#", "L"
.handlers_lo:
    !byte <(.down-1), <(.up-1), <(.connect_selected-1), <(.new-1), <(.edit-1)
    !byte <(.delete-1), <(.next_type-1), <(save_key-1), <(.open-1)
    !byte <(.portal-1), <(.top-1), <(.directory-1), <(.dos_command-1)
    !byte <(drive_key-1), <(drive_load_key-1)
.handlers_hi:
    !byte >(.down-1), >(.up-1), >(.connect_selected-1), >(.new-1), >(.edit-1)
    !byte >(.delete-1), >(.next_type-1), >(save_key-1), >(.open-1)
    !byte >(.portal-1), >(.top-1), >(.directory-1), >(.dos_command-1)
    !byte >(drive_key-1), >(drive_load_key-1)

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
    bne +
    jmp .key
+
    ldx .selected
    jsr .label_address
    ldx #book_label - book_session
    jsr .take_field
    ldx .selected
    jsr .entry_address
    lda #BOOK_ENTRY_USER
    ldx #book_user - book_session
    jsr .take_entry_field
    lda #BOOK_ENTRY_PASSWORD
    ldx #book_password - book_session
    jsr .take_entry_field
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

.no_input:
    jmp .key

.open:
    lda #0
    tay
    jsr .ask_host
    bcs .no_input
    jsr .take_host
    lda #<book_open_host
    ldy #>book_open_host
    ldx #book_label - book_session
    jsr .take_field
    lda #0                  ; no login
    sta book_user
    sta book_password
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
    bcs .no_input
    ldx .count
    stx .selected
    inc .count
    jsr .entry_address      ; a deleted entry may have left its details
    lda #0
    ldy #.ENTRY_SIZE-1
-   sta (zp_a),y
    dey
    bpl -
    ldx .selected
    jsr .store_host
    lda #TERM_PETSCII
    sta (zp_a),y
    jmp .ask_details

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

; Asks for the selected entry's name, user name and password, with
; what it has as the defaults.
.ask_details:
    lda #0
    sta .field
-   ldx .field
    lda .prompts_lo,x
    sta .prompt
    lda .prompts_hi,x
    sta .prompt+1
    jsr .field_address
    jsr .ask
    jsr .field_address
    ldx .field
    lda .field_offsets,x
    tay
    clc
    adc #.FIELD_MAX + 1
    jsr .store_field
    inc .field
    lda .field
    cmp #.DETAILS
    bcc -
    jmp .changed

; Returns A/Y = the selected entry's field .field, zp_a on the entry.
.field_address:
    ldx .selected
    jsr .entry_address
    ldx .field
    lda zp_a
    clc
    adc .field_offsets,x
    ldy zp_a+1
    bcc +
    iny
+   rts

.DETAILS = 3
.field_offsets: !byte BOOK_ENTRY_NAME, BOOK_ENTRY_USER, BOOK_ENTRY_PASSWORD
.prompts_lo:    !byte <.name_prompt, <.user_prompt, <.password_prompt
.prompts_hi:    !byte >.name_prompt, >.user_prompt, >.password_prompt

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
    jsr .label_address
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
    jsr .keep
    lda #<.unsaved_message
    ldy #>.unsaved_message
; Shows the message at A/Y and waits for the next key (also for
; disk_tools.asm).
book_show_message:
.show_message:
    sta .message
    sty .message+1
    jsr .draw
    jmp .key

.directory:
    jsr directory_show
    jsr disk_read_status
    jmp .show_drive_status

; Sends a command to the drive, or with none reads its status, and
; shows the drive's answer.
.dos_command:
    lda #<.dos_prompt
    sta .prompt
    lda #>.dos_prompt
    sta .prompt+1
    lda #0
    sta disk_status         ; no answer if the drive isn't there
    tay
    jsr .ask
    bcc +
    jsr disk_read_status
    jmp .show_drive_status
+   ldx #<INPUT_BUFFER
    ldy #>INPUT_BUFFER
    jsr disk_command
.show_drive_status:
    lda disk_status
    bne +
    lda #<.no_drive_message
    ldy #>.no_drive_message
    jmp .show_message
+   lda #<disk_status
    ldy #>disk_status
    jmp .show_message

;---------------------------------------------------------

; X = entry index; points zp_a at the entry. Changes X.
.entry_address:
    lda #<.entries
    sta zp_a
    lda #>.entries
    sta zp_a+1
-   dex
    bmi +
    lda zp_a
    clc
    adc #.ENTRY_SIZE
    sta zp_a
    bcc -
    inc zp_a+1
    bne -                   ; always
+   rts

; X = entry index; returns A/Y = its name, or its host if it has
; none. Leaves zp_a on the entry.
.label_address:
    jsr .entry_address
    ldy #BOOK_ENTRY_NAME
    lda (zp_a),y
    beq +
    lda zp_a
    clc
    adc #BOOK_ENTRY_NAME
    ldy zp_a+1
    bcc ++
    iny
++  rts
+   lda zp_a
    ldy zp_a+1
    rts

; Copies the field at offset A of the entry at zp_a to book_session + X.
.take_entry_field:
    clc
    adc zp_a
    pha
    lda zp_a+1
    adc #0
    tay
    pla
; Copies the text at A/Y to book_session + X, cut to .FIELD_MAX
; characters.
.take_field:
    sta .field_text+1
    sty .field_text+2
    ldy #0
.field_text:
-   lda $ffff,y
    sta book_session,x
    beq +
    inx
    iny
    cpy #.FIELD_MAX
    bcc -
    lda #0
    sta book_session,x
+   rts

; Asks for a host, or with .prompt for anything else, with the default
; text at A/Y (A = Y = 0 for none). Returns C=1 if the user entered
; nothing.
.ask_host:
    ldx #<.host_prompt
    stx .prompt
    ldx #>.host_prompt
    stx .prompt+1
book_ask:                   ; (also for disk_tools.asm, with book_prompt)
.ask:
    pha
    tya
    pha
    lda #.BOX_COLOR
    ldx #20
    jsr box_open
    +plot 1, 21
    lda .prompt
    ldy .prompt+1
    jsr print_str
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

; Copies the input line into entry X, without leading spaces, as its
; host. Leaves zp_a on the entry and Y on its mode.
.store_host:
    jsr .entry_address
    ldy #0
    lda #BOOK_ENTRY_MODE
; Copies the input line, without leading spaces, into the entry at zp_a from offset Y up to (not including) offset A,
; with a 0 after the text and up to the end.
.store_field:
    sta .field_end
    sec
    sbc #1
    sta .field_last
    jsr .skip_spaces
-   lda INPUT_BUFFER,x
    beq +
    sta (zp_a),y
    inx
    iny
    cpy .field_last
    bcc -
+   lda #0
-   sta (zp_a),y
    iny
    cpy .field_end
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

; Copies the list from BOOK_STORE to BOOK_LIST, for the start screen,
; and the start screen's overlay (disk_tools.asm) to BOOK_OVERLAY
.fetch:
    lda #>BOOK_OVERLAY_STORE
    ldx #>BOOK_OVERLAY
    ldy #BOOK_OVERLAY_PAGES
    jsr .copy_list
    lda #>BOOK_STORE
    ldx #>BOOK_LIST
    bne .list_pages         ; always
; and the list back again, after a change (also for disk_tools.asm)
book_keep:
.keep:
    lda #>BOOK_LIST
    ldx #>BOOK_STORE
.list_pages:
    ldy #.PAGES
.copy_list:
    sta zp_a+1
    stx zp_b+1
    tya
    tax
    lda #0
    sta zp_a
    sta zp_b
    tay
    sei
    lda #R6510_ALL_RAM      ; BOOK_STORE is under the I/O area
    sta R6510
-   lda (zp_a),y
    sta (zp_b),y
    iny
    bne -
    inc zp_a+1
    inc zp_b+1
    dex
    bne -
    lda #R6510_DEFAULT
    sta R6510
    cli
    rts

;---------------------------------------------------------
; Drawing
;---------------------------------------------------------

.draw:
    jsr ui_screen_menu
    jsr drive_show
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
    jsr .label_address
    ldx #.LABEL_COLUMNS
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

book_draw_message:
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
    bcs .command_failed
    jsr disk_read_open_status ; before closing: that resets the status
    php
    lda #15
    jsr CLOSE
    plp
    lda #1                  ; Z=0: the drive reported the error
    rts
.command_failed:
    pha
    lda #15
    jsr CLOSE
    pla
    ldx #0                  ; Z=1: A = KERNAL error
    sec
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
    jsr disk_present        ; reading from a drive that isn't there
    bcs +                   ; would wait for ever
    lda #0
    jsr SETNAM
    lda #15
    ldx disk_device
    ldy #15
    jsr SETLFS
    jmp OPEN
+   rts

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
book_selected:              ; (for disk_tools.asm)
.selected: !byte 0
.index:    !byte 0
book_message:
.message:  !word .empty_text

; book_init's file versions: before names, before logins, and now
.magic:          !text "WTB3"
.versions:       !text "1", "2", "3"
.entry_sizes:    !byte 40, 60, .ENTRY_SIZE
.file_ends_lo:   !byte <(book_load_buffer + 5 + 16 * 40), <(book_load_buffer + 5 + 16 * 60)
                 !byte <(book_load_buffer + .FILE_SIZE)
.file_ends_hi:   !byte >(book_load_buffer + 5 + 16 * 40), >(book_load_buffer + 5 + 16 * 60)
                 !byte >(book_load_buffer + .FILE_SIZE)
.loaded_end:        !word 0
.loaded_entry_size: !byte 0
book_prompt:
.prompt:     !word 0
.field:      !byte 0
.field_end:  !byte 0
.field_last: !byte 0
; What the session gets of the server it connects to
book_session:
book_label:    !fill .FIELD_MAX + 1, 0  ; its name, or else its host
book_user:     !fill .FIELD_MAX + 1, 0  ; its login (empty: none)
book_password: !fill .FIELD_MAX + 1, 0

!if .FILE_SIZE > $800 {
    !error "The address book takes more than BOOK_LIST's 2 KB"
}
!if .FILE_SIZE > book_load_buffer_size {
    !error "The address book file does not fit book_load_buffer"
}



.title:
    !pet PET_RVS_ON, PET_LIGHT_GREEN
    !pet "  WiC64 Telnet Client 3.3    Drive "
book_title_drive:           ; disk_tools.asm's drive_show puts it here
    !pet "8   ", PET_RVS_OFF, 0
.help:
    !pet PET_WHITE, "RETURN", PET_GREEN, "/", PET_WHITE, "1-9", PET_GREEN, " connect  "
    !pet PET_WHITE, "CRSR", PET_GREEN, " select", 13
    !pet PET_WHITE, "N", PET_GREEN, "ew ", PET_WHITE, "E", PET_GREEN, "dit "
    !pet PET_WHITE, "D", PET_GREEN, "elete ", PET_WHITE, "T", PET_GREEN, "ype "
    !pet PET_WHITE, "S", PET_GREEN, "ave ", PET_WHITE, "L", PET_GREEN, "oad", 13
    !pet PET_WHITE, "O", PET_GREEN, "pen other host  "
    !pet PET_WHITE, "_", PET_GREEN, " WiC64 portal", 13
    !pet PET_WHITE, "$", PET_GREEN, " directory  "
    !pet PET_WHITE, "@", PET_GREEN, " disk command  "
    !pet PET_WHITE, "#", PET_GREEN, " drive", 13
    !pet "Online: ", PET_WHITE, "F1", PET_GREEN, " hang up  "
    !pet PET_WHITE, "F3", PET_GREEN, " type a line", 13
    !pet "        ", PET_WHITE, "F5", PET_GREEN, " echo  "
    !pet PET_WHITE, "F7", PET_GREEN, " menu  "
    !pet PET_WHITE, "F4", PET_GREEN, "/", PET_WHITE, "F6", PET_GREEN, " login", 0
.empty_message:   !pet "No servers yet. Press N to add one.", 0
.host_prompt:     !pet "Server as host:port, e.g. bbs.org:23", 0
.name_prompt:     !pet "Name (may be left empty)", 0
.user_prompt:     !pet "User name, sent on F4", 0
.password_prompt: !pet "Password, sent on F6", 0
.dos_prompt:      !pet "Disk command (none: drive status)", 0
.delete_prompt:   !pet "Delete ", PET_WHITE, 0
.yes_no:          !pet PET_GREEN, "? (Y/N)", 0
.full_message:    !pet "The list is full (16 servers).", 0
.unsaved_message: !pet "Changed. Press S to save to disk.", 0
book_no_drive_message:
.no_drive_message:   !pet "No disk drive found.", 0
.empty_text:      !byte 0
}

; The address book until a file is loaded: put at BOOK_STORE (main.asm)
!macro book_defaults {
    !text "WTB3"
    !byte 9
    +book_entry "8bit.hoyvision.com:6502", TERM_PETSCII, "8-Bit Playground"
    +book_entry "particlesbbs.dyndns.org:6400", TERM_PETSCII, "Particles! BBS"
    +book_entry "cottonwoodbbs.dyndns.org:6502", TERM_PETSCII, "Cottonwood BBS"
    +book_entry "rapidfire.hopto.org:64128", TERM_PETSCII, "Rapid Fire BBS"
    +book_entry "raveolution.hopto.org:64128", TERM_PETSCII, "Raveolution BBS"
    +book_entry "bbs.fozztexx.com:23", TERM_ANSI, "Level 29"
    +book_entry "bbs.retrocampus.com:6510", TERM_PETSCII, "RetroCampus BBS"
    +book_entry "vert.synchro.net:23", TERM_ANSI, "Vertrauen"
    +book_entry "telehack.com:23", TERM_UTF8_80, "Telehack"
    !fill 7 * BOOK_ENTRY_SIZE, 0
}

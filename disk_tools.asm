;---------------------------------------------------------
; The start screen's disk tools: the directory ($), the drive (#), and
; saving (S) and loading (L) the address book, under a name of the
; user's choice (book_file_name, telnet.cfg to begin with)
;
; directory_show lists the directory of disk_device as BASIC's LOAD"$"
; and LIST would: the blocks, then the name and type. Any key pauses the
; listing until the next key; RUN/STOP ends it.
;
; disk_device is the drive the program was loaded from (the KERNAL's
; last device), or drive 8 if that is none, or if telnet.cfg isn't on
; it: started from the WiC64 portal, a cartridge or a launcher, the last
; device need not be a drive at all. # steps through drives 8 to 11, the
; start screen's title shows the one in use, and L loads telnet.cfg from
; it.
;
; Saving writes the list as telnet.tmp first and only gives it the
; name once it is on the disk completely, so that a failed save leaves
; the old file alone.
;
; This code only runs on the start screen. It is kept in the RAM under
; the I/O area (BOOK_OVERLAY_STORE) and copied to BOOK_OVERLAY with the
; address book (book.asm's .fetch), as the program has no room left for
; it.
;---------------------------------------------------------

!zone drive {
.LAST_DRIVE = 11

; Chooses disk_device and loads the address book from it.
drive_init:
    lda LAST_DEVICE
    cmp #8
    bcc .eight
    cmp #31
    bcc +
.eight:
    lda #8
+   sta disk_device
    jsr .load
    bcc .found
    lda #8                  ; not there: drive 8, the usual one
    cmp disk_device
    beq .found
    sta disk_device
    jmp .load
.found:
    rts

; Loads book_file_name. Returns C=0 if it was there.
.load:
    jsr .name_length
    ldx #<book_file_name
    ldy #>book_file_name
    jsr SETNAM
    jmp book_load

; Returns the length of book_file_name in A.
.name_length:
    ldx #$ff
-   inx
    lda book_file_name,x
    bne -
    txa
    rts

; Asks for the name to save or load as; RETURN on its own keeps the last
; one (the prompt shows it). The name is kept with the list.
.ask_name:
    ldx #0
-   lda .name_prompt,x      ; the prompt, then the name
    beq +
    sta .prompt_text,x
    inx
    bne -
+   ldy #0
-   lda book_file_name,y
    sta .prompt_text,x
    inx
    iny
    cmp #0
    bne -
    lda #<.prompt_text
    sta book_prompt
    lda #>.prompt_text
    sta book_prompt+1
    lda #0                  ; no default text: the editor would type
    tay                     ; over it, leaving its end
    jsr book_ask
    bcs .no_name
    ldx #0
-   lda INPUT_BUFFER,x
    beq +
    sta book_file_name,x
    inx
    cpx #BOOK_FILE_NAME_MAX
    bcc -
+   lda #0
    sta book_file_name,x
    jsr book_keep
.no_name:
    clc
    rts

; #: the next drive
drive_key:
    ldx disk_device
    inx
    cpx #.LAST_DRIVE + 1
    bcc +
    ldx #8
+   stx disk_device
    lda #<.no_message
    ldy #>.no_message
    jmp book_show_message

; Puts disk_device, in decimal, into the start screen's title.
drive_show:
    lda disk_device
    ldx #$30 - 1             ; "0" - 1
    sec
-   inx                     ; X = the tens, as a digit
    sbc #10
    bcs -
    adc #$30 + 10            ; "0" + 10: A = the units, as a digit
    cpx #"0"
    bne +
    tax                     ; one digit: then a space
    lda #" "
+   stx book_title_drive
    sta book_title_drive + 1
    rts

; L: the address book from the drive in the title
drive_load_key:
    jsr .ask_name
    jsr .load
    bcc +
    lda #<.not_loaded
    ldy #>.not_loaded
    jmp book_show_message
+   lda #0                  ; the list may be shorter now
    sta book_selected
    lda #<.loaded
    ldy #>.loaded
    jmp book_show_message

; S: the address book to the drive in the title
save_key:
    jsr .ask_name
    lda #<.saving
    ldy #>.saving
    sta book_message
    sty book_message+1
    jsr book_draw_message
    jsr .save
    jmp book_show_message
; Returns A/Y = the message to show.
.save:
    lda #.scratch_tmp_length ; left over from an earlier failed save
    ldx #<.scratch_tmp
    ldy #>.scratch_tmp
    jsr disk_command
    bcs .disk_failed
    lda #.tmp_length
    ldx #<.tmp
    ldy #>.tmp
    jsr SETNAM
    lda #1
    ldx disk_device
    ldy #0
    jsr SETLFS
    lda #<BOOK_LIST
    sta zp_a
    lda #>BOOK_LIST
    sta zp_a+1
    lda #zp_a
    ldx #<(BOOK_LIST + BOOK_FILE_SIZE)
    ldy #>(BOOK_LIST + BOOK_FILE_SIZE)
    jsr SAVE
    bcs .kernal_error
    jsr disk_read_status
    bcs .drive_error
    lda #"S"                ; S0:name, then R0:name=TELNET.TMP
    jsr .command
    jsr .send_command
    bcs .disk_failed
    lda #"R"
    jsr .command
    ldy #0
-   lda .equals_tmp,y
    sta .command_text,x
    inx
    iny
    cpy #.equals_tmp_length
    bcc -
    txa
    jsr .send_command
    bcs .disk_failed
    lda #<.saved
    ldy #>.saved
    rts
.disk_failed:
    bne .drive_error
.kernal_error:
    cmp #5
    bne .drive_error
    lda #<book_no_drive_message
    ldy #>book_no_drive_message
    rts
.drive_error:
    lda disk_status
    beq +
    lda #<disk_status
    ldy #>disk_status
    rts
+   lda #<.disk_error
    ldy #>.disk_error
    rts

; Sends .command_text, A bytes long, to the drive.
.send_command:
    ldx #<.command_text
    ldy #>.command_text
    jmp disk_command

; Puts A, "0:" and book_file_name in .command_text. Returns the length
; in A and X.
.command:
    sta .command_text
    lda #"0"
    sta .command_text+1
    lda #":"
    sta .command_text+2
    ldx #3
    ldy #0
-   lda book_file_name,y
    beq +
    sta .command_text,x
    inx
    iny
    bne -
+   txa
    rts

.no_message: !byte 0
.loaded:     !pet "Loaded.", 0
.not_loaded: !pet "Not found on this drive.", 0
.saving:     !pet "Saving...", 0
.saved:      !pet "Saved.", 0
.disk_error: !pet "Disk error.", 0
.name_prompt: !pet "File name, RETURN: ", 0
.prompt_text: !fill 19 + BOOK_FILE_NAME_MAX + 1, 0
.tmp:        !pet "telnet.tmp"
.tmp_length = * - .tmp
.scratch_tmp: !pet "s0:telnet.tmp"
.scratch_tmp_length = * - .scratch_tmp
.equals_tmp: !pet "=telnet.tmp"
.equals_tmp_length = * - .equals_tmp
.command_text: !fill 3 + BOOK_FILE_NAME_MAX + .equals_tmp_length, 0
}

!zone directory {
.FILE = 2
.KEYS_WAITING = $c6

directory_show:
    jsr ui_screen_menu
    lda #1
    ldx #<.dollar
    ldy #>.dollar
    jsr SETNAM
    lda #.FILE
    ldx disk_device
    ldy #0                  ; as a program: links and line numbers
    jsr SETLFS
    jsr OPEN
    bcs .done
    ldx #.FILE
    jsr CHKIN
    bcs .done
    jsr CHRIN               ; the load address
    jsr CHRIN

.line:
    jsr CHRIN               ; the link: 0 at the end
    sta .link
    jsr CHRIN
    ora .link
    beq .done
    jsr READST
    bne .done               ; no disk, or a drive error
    jsr CHRIN               ; the line number: the blocks
    sta print_number_value
    jsr CHRIN
    sta print_number_value+1
    lda #0
    sta print_number_value+2
    ldx #5
    jsr print_number
    lda #" "
    jsr CHROUT
-   jsr CHRIN
    beq +
    jsr CHROUT
    jsr READST
    beq -
+   lda #$0d
    jsr CHROUT
    jsr STOP
    beq .done
    lda .KEYS_WAITING       ; a key: pause until the next one
    beq .line
    jsr .key_from_keyboard
    ldx #.FILE
    jsr CHKIN
    jmp .line

.done:
    jsr CLRCHN
    lda #.FILE
    jsr CLOSE
    +print .press_key
.key_from_keyboard:
    jsr CLRCHN              ; GETIN reads the keyboard again
    lda #0
    sta .KEYS_WAITING
    jmp wait_key

.dollar:    !pet "$"
.press_key: !pet 13, PET_GREEN, "Press a key.", 0
.link:      !byte 0
}
directory_end:

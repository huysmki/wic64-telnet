;---------------------------------------------------------
; An address book file as versions up to 3.3 wrote it (WTB1, 40-byte
; entries without names), for scenario 24: acme -f cbm makes it with
; the load address the KERNAL's SAVE puts in front
;---------------------------------------------------------

!macro old_entry .host, .mode {
    .start = *
    !pet .host
    !fill 39 - (* - .start), 0
    !byte .mode
}

* = $c400
    !text "WTB1"
    !byte 3
    +old_entry "old.example.org:6400", 0
    +old_entry "ansi.example.net:23", 1
    +old_entry "eighty.example.com:2323", 3
    !fill 13 * 40, 0

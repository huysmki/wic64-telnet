;---------------------------------------------------------
; An address book file from before logins (WTB2, 60-byte entries with
; names), for scenario 25
;---------------------------------------------------------

!macro wtb2_entry .host, .mode, .name {
    .start = *
    !pet .host
    !fill 39 - (* - .start), 0
    !byte .mode
    !pet .name
    !fill 60 - (* - .start), 0
}

* = $c400
    !text "WTB2"
    !byte 2
    +wtb2_entry "login.example.org:6400", 0, "Login BBS"
    +wtb2_entry "other.example.net:23", 1, ""
    !fill 14 * 60, 0

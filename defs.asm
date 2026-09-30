;---------------------------------------------------------
; System addresses, memory map and shared constants
;---------------------------------------------------------

; KERNAL routines
SETMSG = $ff90
READST = $ffb7
SETLFS = $ffba
SETNAM = $ffbd
OPEN   = $ffc0
CLOSE  = $ffc3
CHKIN  = $ffc6
CLRCHN = $ffcc
CHRIN  = $ffcf
CHROUT = $ffd2
LOAD   = $ffd5
SAVE   = $ffd8
GETIN  = $ffe4
PLOT   = $fff0

; BASIC line input: reads one line from the screen editor into
; INPUT_BUFFER, 0-terminated
BASIC_INLIN  = $a560
INPUT_BUFFER = $0200

; KERNAL variables
JIFFY_MID     = $a1
JIFFY_LO      = $a2
LAST_DEVICE   = $ba
REVERSE_FLAG  = $c7
LINE_PTR      = $d1     ; start of the current logical screen line
CURSOR_COL    = $d3     ; column within the logical line (0-79)
QUOTE_MODE    = $d4
INSERT_COUNT  = $d8
LINE_LINKS    = $d9     ; 25 entries, bit 7 clear = continues the row above
CURSOR_COLOR  = $0286
KEY_MODIFIERS = $028d   ; bit 2 = CTRL held

; VIC
BORDER     = $d020
BACKGROUND = $d021
VIC_MEMORY = $d018
VIC_ROM_CHARSET    = $17   ; screen $0400, ROM lower/upper case set
VIC_CUSTOM_CHARSET = $1e   ; screen $0400, CHARSET at $3800

SCREEN    = $0400
COLOR_RAM = $d800
COLOR_OFFSET_HI = >(COLOR_RAM - SCREEN)

; Keys as returned by GETIN
KEY_RETURN = $0d
KEY_DOWN   = $11
KEY_HOME   = $13
KEY_DEL    = $14
KEY_RIGHT  = $1d
KEY_ARROW_LEFT = $5f
KEY_F1     = $85
KEY_F3     = $86
KEY_F5     = $87
KEY_F7     = $88
KEY_UP     = $91
KEY_CLR    = $93
KEY_LEFT   = $9d

; PETSCII control codes
PET_WHITE       = $05
PET_LOCK_CASE   = $08
PET_UNLOCK_CASE = $09
PET_LOWER_CASE  = $0e
PET_RVS_ON      = $12
PET_RED         = $1c
PET_GREEN       = $1e
PET_RVS_OFF     = $92
PET_CLR         = $93
PET_CRSR_LEFT   = $9d
PET_YELLOW      = $9e
PET_LIGHT_GREEN = $99
PET_GREY        = $98

; Colors
COLOR_BLACK       = $00
COLOR_WHITE       = $01
COLOR_RED         = $02
COLOR_GREEN       = $05
COLOR_GREY        = $0c
COLOR_LIGHT_GREEN = $0d
COLOR_LIGHT_GREY  = $0f

; Zero page pointers, free for any routine that does not hold
; them across calls into other modules
zp_a = $fb
zp_b = $fd

; Memory map
;   $0801-$37ff  program
;   $3800-$3fff  CHARSET: ASCII character set for the ANSI modes
;   $4000-       uninitialised buffers
CHARSET          = $3800
BSS              = $4000
box_save_buffer  = BSS            ; 8 rows * (40 screen + 40 color)
box_save_links   = BSS + $0280    ; 25 bytes
net_response     = BSS + $0300    ; 256 bytes
book_load_buffer = BSS + $0400    ; 1 KB
alt_screen_buffer = BSS + $0800   ; 24 rows * (40 screen + 40 color)

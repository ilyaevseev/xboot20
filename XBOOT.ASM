code            segment

                assume  cs:Code, ds:Code, es:Code, ss:Code
                org     0

;DiskB          equ     1   ;Allow load system from drive B: when CTRL pressed

IFDEF DiskB
New40location   equ     300h
Vect40seg       equ     040h * 4 + 2
Vect40ofs       equ     040h * 4
VectD0seg       equ     0D0h * 4 + 2
VectD0ofs       equ     0D0h * 4
ENDIF

CtrlShift       equ     4
AltShift        equ     8
F1_scancode     equ     59
Numeric         equ     '0'             ; First numeric value

BootLocation    equ     7C00h           ; Address where DOS loads us
BootSeg         equ     07C0h           ; Segment where DOS loads us
NewBootLocation equ     7A00h           ; Address where we relocate
NewBootSeg      equ     07A0h           ; Segment where we relocate
PartAddr        equ     1beh            ; offset to partition table

max_entryes     equ     4
max_partitions  equ     3               ; Can't fit any more
part_text_len   equ     15              ; max bytes for partition desc

HiddenId        equ     0FFh            ; BBT

TPartEntry      struc
BootIndicator   db      ?
BeginHead       db      ?
BeginSector     db      ?
BeginCyl        db      ?
SystemID        db      ?
EndHead         db      ?
EndSector       db      ?
EndCyl          db      ?
RelSectorLow    dw      ?
RelSectorHigh   dw      ?
NumSectorsLow   dw      ?
NumSectorsHigh  dw      ?
TPartEntry      ends

TPartData       struc
trueSys         db   0
partition       db   0
text            db   part_text_len dup(0)
term            db   +80h
TPartData       ends

PartDataLen     equ  SIZE TPartData * max_partitions

DataAddr        equ  PartAddr - PartDataLen - 4  ; 4=sizeof(XBootId)

TBootHeader     struc
JmpCode         db   3 dup(?)
OEM             db   8 dup(?)
SecSize         dw   200h
CluSec          db   ?
ResSect         dw   ?
FatCnt          db   ?
Root            dw   ?
Secs            dw   ?
Media           db   ?
FatSect         dw   ?
SecTrk          dw   ?
Heads           dw   ?
HidSecs         dd   ?
BigSecs         dd   ?
DrvNo           db   ?
res1            db   ?
ExtSig          db   29h
SerNo           dd   ?
Vol             db   11 dup(?)
SysID           db   8 dup(?)
TBootHeader     ends

;*************  End of definitions  *********************************

bootany         proc    near

;*************  Setup stack at 0000:7A00  ***************************

                mov     AX,CS
                mov     DS,AX
                cli
                mov     SS,AX
                mov     SP,NewBootLocation
                sti

; DOS loads this pgm at 0000:7C00. Any boot routine we call also expects
; to execute there so the first exercise is to move this code somewhere else.

;*************  Free space for next boot  ***************************

                mov     CX,512
                mov     SI,BootLocation
                les     DI,DWORD PTR SecBoot[SI] ; ES:DI <- 07A0:0000
                rep     movsb

                lea     SI,down+NewBootLocation
                jmp     SI

down            equ     $

;*************  Setup data segment  *********************************

                mov     AX,ES
                mov     DS,AX

; if "Ctrl" pressed, then run system from drive B:
; if "ALT"  pressed, then display prompt and select new bootable partition
; else run system from current active partition without changes
                mov     al, cs:[417h]
IFDEF DiskB
                test    al, CtrlShift
                jnz     SystemB
ENDIF
checkAlt:       test    al, AltShift
                jnz     prompt

;*************  Load default from HD  *******************************

default:        mov     cx, max_entryes
next_prob:      call    LoadBoot
                jnc     StartNextBoot
                loop    next_prob
IFDEF DiskB
                int     18h
ELSE
                lea     SI, haltStr     ; No bootable partEntry found
                call    Send
forever:        jmp     SHORT forever
ENDIF
;*************  Display the menu  ***********************************

prompt:         mov     CX, max_partitions
                xor     BX, BX
                mov     DL, Numeric
                mov     key, DL
promptLoop:
                inc     DL
                cmp     part.partition[BX],0
                je      finishPrompt
                mov     key, DL
                lea     SI, FkeyMsg
                call    Send
                lea     SI, part.text[BX]
                call    Send
                add     BX, SIZE TPartData
                loop    promptLoop
finishPrompt:
                sub     key, Numeric
                jz      default      ; if all partData is empty, load current
                lea     SI, finishStr
                call    Send

;*************  Get the reply from keyboard  ************************
error:
reply:          xor     ax, ax
                int     16h
                sub     ah, F1_scancode-1
                jbe     reply
                cmp     ah, key
                ja      reply
                jmp     SHORT system

;*************  Load second boot sector from drive B:  **************
IFDEF DiskB
SystemB:        xor     ax, ax
                mov     es, ax
                mov     di, New40location
                xchg    ax, es:[Vect40seg]
                mov     es:[VectD0seg], ax
                mov     ax, di
                xchg    ax, es:[Vect40ofs]
                mov     es:[VectD0ofs], ax
                mov     si, offset New40start
                mov     cx, New40length
                rep     movsb

                mov     ax, NewBootLocation + offset StartNextBoot
                push    ax
                push    cx
                inc     cx
                xor     dx, dx
                jmp     LoadPrim
ENDIF
;*************  Execute next loaded boot-sector  ********************

StartNextBoot:  cli                     ; disable interrupts
                mov     SI,BootLocation ; get address of area read
                jmp     SI              ; enter second level boot

;************   Load system from new partition and update self  *****

system:         mov     ch, 1
                mov     al, SIZE TPartData
                dec     ah              ; now AH (keycode) in [0..3]
                mul     ah
                xchg    di, ax
                mov     cl, part[di].Partition
                call    LoadBoot        ; BX = offset to new partEntry
                jc      error
                mov     ah, part[di].TrueSys  ; AH = type of new system

                xor     cx, cx
                xor     si, si
                mov     dl, max_partitions
resetNext:      mov     cl, part[si].Partition
                jcxz    skipReset
                dec     cx
                xchg    di, ax          ; preserve AH (new SystemId)
                mov     al, SIZE TPartEntry
                mul     cl
                xchg    di, ax
                mov     PartEntry[di].SystemId, HiddenId
                mov     PartEntry[di].BootIndicator, 0
skipReset:      add     si, SIZE TPartData
                dec     dl
                jnz     resetNext

                mov     partEntry[bx].BootIndicator, 80h
                mov     partEntry[bx].SystemID, ah

;*************  Update self on the hard disk and go next  ***********

                mov     AX, 301h        ; write sector
                les     BX, DWORD PTR SecBoot ; buffer address
                mov     CX, 1           ; cylinder 0, sector 1
                mov     dx, 80h         ; head 0, hard drive 0
                int     13h             ; replace master boot record

                mov     ah, 0Fh         ; clear the screen
                int     10h
                mov     ah, 0
                int     10h

                jmp     SHORT StartNextBoot

;*************  Load and check new boot sector  ***************
;Entry:
; CH = 0, CL = #partEntry  ->>  BX = @partEntry[CL-1]  (check BootIndicator)
; CH = 1, CL = #partEntry  ->>  BX = @partEntry[CL-1]  (no check BootIndicator)

LoadBoot:       push    cx
                dec     cl
                mov     al, SIZE TPartEntry
                mul     cl
                xchg    bx, ax          ; BX = offset to PartEntry

                cmp     ch, 1
                je      contLoad
                cmp     partEntry[bx].BootIndicator, 80h
                jne     skipLoad
contLoad:
                mov     DL, 80h         ; hard drive 0
                mov     DH, partEntry.BeginHead[BX]
                mov     CL, partEntry.BeginSector[BX]
                mov     CH, partEntry.BeginCyl[BX]
LoadPrim:       push    bx
                les     BX, DWORD PTR PrimBoot  ; ES:BX = @dest
                mov     AX, 201h        ; read 1 sector
                int     13h             ; read system boot record
                pop     bx
                jc      endLoad

                cmp     word ptr ES:510,0aa55h ; test signature
skipLoad:       clc
                je      testOk
                stc
testOk:
endLoad:        pop     cx
                ret

;*************  Out message to console, terminate by 80h  ***********

Send:           cld
                lodsb
                test    AL,80h
                pushf
                and     AL,7fh
                mov     AH,14
                int     10h
                popf
                jz      Send
                ret

;*************  New handler 40h swapped A: and B:  *******************
IFDEF DiskB
New40start      label   near
                pushf
                xor     dl, 1
                popf
                int     0D0h
                pushf
                xor     dl, 1
                popf
                iret
New40length     =       $ - offset New40start
ENDIF
;*************  Internal data  **************************************

SecBoot         dw      0,NewBootSeg    ;  ES=07A0  BX=0
PrimBoot        dw      0,BootSeg       ;  ES=07C0  BX=0
IFNDEF DiskB
  haltStr       db      'Cannot run system from HD.',7+80h
ENDIF
FkeyMsg         db      13,10,'F'
key             db      'X  ',+0A0h
finishStr       db      13,10,10,'Select F?',':'+80h
used            equ     $ - bootany

;*************  Global data  ****************************************

clearAmt        equ     DataAddr - used ; Assembly error if code too big
                db      clearAmt dup(0) ; clear rest of record

XBootId         dd      11EBCEEBh

part            TPartData max_partitions dup(<>)

partEntry       TPartEntry max_entryes dup(<>)

bootany         endp
code            ends

                end     bootany

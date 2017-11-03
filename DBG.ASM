
       .model  tiny

       .code

        org     100h
start:
        xor     ax, ax
        mov     es, ax
        mov     ds, ax
        mov     ax, 0201h
        mov     bx, 7C00h
        mov     cx, 1
        mov     dx, 80h  ;0=1st floppy, 80h=1st HDD
        push    es
        push    bx
        int     13h
        retf

        end     start

; sibabs.asm — CORPUS SIB-abs COM índice (R-5.4 "loads indexados").
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; Formas base=NOBASE + index (SIB base=101): so `lea` (sem deref) para nao
; dar AV em runtime; o objetivo e a EMISSAO (db -> texto) e o exit 42.
bits 64
default rel

global main
extern ExitProcess

section .text
main:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov ecx, 3
    lea rax, [rcx*4]             ; [rcx*4]   (SIB-abs, disp32=0)
    lea rdx, [rcx*8]             ; [rcx*8]
    lea r8,  [rcx*2]             ; [rcx*2]
    lea r9,  [rcx*1]             ; base=rcx (sem SIB) — controle
    lea r10, [rcx*2+2]           ; nasm encoda split ([rcx+rcx+0x2]) — controle
    lea r11, [rdx*4+8]           ; SIB-abs com disp32 != 0 (ramo "nosplit abs")
    add rax, rdx
    add rax, r8
    add rax, r9                  ; 4*3 + 8*3 + 2*3 + 3 = 12+24+6+3 = 45
    mov qword [rsp+32], rax      ; preserva (return do ExitProcess nao volta)
    mov ecx, 42
    call ExitProcess

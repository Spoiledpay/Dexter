; absidx.asm — CORPUS x32: tabela ABSOLUTA indexada (índice simbólico).
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; `jmp dword [jtab + eax*4]` (SIB-abs, base ausente) + `mov ecx,[jtab2+edx*4]`
; (load indexado absoluto). Convenção x32: stdcall decorado (`_ExitProcess@4`).
bits 32

global main
extern _ExitProcess@4

section .text
main:
    push ebp
    mov ebp, esp
    sub esp, 48
    mov eax, 2
    cmp eax, 3
    ja  dflt
    jmp dword [jtab + eax*4]     ; SIB-abs + índice (base ausente)
c0:
    mov ecx, 0
    jmp out
c1:
    mov ecx, 1
    jmp out
c2:
    mov ecx, 42
    jmp out
c3:
    mov ecx, 3
    jmp out
dflt:
    mov ecx, 99
out:
    mov edx, 1
    mov ecx, [jtab2 + edx*4]     ; load indexado absoluto (controle)
    add ecx, 41                  ; 1 + 41 = 42
    push ecx
    call _ExitProcess@4

section .rdata
jtab:  dd c0, c1, c2, c3
jtab2: dd 1, 1, 1, 1

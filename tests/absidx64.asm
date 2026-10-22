; absidx64.asm — CORPUS x64: tabela ABSOLUTA indexada (índice simbólico).
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; Requer ImageBase < 2 GiB (/BASE:0x400000 /DYNAMICBASE:NO): só assim o
; disp32 do SIB-abs (base ausente, base=101) pode apontar para dados da
; imagem em x64 — em base >= 4 GiB o disp32 é sinal-estendido para fora da
; imagem e a forma não é um endereço válido do módulo.
; Formas cobertas: dispatch `jmp qword [jtab+rcx*8]`, load indexado
; `mov eax,[jtab2+rdx*4]` e `lea` com escala 2 (sem deref).
bits 64
default rel

global main
extern ExitProcess

section .text
main:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov ecx, 2
    cmp ecx, 3
    ja  dflt
    jmp qword [jtab + rcx*8]     ; SIB-abs + índice (base ausente)
c0:
    mov ecx, 10
    jmp out
c1:
    mov ecx, 20
    jmp out
c2:
    mov ecx, 42
    jmp out
c3:
    mov ecx, 30
    jmp out
dflt:
    mov ecx, 99
out:
    mov edx, 3
    mov eax, [jtab2 + rdx*4]     ; load indexado absoluto (controle)
    add eax, 41                  ; 1 + 41 = 42
    lea r8, [jtab3 + rdx*2]      ; SIB-abs só endereço (escala 2)
    mov ecx, eax
    call ExitProcess

section .rdata
align 8
jtab:  dq c0, c1, c2, c3
jtab2: dd 39, 1, 1, 1
jtab3: dw 0, 0, 0, 0

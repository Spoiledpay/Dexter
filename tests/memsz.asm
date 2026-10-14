; memsz.asm — CORPUS x64 p/ prefixo de tamanho em refs RIP (gcc-native).
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; Formas: movzx byte/word [rel] + cmp byte [rel], imm (nasm exige
; tamanho explícito; sem ele: "operation size not specified").
; Comportamento: soma 0x41+0x1234 e sai com exit code 0.
bits 64
default rel

global main
extern ExitProcess

section .text code
main:
    movzx eax, byte [rel mb]
    movzx ecx, word [rel mw]
    add eax, ecx
    cmp byte [rel mb], 0x41
    jne .fail
    xor ecx, ecx
    call ExitProcess
.fail:
    mov ecx, 1
    call ExitProcess

section .rdata rdata
mb: db 0x41
mw: dw 0x1234

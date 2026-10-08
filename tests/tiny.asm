; tiny.asm — GOLDEN test binary: mínimo, 2 seções, cabe em 4KB
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; Comportamento: sai com exit code 42 (sem output).
bits 64
default rel

global main
extern ExitProcess

section .text
main:
    sub rsp, 40                ; alinha p/ call (entry rsp%16==0 -> 8)
    mov ecx, 42
    call ExitProcess

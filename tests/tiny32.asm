; tiny32.asm — CORPUS x32 mínimo (Fase C): 2 seções, exit 42.
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; Comportamento: sai com exit code 42 (sem output). Convenção stdcall
; (_ExitProcess@4); entry `start` (não `_main`: o link puxaria o CRT
; atrás de `__main`). A suíte monta com nasm -f win32 + link X86.
bits 32

global start
extern _ExitProcess@4

section .text code
start:
    push 42
    call _ExitProcess@4

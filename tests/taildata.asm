; =============================================================================
; tests/taildata.asm — FONTE SAGRADA DO CORPUS (D-19 fatia 2c-3)
; Fixture de `.data` com vsize > raw: o loader zera o tail nao presente no
; arquivo. tests/taildata_patch.py reduz SizeOfRawData de `.data` para 0x400;
; m1 (0x800) e m2 (0xC00) caem no tail zerado. O programa le os dois campos e
; so sai 42 se ambos forem zero.
;
; Como testar: tests\run_tests.bat [58].
; =============================================================================
bits 64
default rel

global start
extern ExitProcess

section .text
start:
    mov eax, [rel m1]
    add eax, [rel m2]
    cmp eax, 0
    jne .bad
    mov ecx, 42
    sub rsp, 0x28
    call ExitProcess
.bad:
    mov ecx, 7
    sub rsp, 0x28
    call ExitProcess

section .data
    times 0x800 db 0xAA
m1: dd 0x11111111
    times 0x3FC db 0xBB
m2: dd 0x22222222

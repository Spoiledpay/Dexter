; strings.asm — GOLDEN test binary: .rdata rico (strings p/ -strings)
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; Comportamento: imprime 3 linhas e sai (exit 0).
bits 64
default rel

global main
extern ExitProcess
extern GetStdHandle
extern WriteFile

section .text
main:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov ecx, -11
    call GetStdHandle
    mov [rsp+32], rax
    lea rbx, [rel s_tab]
    mov edi, 3                 ; 3 strings
.next:
    test edi, edi
    jz .done
    mov rcx, [rsp+32]          ; handle
    mov rdx, [rbx]             ; ptr
    mov r8d, [rbx+8]           ; len
    add rbx, 16
    dec edi
    lea r9, [rsp+40]           ; written (rbx/rdi sobrevivem: API preserva non-voláteis)
    mov qword [rsp+40], 0
    sub rsp, 32
    mov qword [rsp+32], 0      ; overlapped = NULL
    call WriteFile
    add rsp, 32
    jmp .next
.done:
    xor ecx, ecx
    call ExitProcess

section .rdata
s1 db 'alpha-one', 13, 10, 0
s2 db 'say "hi" ok', 13, 10, 0
s3 db '0123456789ABCDEF', 13, 10, 0
s_tab dq s1, 11, s2, 13, s3, 18

; jtable.asm — CORPUS jump table absoluta (switch) para o Dexter.
; FONTE SAGRADA DO CORPUS: nunca gerar .asm em cima deste arquivo!
; main sem args: i=2 fixo -> tabela jtab (dq VAs absolutas, base via
; lea RIP-rel) -> jmp indireto -> imprime '2' + CRLF, exit 0.
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
    mov ecx, 2
    cmp ecx, 3
    ja jt_dflt
    lea rax, [rel jtab]
    mov rax, [rax+rcx*8]         ; VA absoluta do case
    jmp rax
jt_c0:
    mov al, '0'
    jmp jt_out
jt_c1:
    mov al, '1'
    jmp jt_out
jt_c2:
    mov al, '2'
    jmp jt_out
jt_c3:
    mov al, '3'
    jmp jt_out
jt_dflt:
    mov al, 'X'
jt_out:
    mov [rsp+32], al             ; char (local)
    mov byte [rsp+33], 13
    mov byte [rsp+34], 10
    mov ecx, -11
    call GetStdHandle
    mov rcx, rax                 ; hFile
    lea rdx, [rsp+32]            ; buf
    mov r8d, 3                   ; len
    lea r9, [rsp+40]             ; written
    mov qword [rsp+40], 0
    mov qword [rsp+48], 0        ; overlapped=NULL (5th arg at [rsp+32] of call)
    sub rsp, 32
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 32
    xor ecx, ecx
    call ExitProcess

section .rdata
jtab dq jt_c0, jt_c1, jt_c2, jt_c3

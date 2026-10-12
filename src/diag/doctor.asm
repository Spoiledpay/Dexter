;=============================================================================
; Dexter/src/diag/doctor.asm
; dex_doctor — checagem inspect-only da toolchain (nasm/link/kernel32/versão).
;
; O quê: imprime versão do dexter + paths configurados de nasm/link com
;   existência (ok/missing) + kernel32 ok + input válido, sem gerar .asm.
; Por quê: diagnóstico rápido de ambiente ("por que o rebuild falha?").
;   R-7.5, marco.md §5.
; Contrato:
;   Args:   rcx = DexConfig* (nasm_path/linker_path), rdx = PeImage*
;           (já validado — o chamador só despacha após pe_load OK, logo
;           "input: valid PE x64" é fato, não inferência).
;   Ret:    eax = 0 sempre (best-effort, como overview; nunca falha).
;   Clobber: rax, rcx, rdx, r8-r11.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\run_tests.bat seção [20] (--doctor + -doctor -q).
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_doctor

extern dex_console_print_cstr
extern dex_console_print_u64dec
extern dex_open_read
extern dex_close

section .rodata
s_dr_hdr    db "Doctor: dexter ", 0
s_dr_dot    db ".", 0
s_dr_nl     db 13, 10, 0
s_dr_nasm   db "  nasm: ", 0
s_dr_link   db "  link: ", 0
s_dr_ok     db " ok", 13, 10, 0
s_dr_miss   db " missing", 13, 10, 0
s_dr_k32    db "  kernel32: ok", 13, 10, 0
s_dr_input  db "  input: valid PE x64", 13, 10, 0

section .text

;-----------------------------------------------------------------------------
; dex_doctor — rcx=cfg, rdx=img -> eax=0.
; Frame: 5 pushes (40B) + sub 32 = 72 = 16*4+8 (regra D-10); os 32B
;   reservados servem de shadow para os calls internos (sem sub/add).
; rbx=cfg, r13=path do tool sob teste, r14=handle (não-voláteis: vivem
;   através dos calls; r12 guarda img sem uso além de documentar validade).
;-----------------------------------------------------------------------------
dex_doctor:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14                    ; 5 pushes
    sub rsp, 32                 ; shadow p/ calls; (40+32)=72 .eq. 8
    mov rbx, rcx                ; cfg
    mov r12, rdx                ; img (validade já provada pelo chamador)
    ; Linha 1: "Doctor: dexter M.m.p"
    lea rcx, [rel s_dr_hdr]
    call dex_console_print_cstr
    mov ecx, DEX_VER_MAJOR
    call dex_console_print_u64dec
    lea rcx, [rel s_dr_dot]
    call dex_console_print_cstr
    mov ecx, DEX_VER_MINOR
    call dex_console_print_u64dec
    lea rcx, [rel s_dr_dot]
    call dex_console_print_cstr
    mov ecx, DEX_VER_PATCH
    call dex_console_print_u64dec
    lea rcx, [rel s_dr_nl]
    call dex_console_print_cstr
    ; Linha 2: "  nasm: <path> ok|missing"
    lea rcx, [rel s_dr_nasm]
    call dex_console_print_cstr
    mov r13, [rbx+DexConfig.nasm_path]
    mov rcx, r13
    call dex_console_print_cstr
    mov rcx, r13
    call dex_open_read
    test rax, rax
    jz .nasm_miss
    mov r14, rax
    lea rcx, [rel s_dr_ok]
    call dex_console_print_cstr
    mov rcx, r14
    call dex_close
    jmp .link
.nasm_miss:
    lea rcx, [rel s_dr_miss]
    call dex_console_print_cstr
.link:
    ; Linha 3: "  link: <path> ok|missing"
    lea rcx, [rel s_dr_link]
    call dex_console_print_cstr
    mov r13, [rbx+DexConfig.linker_path]
    mov rcx, r13
    call dex_console_print_cstr
    mov rcx, r13
    call dex_open_read
    test rax, rax
    jz .link_miss
    mov r14, rax
    lea rcx, [rel s_dr_ok]
    call dex_console_print_cstr
    mov rcx, r14
    call dex_close
    jmp .tail
.link_miss:
    lea rcx, [rel s_dr_miss]
    call dex_console_print_cstr
.tail:
    ; kernel32: este processo a usa (imports do próprio dexter) — fato.
    lea rcx, [rel s_dr_k32]
    call dex_console_print_cstr
    ; input: pe_load + parses passaram antes do despacho — fato.
    lea rcx, [rel s_dr_input]
    call dex_console_print_cstr
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

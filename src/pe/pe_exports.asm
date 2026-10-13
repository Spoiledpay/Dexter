;=============================================================================
; Dexter/src/pe/pe_exports.asm
; dex_pe_parse_exports — valida o Export Directory e conta/coleta RVAs.
; Layout em img.exports_ptr: qword count seguido de count dwords (RVA, cap
; 4096). Diretório ausente/corrompido => count 0, nunca crasha.
;
; Requisitos atendidos: R-3.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"
%include "pe.inc"

global dex_pe_parse_exports

extern dex_rva_to_offset
extern dex_malloc

section .text

;-----------------------------------------------------------------------------
; dex_pe_parse_exports — rcx=PeImage* -> rax=count
;-----------------------------------------------------------------------------
dex_pe_parse_exports:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    test rcx, rcx
    jz .zero_e
    mov rbx, rcx
    mov rsi, [rbx+PeImage.file_buffer]
    test rsi, rsi
    jz .zero_e
    mov r12, [rbx+PeImage.file_size]
    mov rax, [rbx+PeImage.opt_header]
    test rax, rax
    jz .zero_e
    cmp dword [rbx+PeImage.arch], DEX_ARCH_X32
    je .edir32
    mov ecx, [rax+ OH64_NUM_RVA_SIZES]
    test ecx, ecx
    jz .zero_e
    mov ecx, [rax+ OH64_DATA_DIR + 8*0]       ; export rva
    mov edx, [rax+ OH64_DATA_DIR + 8*0 + 4]   ; export size
    jmp .edir_ok
.edir32:
    mov ecx, [rax+ OH32_NUM_RVA_SIZES]
    test ecx, ecx
    jz .zero_e
    mov ecx, [rax+ OH32_DATA_DIR + 8*0]       ; export rva
    mov edx, [rax+ OH32_DATA_DIR + 8*0 + 4]   ; export size
.edir_ok:
    test ecx, ecx
    jz .zero_e
    test edx, edx
    jz .zero_e
    mov r13d, ecx              ; export_rva (r13 livre aqui)
    mov rcx, rbx
    mov edx, r13d
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    test rax, rax
    jz .zero_e
    ; validar EDIRECTORY (40 bytes)
    mov rdi, rax               ; exp_off
    mov rax, rdi
    add rax, 40
    cmp rax, r12
    ja .zero_e
    lea rax, [rsi+rdi]         ; &dir
    mov ecx, [rax+24]          ; NumberOfNames
    mov edx, [rax+32]          ; AddressOfNames (rva)
    cmp ecx, 4096
    ja .zero_e                 ; absurdo: trata como ausente
    test ecx, ecx
    jz .zero_e
    mov r13d, ecx              ; n
    ; validar tabela de nomes (n*4)
    mov rcx, rbx
    ; edx = names_rva
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    test rax, rax
    jz .zero_e
    mov r14, rax               ; names_off
    mov rax, r14
    mov rcx, r13
    shl rcx, 2
    add rax, rcx
    cmp rax, r12
    ja .zero_e
    ; alocar 8 + n*4
    mov rax, r13
    shl rax, 2
    add rax, 8
    mov rcx, rax
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .zero_e
    mov r15, rax
    mov [r15], r13
    ; copiar RVAs dos nomes (u32 cada)
    xor r10d, r10d
.cp:
    cmp r10d, r13d
    jae .cp_done
    mov eax, [rsi+r14]
    add r14, 4
    mov ecx, r10d
    mov [r15+8+rcx*4], eax
    inc r10d
    jmp .cp
.cp_done:
    mov [rbx+PeImage.exports_ptr], r15
    mov rax, r13
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.zero_e:
    xor eax, eax
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

;=============================================================================
; Dexter/src/diag/overview.asm
; dex_overview — resumo inspect-only do PE (texto humano ou JSON).
;
; O quê: imprime base/entry/seções/imports/exports/relocs sem gerar .asm.
; Por quê: inspeção rápida legível por humanos (default) e por agentes
;  /scripts (-json), no espírito do modo inspect do REA (Fase 3, marco.md).
; Contrato:
;   Args: rcx = DexConfig* (flags DF_OVERVIEW/DF_JSON), rdx = PeImage*
;         (já validado + imports/exports/relocs parseados).
;   Ret:  eax = 0 sempre (best-effort, como -v; nunca falha por conteúdo).
;   Clobber: rax, rcx, rdx, r8-r11.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\run_tests.bat seção [16] (texto + json + inspect-only).
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_overview

extern dex_console_print_cstr
extern dex_console_print_u64hex
extern dex_console_print_u64dec
extern dex_console_newline

section .rodata
s_ov_hdr     db "Overview: ", 0
s_ov_base    db "ImageBase: 0x", 0
s_ov_entry   db "EntryPoint RVA: 0x", 0
s_ov_nsec    db "Sections: ", 0
s_ov_sec     db "  [", 0
s_ov_mid1    db "] vaddr=0x", 0
s_ov_mid2    db " vsize=0x", 0
s_ov_mid3    db " raw=0x", 0
s_ov_nl      db 13, 10, 0
s_ov_imp     db "Imports: ", 0
s_ov_imp1    db "  ", 0
s_ov_bang    db "!", 0
s_ov_iat     db " iat=0x", 0
s_ov_ord     db " ord=", 0
s_ov_exp     db "Exports: ", 0
s_ov_rel     db "Relocs: ", 0
; ---- JSON (1 linha, chaves estáveis; hex como string, counts decimais) ----
s_j_open     db '{"tool":"dexter","version":"', 0
s_j_dot      db ".", 0
s_j_base     db '","image_base":"0x', 0
s_j_entry    db '","entry_rva":"0x', 0
s_j_nsec     db '","num_sections":', 0
s_j_secs     db ',"sections":[', 0
s_j_sopen    db '{"name":"', 0
s_j_sva      db '","vaddr":"0x', 0
s_j_svsz     db '","vsize":"0x', 0
s_j_sraw     db '","raw_size":"0x', 0
s_j_sclose   db '"}', 0
s_j_comma    db ",", 0
s_j_secs_e   db "],", 0
s_j_nimp     db '"imports_count":', 0
s_j_imps     db ',"imports":[', 0
s_j_iopen    db '{"dll":"', 0
s_j_ifunc    db '","func":"', 0
s_j_iord     db '","ordinal":', 0
s_j_iordb    db ',"is_ordinal":', 0
s_j_iiat     db ',"iat_rva":"0x', 0
s_j_iclose   db '"}', 0
s_j_imps_e   db "],", 0
s_j_exp      db '"exports_count":', 0
s_j_rel      db ',"relocs_count":', 0
s_j_close    db "}", 0

section .text

;-----------------------------------------------------------------------------
; dex_overview — rcx=cfg, rdx=img -> eax=0.
;-----------------------------------------------------------------------------
dex_overview:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15                     ; 6 pushes (48B) + sub 576 = 624 ≡ 8
    sub rsp, 576                 ; jtmp 256B em [rbp-320,rbp-64)
    mov rbx, rcx                 ; cfg
    mov r15, rdx                 ; img
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .text
    jmp .json
;-----------------------------------------------------------------------------
; Modo texto (mesmo vocabulário do -v).
;-----------------------------------------------------------------------------
.text:
    lea rcx, [rel s_ov_hdr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbx+DexConfig.input_path]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_ov_base]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+PeImage.image_base]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_ov_entry]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+PeImage.entry_point]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_ov_nsec]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.num_sections]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    mov r12d, [r15+PeImage.num_sections]
    mov r13, [r15+PeImage.sections_ptr]
    xor r14d, r14d
.t_sec:
    cmp r14d, r12d
    jae .t_imp
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]           ; sec (rsi preservado pelas prints)
    mov [rbp-328], rsi           ; spill sec (slot livre abaixo do jtmp)
    lea rcx, [rel s_ov_sec]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    ; nome (8B, pode não ter NUL): copiar + terminar no jtmp
    lea rdi, [rbp-320]
    mov rax, [rsi+PeSection.name]
    mov [rdi], rax
    mov byte [rdi+8], 0
    mov rcx, rdi
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    lea rcx, [rel s_ov_mid1]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rsi+PeSection.vaddr]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_ov_mid2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    mov ecx, [rsi+PeSection.vsize]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_ov_mid3]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    mov ecx, [rsi+PeSection.raw_size]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_ov_nl]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    inc r14d
    jmp .t_sec
.t_imp:
    lea rcx, [rel s_ov_imp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.imports_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    mov r12d, [r15+PeImage.imports_count]
    mov r13, [r15+PeImage.imports_ptr]
    xor r14d, r14d
.t_imp_l:
    cmp r14d, r12d
    jae .t_exp
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]           ; entry
    mov [rbp-328], rsi
    lea rcx, [rel s_ov_imp1]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    mov rcx, [rsi+ImportEntry.dll_name]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_ov_bang]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    cmp byte [rsi+ImportEntry.is_ordinal], 0
    jne .t_ord
    mov rcx, [rsi+ImportEntry.func_name]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    jmp .t_iat
.t_ord:
    lea rcx, [rel s_ov_ord]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    movzx ecx, word [rsi+ImportEntry.ordinal]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
.t_iat:
    lea rcx, [rel s_ov_iat]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    mov ecx, [rsi+ImportEntry.iat_rva]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    inc r14d
    jmp .t_imp_l
.t_exp:
    lea rcx, [rel s_ov_exp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov r13, [r15+PeImage.exports_ptr]
    test r13, r13
    jz .t_exp0
    mov rcx, [r13]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    jmp .t_rel
.t_exp0:
    mov ecx, 0
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
.t_rel:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_ov_rel]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.relocs_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .done
;-----------------------------------------------------------------------------
; Modo JSON (1 linha; ver cabeçalho p/ contrato).
;-----------------------------------------------------------------------------
.json:
    lea rcx, [rel s_j_open]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, DEX_VER_MAJOR
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_dot]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, DEX_VER_MINOR
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_dot]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, DEX_VER_PATCH
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_base]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+PeImage.image_base]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_entry]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+PeImage.entry_point]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_nsec]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.num_sections]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_secs]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov r12d, [r15+PeImage.num_sections]
    mov r13, [r15+PeImage.sections_ptr]
    xor r14d, r14d
.j_sec:
    cmp r14d, r12d
    jae .j_secs_e
    test r14d, r14d
    jz .j_sec0
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.j_sec0:
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]
    mov [rbp-328], rsi
    lea rcx, [rel s_j_sopen]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    ; nome com escape (máx 8 do PE, cap 255)
    mov rsi, [rbp-328]
    lea rdi, [rsi+PeSection.name]
    mov rsi, rdi
    lea rdi, [rbp-320]
    mov edx, 8
    call .jstrn
    lea rcx, [rbp-320]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    lea rcx, [rel s_j_sva]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rsi+PeSection.vaddr]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_svsz]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    mov ecx, [rsi+PeSection.vsize]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_sraw]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    mov ecx, [rsi+PeSection.raw_size]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_sclose]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    inc r14d
    jmp .j_sec
.j_secs_e:
    lea rcx, [rel s_j_secs_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_nimp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.imports_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_imps]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov r12d, [r15+PeImage.imports_count]
    mov r13, [r15+PeImage.imports_ptr]
    xor r14d, r14d
.j_imp_l:
    cmp r14d, r12d
    jae .j_imps_e
    test r14d, r14d
    jz .j_imp0
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.j_imp0:
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]
    mov [rbp-328], rsi
    lea rcx, [rel s_j_iopen]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    mov rsi, [rsi+ImportEntry.dll_name]
    lea rdi, [rbp-320]
    mov edx, 255
    call .jstrn
    lea rcx, [rbp-320]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_ifunc]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    cmp byte [rsi+ImportEntry.is_ordinal], 0
    jne .j_imp_ordv               ; ordinal: func="" (nada entre as aspas)
    mov rsi, [rsi+ImportEntry.func_name]
    lea rdi, [rbp-320]
    mov edx, 255
    call .jstrn
    lea rcx, [rbp-320]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.j_imp_ordv:
    lea rcx, [rel s_j_iord]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    movzx ecx, word [rsi+ImportEntry.ordinal]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_iordb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    movzx ecx, byte [rsi+ImportEntry.is_ordinal]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_iiat]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-328]
    mov ecx, [rsi+ImportEntry.iat_rva]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_iclose]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    inc r14d
    jmp .j_imp_l
.j_imps_e:
    lea rcx, [rel s_j_imps_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_exp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov r13, [r15+PeImage.exports_ptr]
    test r13, r13
    jz .j_exp0
    mov rcx, [r13]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    jmp .j_rel
.j_exp0:
    mov ecx, 0
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
.j_rel:
    lea rcx, [rel s_j_rel]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.relocs_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_close]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.done:
    xor eax, eax
    add rsp, 576
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
;-----------------------------------------------------------------------------
; .jstrn — rsi=src, rdi=dst, edx=maxlen(src) -> copia com escapes JSON
; (" \\ ?), NUL-termina, dst limitado a 255+1 (nunca estoura o jtmp).
; Sem calls (leaf). Clobber: rax, rcx, rdx, r8.
;-----------------------------------------------------------------------------
.jstrn:
    xor ecx, ecx                 ; src idx
    xor r8d, r8d                 ; dst len
.jn_l:
    cmp ecx, edx
    jae .jn_end
    cmp r8d, 254
    jae .jn_end
    mov al, [rsi+rcx]
    test al, al
    jz .jn_end
    cmp al, '"'
    je .jn_esc
    cmp al, '\'
    je .jn_esc
    cmp al, 0x20
    jb .jn_q
    mov [rdi], al                ; raw
    inc rdi
    inc r8d
    inc rcx
    jmp .jn_l
.jn_q:
    mov byte [rdi], '?'          ; controle -> ?
    inc rdi
    inc r8d
    inc rcx
    jmp .jn_l
.jn_esc:
    cmp r8d, 253                 ; precisa de 2 bytes
    ja .jn_end
    mov byte [rdi], '\'
    inc rdi
    mov [rdi], al
    inc rdi
    add r8d, 2
    inc rcx
    jmp .jn_l
.jn_end:
    mov byte [rdi], 0
    ret

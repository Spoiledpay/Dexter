;=============================================================================
; Dexter/src/diag/compare.asm
; dex_compare — diff de dois binários PE x64 (hash FNV-1a + size + layout).
;
; O quê: abre/mapeia/valida o segundo arquivo, calcula FNV-1a dos dois,
;  compara size/hash/base/entry/seções/imports/exports/relocs e imprime
;  veredito (identical/different) + diffs em texto ou JSON.
; Por quê: responder "o que mudou entre A e B" sem gerar .asm (snapshots
;  estilo REA: save/compare — R-7.4, marco.md).
; Contrato:
;   Args: rcx = DexConfig* (DF_JSON), rdx = PeImage* primário (validado),
;         r8 = path do segundo arquivo (NUL).
;   Ret:  eax = 0 ok (identical ou different, ambos sucesso) | 2 I/O no
;         segundo (mensagem própria em stderr) | 3 segundo PE inválido.
;   identical = hash igual E todos os campos iguais (só-timestamp muda
;   o hash: veredito different com campos same — honesto).
;   Seções casam por nome (8B); imports por dll+func/ordinal; sem cap
;   de exibição (limitado pelos tamanhos reais).
;   Clobber: rax, rcx, rdx, r8-r11.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
;   Nota de ABI: helpers leaf sem uso de pilha (.t_exp_count_*,
;   .c_esc) são chamados sem shadow (precedente: .san_ch); todo call
;   p/ função COM frame tem sub rsp,32.
; Como testar: tests\run_tests.bat seção [19].
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"
%include "pe.inc"

global dex_compare

extern dex_open_read
extern dex_file_size
extern dex_mmap_read
extern dex_unmap
extern dex_close
extern dex_pe_load
extern dex_pe_parse_imports
extern dex_pe_parse_exports
extern dex_pe_parse_relocs
extern dex_fnv1a
extern dex_memcmp
extern dex_streq
extern dex_console_print_cstr
extern dex_console_print_err
extern dex_console_print_u64hex
extern dex_console_print_u64dec
extern dex_console_newline

section .rodata
s_c_cmp      db "Compare: ", 0
s_c_vs       db " vs ", 0
s_c_ident    db "  identical", 0
s_c_differ   db "  different", 0
s_c_size     db "  size: ", 0
s_c_fnv      db "  fnv1a: ", 0
s_c_base     db "  base: ", 0
s_c_entry    db "  entry: ", 0
s_c_secs     db "  sections: ", 0
s_c_imps     db "  imports: ", 0
s_c_exp      db "  exports: ", 0
s_c_rel      db "  relocs: ", 0
s_c_vs2      db " vs ", 0
s_c_same     db " (same)", 0
s_c_diff     db " (DIFF)", 0
s_c_add      db "    + ", 0
s_c_rem      db "    - ", 0
s_c_chg      db "    ~ ", 0
s_c_bang     db "!", 0
s_c_ord      db "ord", 0
s_c_0x       db "0x", 0
s_c_nl       db 13, 10, 0
s_c_io2      db "dexter: cannot open/read second file", 13, 10, 0
s_c_pe2      db "dexter: invalid second PE file", 13, 10, 0
s_j_open     db '{"tool":"dexter","version":"', 0
s_j_dot      db ".", 0
s_j_a        db '","a":"', 0
s_j_b        db '","b":"', 0
s_j_ident_e  db ',"identical":', 0
s_j_true     db "true", 0
s_j_false    db "false", 0
s_j_size     db '","size":{"a":', 0
s_j_vsb      db ',"b":', 0
s_j_same     db ',"same":', 0
s_j_cls      db "}", 0
s_j_fnv      db ',"fnv1a":{"a":"0x', 0
s_j_base     db ',"base":{"a":"0x', 0
s_j_entry    db ',"entry":{"a":"0x', 0
s_j_secs     db ',"sections":{"a":', 0
s_j_added    db ',"added":[', 0
s_j_removed  db ',"removed":[', 0
s_j_changed  db "],", 0
s_j_chg2     db '"changed":[', 0
s_j_arr_e    db "]", 0
s_j_imps     db ',"imports":{"a":', 0
s_j_exp      db ',"exports":{"a":', 0
s_j_rel      db ',"relocs":{"a":', 0
s_j_q        db '"', 0
s_j_comma    db ",", 0

section .bss
align 16
g_cimg:   resb 128                ; PeImage secundário
g_csec:   resb 3072               ; 96 seções secundárias

section .text

;-----------------------------------------------------------------------------
; dex_compare — rcx=cfg, rdx=imgA, r8=pathB -> eax=0 | 2 | 3.
; Frame: 8 pushes + sub 328 = 392. jtmp [rbp-384]=[RSP] (NUNCA
; usar [-368,-320) p/ flags: colide!); [rbp-120]=first, [rbp-128]=pathB.
; Slots: -72 chandle, -80 csize, -88 cbase, -96 chash, -104 ahash,
;  -112 verdict (1=identical até prova contrária).
;-----------------------------------------------------------------------------
dex_compare:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15                     ; 8 pushes (64B) + sub 328 = 392
    sub rsp, 328
    mov rbx, rcx                 ; cfg
    mov r15, rdx                 ; imgA
    mov rdi, r8                  ; pathB
    mov [rbp-128], rdi           ; spill pathB (rdi morre nos escapes!)
    mov qword [rbp-72], 0        ; chandle (0 = fechado)
    mov qword [rbp-88], 0        ; cbase (0 = sem mapeamento)
    ; ---- abre segundo ----
    mov rcx, rdi
    sub rsp, 32
    call dex_open_read
    add rsp, 32
    test rax, rax
    jz .err_io2
    mov [rbp-72], rax            ; chandle
    mov rcx, rax
    sub rsp, 32
    call dex_file_size
    add rsp, 32
    cmp rax, -1
    je .err_io2_close
    mov [rbp-80], rax            ; csize
    mov rcx, [rbp-72]
    mov rdx, rax
    sub rsp, 32
    call dex_mmap_read
    add rsp, 32
    test rax, rax
    jz .err_io2_close
    mov [rbp-88], rax            ; cbase
    ; ---- valida segundo (PeImage próprio em .bss) ----
    lea rax, [rel g_csec]
    mov [rel g_cimg+PeImage.sections_ptr], rax
    lea rcx, [rel g_cimg]
    mov rdx, [rbp-88]
    mov r8, [rbp-80]
    sub rsp, 32
    call dex_pe_load
    add rsp, 32
    test eax, eax
    jnz .err_pe2
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NO_IMPORTS
    jnz .sk_imp2
    lea rcx, [rel g_cimg]
    sub rsp, 32
    call dex_pe_parse_imports
    add rsp, 32
.sk_imp2:
    lea rcx, [rel g_cimg]
    sub rsp, 32
    call dex_pe_parse_exports
    add rsp, 32
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NO_RELOCS
    jnz .sk_rel2
    lea rcx, [rel g_cimg]
    sub rsp, 32
    call dex_pe_parse_relocs
    add rsp, 32
.sk_rel2:
    ; ---- hash dos dois ----
    mov rcx, [r15+PeImage.file_buffer]
    mov rdx, [r15+PeImage.file_size]
    sub rsp, 32
    call dex_fnv1a
    add rsp, 32
    mov [rbp-104], rax           ; ahash
    mov rcx, [rbp-88]
    mov rdx, [rbp-80]
    sub rsp, 32
    call dex_fnv1a
    add rsp, 32
    mov [rbp-96], rax            ; chash
    mov dword [rbp-112], 1       ; verdict=identical (refuta abaixo)
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .p_text
    jmp .p_json
;-----------------------------------------------------------------------------
; Texto.
;-----------------------------------------------------------------------------
.p_text:
    lea rcx, [rel s_c_cmp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbx+DexConfig.input_path]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_vs]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, rdi
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; size
    lea rcx, [rel s_c_size]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+PeImage.file_size]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_c_vs2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-80]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    mov rax, [r15+PeImage.file_size]
    cmp rax, [rbp-80]
    je .t_sz_same
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_diff]
    jmp .t_sz_go
.t_sz_same:
    lea rcx, [rel s_c_same]
.t_sz_go:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; fnv1a
    lea rcx, [rel s_c_fnv]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-104]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_c_vs2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-96]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    mov rax, [rbp-104]
    cmp rax, [rbp-96]
    je .t_h_same
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_diff]
    jmp .t_h_go
.t_h_same:
    lea rcx, [rel s_c_same]
.t_h_go:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; base
    lea rcx, [rel s_c_base]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+PeImage.image_base]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_c_vs2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.image_base]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    mov rax, [r15+PeImage.image_base]
    lea rdx, [rel g_cimg]
    cmp rax, [rdx+PeImage.image_base]
    je .t_b_same
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_diff]
    jmp .t_b_go
.t_b_same:
    lea rcx, [rel s_c_same]
.t_b_go:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; entry
    lea rcx, [rel s_c_entry]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+PeImage.entry_point]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_c_vs2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.entry_point]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    mov rax, [r15+PeImage.entry_point]
    lea rdx, [rel g_cimg]
    cmp rax, [rdx+PeImage.entry_point]
    je .t_e_same
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_diff]
    jmp .t_e_go
.t_e_same:
    lea rcx, [rel s_c_same]
.t_e_go:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; sections
    lea rcx, [rel s_c_secs]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.num_sections]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_c_vs2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov ecx, [rax+PeImage.num_sections]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    mov eax, [r15+PeImage.num_sections]
    lea rdx, [rel g_cimg]
    cmp eax, [rdx+PeImage.num_sections]
    je .t_s_nodiffcount
    mov dword [rbp-112], 0
.t_s_nodiffcount:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    sub rsp, 32
    call .t_diff_secs
    add rsp, 32
    ; imports
    lea rcx, [rel s_c_imps]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.imports_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_c_vs2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov ecx, [rax+PeImage.imports_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    mov eax, [r15+PeImage.imports_count]
    lea rdx, [rel g_cimg]
    cmp eax, [rdx+PeImage.imports_count]
    je .t_i_nodiffcount
    mov dword [rbp-112], 0
.t_i_nodiffcount:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    sub rsp, 32
    call .t_diff_imps
    add rsp, 32
    ; exports
    lea rcx, [rel s_c_exp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .t_exp_count_a
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_c_vs2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .t_exp_count_b
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    call .t_exp_count_a
    mov edx, eax
    call .t_exp_count_b
    mov ecx, eax
    cmp edx, ecx
    je .t_x_same
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_diff]
    jmp .t_x_go
.t_x_same:
    lea rcx, [rel s_c_same]
.t_x_go:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; relocs
    lea rcx, [rel s_c_rel]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.relocs_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_c_vs2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov ecx, [rax+PeImage.relocs_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    mov eax, [r15+PeImage.relocs_count]
    lea rdx, [rel g_cimg]
    cmp eax, [rdx+PeImage.relocs_count]
    je .t_r_same
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_diff]
    jmp .t_r_go
.t_r_same:
    lea rcx, [rel s_c_same]
.t_r_go:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; veredito
    cmp dword [rbp-112], 0
    je .t_verd_diff
    lea rcx, [rel s_c_ident]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    jmp .t_verd_nl
.t_verd_diff:
    lea rcx, [rel s_c_differ]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.t_verd_nl:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .cleanup_ok
;-----------------------------------------------------------------------------
; JSON (mesmas dimensões, espelho fiel do texto).
;-----------------------------------------------------------------------------
.p_json:
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
    lea rcx, [rel s_j_a]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbx+DexConfig.input_path]
    lea rdi, [rbp-384]
    mov edx, 255
    call .c_esc
    lea rcx, [rbp-384]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_b]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rbp-128]           ; pathB (spill; rdi morreu nos escapes)
    lea rdi, [rbp-384]
    mov edx, 255
    sub rsp, 32
    call .c_esc
    add rsp, 32
    lea rcx, [rbp-384]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_size]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+PeImage.file_size]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_vsb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-80]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_same]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rax, [r15+PeImage.file_size]
    cmp rax, [rbp-80]
    sete cl
    movzx ecx, cl
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_fnv]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-104]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_vsb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-96]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_same]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rax, [rbp-104]
    cmp rax, [rbp-96]
    sete cl
    movzx ecx, cl
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
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
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_vsb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.image_base]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_same]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rax, [r15+PeImage.image_base]
    lea rdx, [rel g_cimg]
    cmp rax, [rdx+PeImage.image_base]
    sete cl
    movzx ecx, cl
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
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
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_vsb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_0x]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.entry_point]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_same]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rax, [r15+PeImage.entry_point]
    lea rdx, [rel g_cimg]
    cmp rax, [rdx+PeImage.entry_point]
    sete cl
    movzx ecx, cl
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_secs]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.num_sections]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_vsb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov ecx, [rax+PeImage.num_sections]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_added]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov dword [rbp-120], 0       ; first (vírgulas do array added)
    sub rsp, 32
    call .j_diff_secs_added
    add rsp, 32
    lea rcx, [rel s_j_arr_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_removed]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov dword [rbp-120], 0
    sub rsp, 32
    call .j_diff_secs_removed
    add rsp, 32
    lea rcx, [rel s_j_changed]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_chg2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov dword [rbp-120], 0
    sub rsp, 32
    call .j_diff_secs_changed
    add rsp, 32
    lea rcx, [rel s_j_arr_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_imps]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.imports_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_vsb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov ecx, [rax+PeImage.imports_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_added]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov dword [rbp-120], 0
    sub rsp, 32
    call .j_diff_imps_added
    add rsp, 32
    lea rcx, [rel s_j_arr_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_removed]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov dword [rbp-120], 0
    sub rsp, 32
    call .j_diff_imps_removed
    add rsp, 32
    lea rcx, [rel s_j_arr_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_exp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .t_exp_count_a
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_vsb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .t_exp_count_b
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_same]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .t_exp_count_a
    mov edx, eax
    call .t_exp_count_b
    mov ecx, eax
    cmp edx, ecx
    sete cl
    movzx ecx, cl
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_rel]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+PeImage.relocs_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_vsb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rax, [rel g_cimg]
    mov ecx, [rax+PeImage.relocs_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_same]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov eax, [r15+PeImage.relocs_count]
    lea rdx, [rel g_cimg]
    cmp eax, [rdx+PeImage.relocs_count]
    sete cl
    movzx ecx, cl
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_ident_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    cmp dword [rbp-112], 0
    je .j_ident_f
    lea rcx, [rel s_j_true]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    jmp .j_after_ident
.j_ident_f:
    lea rcx, [rel s_j_false]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.j_after_ident:
    lea rcx, [rel s_j_cls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .cleanup_ok
;-----------------------------------------------------------------------------
; Helpers de diff (com shadow pelo chamador; preservam non-voláteis).
; .t_diff_secs / .t_diff_imps: texto (+/-/~/por nome e dll!func).
; .j_diff_*: JSON ("nome" / "dll!func" com escape? nomes vêm do PE:
;  usa .c_esc p/ aspas em JSON; texto imprime cru).
; .t_exp_count_a/b: exports count de A/B em eax.
; .c_esc: rsi=NUL, rdi=dst256, edx=max -> escape JSON. Leaf.
;-----------------------------------------------------------------------------
.t_exp_count_a:
    mov rax, [r15+PeImage.exports_ptr]
    test rax, rax
    jz .tea0
    mov eax, [rax]
    ret
.tea0:
    xor eax, eax
    ret
.t_exp_count_b:
    lea rax, [rel g_cimg]
    mov rax, [rax+PeImage.exports_ptr]
    test rax, rax
    jz .teb0
    mov eax, [rax]
    ret
.teb0:
    xor eax, eax
    ret
.t_diff_secs:
    ; A→B: removidas (-) ou mudadas (~); B→A: adicionadas (+)
    mov r12d, [r15+PeImage.num_sections]
    mov r13, [r15+PeImage.sections_ptr]
    xor r14d, r14d
.tds_a:
    cmp r14d, r12d
    jae .tds_b
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]           ; secA (rsi morre abaixo? prints preservam!)
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.sections_ptr]
    mov edx, [rax+PeImage.num_sections]
    mov r8d, r14d                ; (r8 livre aqui? call .t_find_sec clobber só rax,rcx,rdx)
    sub rsp, 32
    call .t_find_sec             ; rax=secB|0 (rsi=secA preservado? .t_find_sec
                                 ; usa rsi? NÃO: só rax,rcx,rdx. rsi intacto? .t_find_sec
                                 ; clobber: rax,rcx,rdx. rsi/rdi/r12-r15 intactos ✓)
    add rsp, 32
    test rax, rax
    jz .tds_rem
    ; compara vaddr/vsize/raw_size/raw_ptr
    mov ecx, [rsi+PeSection.vaddr]
    cmp ecx, [rax+PeSection.vaddr]
    jne .tds_chg
    mov ecx, [rsi+PeSection.vsize]
    cmp ecx, [rax+PeSection.vsize]
    jne .tds_chg
    mov ecx, [rsi+PeSection.raw_size]
    cmp ecx, [rax+PeSection.raw_size]
    jne .tds_chg
    mov ecx, [rsi+PeSection.raw_ptr]
    cmp ecx, [rax+PeSection.raw_ptr]
    jne .tds_chg
    jmp .tds_anext
.tds_chg:
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_chg]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .t_print_secname
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .tds_anext
.tds_rem:
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_rem]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .t_print_secname
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.tds_anext:
    inc r14d
    jmp .tds_a
.tds_b:
    lea rax, [rel g_cimg]
    mov r12d, [rax+PeImage.num_sections]
    mov r13, [rax+PeImage.sections_ptr]
    xor r14d, r14d
.tds_b_l:
    cmp r14d, r12d
    jae .tds_done
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]           ; secB
    mov rcx, [r15+PeImage.sections_ptr]
    mov edx, [r15+PeImage.num_sections]
    sub rsp, 32
    call .t_find_sec_a           ; rax=secA|0
    add rsp, 32
    test rax, rax
    jnz .tds_bnext
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_add]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .t_print_secname
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.tds_bnext:
    inc r14d
    jmp .tds_b_l
.tds_done:
    ret
; .t_find_sec — rsi=secA(8B nome), rcx=baseB, edx=nB -> rax=secB|0.
.t_find_sec:
    test edx, edx
    jz .tfs_no
    push rsi
    push rdi
.tfs_l:
    test edx, edx
    jz .tfs_pop_no
    dec edx
    mov eax, edx
    imul eax, SIZEOF_PE_SECTION
    lea rax, [rcx+rax]
    push rcx
    push rdx
    push rax                     ; preserva candidato (memcmp mata rax!)
    mov rcx, rsi
    mov rdx, rax
    mov r8d, 8
    sub rsp, 32
    call dex_memcmp
    add rsp, 32
    test eax, eax
    pop rax                      ; restaura candidato
    pop rdx
    pop rcx
    jz .tfs_hit
    jmp .tfs_l
.tfs_hit:
    pop rdi
    pop rsi
    ret                          ; rax=secB
.tfs_pop_no:
    pop rdi
    pop rsi
.tfs_no:
    xor eax, eax
    ret
; .t_find_sec_a — rsi=secB, rcx=baseA, edx=nA -> rax=secA|0 (espelho).
.t_find_sec_a:
    test edx, edx
    jz .tfs_no
    push rsi
    push rdi
.tfs_al:
    test edx, edx
    jz .tfs_pop_no
    dec edx
    mov eax, edx
    imul eax, SIZEOF_PE_SECTION
    lea rax, [rcx+rax]
    push rcx
    push rdx
    push rax                     ; preserva candidato (memcmp mata rax!)
    mov rcx, rsi
    mov rdx, rax
    mov r8d, 8
    sub rsp, 32
    call dex_memcmp
    add rsp, 32
    test eax, eax
    pop rax                      ; restaura candidato
    pop rdx
    pop rcx
    jz .tfs_hit
    jmp .tfs_al
; .t_print_secname — rsi=sec (nome 8B, pode sem NUL) -> stdout.
.t_print_secname:
    sub rsp, 56
    lea rdi, [rsp+32]
    mov rax, [rsi+PeSection.name]
    mov [rdi], rax
    mov byte [rdi+8], 0
    mov rcx, rdi
    call dex_console_print_cstr
    add rsp, 56
    ret
.t_diff_imps:
    mov r12d, [r15+PeImage.imports_count]
    mov r13, [r15+PeImage.imports_ptr]
    xor r14d, r14d
.tdi_a:
    cmp r14d, r12d
    jae .tdi_b
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]           ; impA
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.imports_ptr]
    mov edx, [rax+PeImage.imports_count]
    sub rsp, 32
    call .t_find_imp             ; rax=impB|0
    add rsp, 32
    test rax, rax
    jnz .tdi_anext
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_rem]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .t_print_impname
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.tdi_anext:
    inc r14d
    jmp .tdi_a
.tdi_b:
    lea rax, [rel g_cimg]
    mov r12d, [rax+PeImage.imports_count]
    mov r13, [rax+PeImage.imports_ptr]
    xor r14d, r14d
.tdi_b_l:
    cmp r14d, r12d
    jae .tdi_done
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]           ; impB
    mov rcx, [r15+PeImage.imports_ptr]
    mov edx, [r15+PeImage.imports_count]
    sub rsp, 32
    call .t_find_imp_a           ; rax=impA|0
    add rsp, 32
    test rax, rax
    jnz .tdi_bnext
    mov dword [rbp-112], 0
    lea rcx, [rel s_c_add]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .t_print_impname
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.tdi_bnext:
    inc r14d
    jmp .tdi_b_l
.tdi_done:
    ret
; .t_find_imp — rsi=impA, rcx=baseB, edx=nB -> rax=impB|0 (dll+func/ord).
.t_find_imp:
    test edx, edx
    jz .tfi_no
    push rsi
    push rdi
    push r12
.tfi_l:
    test edx, edx
    jz .tfi_pop_no
    dec edx
    mov eax, edx
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rax, [rcx+rax]           ; impB
    push rcx
    push rdx
    push rax
    mov rcx, [rsi+ImportEntry.dll_name]
    mov rdx, [rax+ImportEntry.dll_name]
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .tfi_next
    pop rax
    push rax
    mov rcx, [rsi+ImportEntry.func_name]
    mov rdx, [rax+ImportEntry.func_name]
    test rcx, rcx
    jnz .tfi_byname
    test rdx, rdx
    jnz .tfi_next_pop
    mov cx, [rsi+ImportEntry.ordinal]
    cmp cx, [rax+ImportEntry.ordinal]
    jne .tfi_next_pop
    mov cl, [rsi+ImportEntry.is_ordinal]
    cmp cl, [rax+ImportEntry.is_ordinal]
    jne .tfi_next_pop
    jmp .tfi_hit_pop
.tfi_byname:
    test rdx, rdx
    jz .tfi_next_pop
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .tfi_next_pop
.tfi_hit_pop:
    pop rax
    pop rdx
    pop rcx
    pop r12
    pop rdi
    pop rsi
    ret                          ; rax=impB
.tfi_next_pop:
    ; cai em .tfi_next (3 pops p/ 3 pushes: rcx,rdx,rax)
.tfi_next:
    pop rax                          ; desequilíbrio seria leak: 3 pushes!
    pop rdx
    pop rcx
    jmp .tfi_l
.tfi_pop_no:
    pop r12
    pop rdi
    pop rsi
.tfi_no:
    xor eax, eax
    ret
; .t_find_imp_a — espelho (impB em rsi, baseA/countA) -> rax=impA|0.
.t_find_imp_a:
    test edx, edx
    jz .tfi_no
    push rsi
    push rdi
    push r12
.tfi_al:
    test edx, edx
    jz .tfi_pop_no
    dec edx
    mov eax, edx
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rax, [rcx+rax]
    push rcx
    push rdx
    push rax
    mov rcx, [rsi+ImportEntry.dll_name]
    mov rdx, [rax+ImportEntry.dll_name]
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .tfi_next_a
    pop rax
    push rax
    mov rcx, [rsi+ImportEntry.func_name]
    mov rdx, [rax+ImportEntry.func_name]
    test rcx, rcx
    jnz .tfi_byname_a
    test rdx, rdx
    jnz .tfi_next_pop_a
    mov cx, [rsi+ImportEntry.ordinal]
    cmp cx, [rax+ImportEntry.ordinal]
    jne .tfi_next_pop_a
    mov cl, [rsi+ImportEntry.is_ordinal]
    cmp cl, [rax+ImportEntry.is_ordinal]
    jne .tfi_next_pop_a
    jmp .tfi_hit_pop
.tfi_byname_a:
    test rdx, rdx
    jz .tfi_next_pop_a
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .tfi_next_pop_a
    jmp .tfi_hit_pop
.tfi_next_pop_a:
.tfi_next_a:
    pop rax                          ; idem (espelho): 3 pushes!
    pop rdx
    pop rcx
    jmp .tfi_al
; .t_print_impname — rsi=imp -> "dll!func" ou "dll!ordN" em stdout.
.t_print_impname:
    mov rcx, [rsi+ImportEntry.dll_name]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_bang]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    cmp byte [rsi+ImportEntry.is_ordinal], 0
    jne .tpi_ord
    mov rcx, [rsi+ImportEntry.func_name]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    ret
.tpi_ord:
    lea rcx, [rel s_c_ord]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    movzx ecx, word [rsi+ImportEntry.ordinal]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    ret
; JSON diffs (mesma lógica, com vírgulas via [rbp-120] e escape).
.j_diff_secs_added:
    mov r12d, [r15+PeImage.num_sections]
    mov r13, [r15+PeImage.sections_ptr]
    xor r14d, r14d
.jds_a:
    cmp r14d, r12d
    jae .jds_b
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.sections_ptr]
    mov edx, [rax+PeImage.num_sections]
    sub rsp, 32
    call .t_find_sec
    add rsp, 32
    test rax, rax
    jnz .jds_anext
    mov dword [rbp-112], 0       ; added refuta identical
    cmp dword [rbp-120], 0
    je .jds_a_nc
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jds_a_nc:
    mov dword [rbp-120], 1
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .j_print_secname
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jds_anext:
    inc r14d
    jmp .jds_a
.jds_b:
    ret
.j_diff_secs_removed:
    lea rax, [rel g_cimg]
    mov r12d, [rax+PeImage.num_sections]
    mov r13, [rax+PeImage.sections_ptr]
    xor r14d, r14d
.jdsr_b:
    cmp r14d, r12d
    jae .jdsr_done
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]           ; secB
    mov rcx, [r15+PeImage.sections_ptr]
    mov edx, [r15+PeImage.num_sections]
    sub rsp, 32
    call .t_find_sec_a           ; rax=secA|0
    add rsp, 32
    test rax, rax
    jnz .jdsr_next
    mov dword [rbp-112], 0
    cmp dword [rbp-120], 0
    je .jdsr_nc
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jdsr_nc:
    mov dword [rbp-120], 1
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .j_print_secname
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jdsr_next:
    inc r14d
    jmp .jdsr_b
.jdsr_done:
    ret
.j_diff_secs_changed:
    mov r12d, [r15+PeImage.num_sections]
    mov r13, [r15+PeImage.sections_ptr]
    xor r14d, r14d
.jdsc_a:
    cmp r14d, r12d
    jae .jdsc_done
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rsi, [r13+rax]           ; secA
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.sections_ptr]
    mov edx, [rax+PeImage.num_sections]
    sub rsp, 32
    call .t_find_sec             ; rax=secB|0 (rsi intacto: non-vol)
    add rsp, 32
    test rax, rax
    jz .jdsc_next
    mov [rbp-128], rax           ; spill secB (pathB/path impressos no header:
                                 ; mortos aqui; reuso documentado)
                                 ; pathB só usado no header! reuso documentado)
    mov ecx, [rsi+PeSection.vaddr]
    cmp ecx, [rax+PeSection.vaddr]
    jne .jdsc_hit
    mov ecx, [rsi+PeSection.vsize]
    cmp ecx, [rax+PeSection.vsize]
    jne .jdsc_hit
    mov ecx, [rsi+PeSection.raw_size]
    cmp ecx, [rax+PeSection.raw_size]
    jne .jdsc_hit
    mov ecx, [rsi+PeSection.raw_ptr]
    cmp ecx, [rax+PeSection.raw_ptr]
    jne .jdsc_hit
    jmp .jdsc_next
.jdsc_hit:
    mov dword [rbp-112], 0
    cmp dword [rbp-120], 0
    je .jdsc_nc
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jdsc_nc:
    mov dword [rbp-120], 1
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .j_print_secname
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jdsc_next:
    inc r14d
    jmp .jdsc_a
.jdsc_done:
    ret
.j_diff_imps_added:
    lea rax, [rel g_cimg]
    mov r12d, [rax+PeImage.imports_count]
    mov r13, [rax+PeImage.imports_ptr]
    xor r14d, r14d
.jdia_b:
    cmp r14d, r12d
    jae .jdia_done
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]           ; impB
    mov rcx, [r15+PeImage.imports_ptr]
    mov edx, [r15+PeImage.imports_count]
    sub rsp, 32
    call .t_find_imp_a           ; rax=impA|0
    add rsp, 32
    test rax, rax
    jnz .jdia_next
    mov dword [rbp-112], 0
    cmp dword [rbp-120], 0
    je .jdia_nc
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jdia_nc:
    mov dword [rbp-120], 1
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .j_print_impname
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jdia_next:
    inc r14d
    jmp .jdia_b
.jdia_done:
    ret
.j_diff_imps_removed:
    mov r12d, [r15+PeImage.imports_count]
    mov r13, [r15+PeImage.imports_ptr]
    xor r14d, r14d
.jdir_a:
    cmp r14d, r12d
    jae .jdir_done
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rsi, [r13+rax]           ; impA
    lea rax, [rel g_cimg]
    mov rcx, [rax+PeImage.imports_ptr]
    mov edx, [rax+PeImage.imports_count]
    sub rsp, 32
    call .t_find_imp             ; rax=impB|0
    add rsp, 32
    test rax, rax
    jnz .jdir_next
    mov dword [rbp-112], 0
    cmp dword [rbp-120], 0
    je .jdir_nc
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jdir_nc:
    mov dword [rbp-120], 1
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call .j_print_impname
    add rsp, 32
    lea rcx, [rel s_j_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.jdir_next:
    inc r14d
    jmp .jdir_a
.jdir_done:
    ret
; .j_print_secname — rsi=sec -> nome com escape em stdout.
; Frameless (rbp do chamador p/ jtmp). Clobber: rax,rcx,rdx,rsi,rdi.
.j_print_secname:
    sub rsp, 56                  ; (entry 8 → 8-56 → %16==0 ✓)
    lea rdi, [rsp+32]            ; tmp 9B em [rsp+32,+41)
    mov rax, [rsi+PeSection.name]
    mov [rdi], rax
    mov byte [rdi+8], 0
    mov rsi, rdi
    lea rdi, [rbp-384]           ; jtmp
    mov edx, 9
    call .c_esc                  ; leaf sem stack: dispensa shadow
    lea rcx, [rbp-384]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    add rsp, 56
    ret
; .j_print_impname — rsi=imp -> "dll!func" (escapes) ou "dll!ordN".
.j_print_impname:
    sub rsp, 56
    mov [rsp+48], rsi            ; spill entry ([rsp+48,+56), fora do tmp)
    mov rsi, [rsi+ImportEntry.dll_name]
    lea rdi, [rbp-384]
    mov edx, 255
    call .c_esc
    lea rcx, [rbp-384]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_c_bang]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rsp+48]            ; entry (rsp restaurado: sub/add pares ✓)
    cmp byte [rsi+ImportEntry.is_ordinal], 0
    jne .jpi_ord
    mov rsi, [rsi+ImportEntry.func_name]
    lea rdi, [rbp-384]
    mov edx, 255
    call .c_esc
    lea rcx, [rbp-384]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    add rsp, 56
    ret
.jpi_ord:
    lea rcx, [rel s_c_ord]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rsi, [rsp+48]
    movzx ecx, word [rsi+ImportEntry.ordinal]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    add rsp, 56
    ret
; .c_esc — rsi=NUL, rdi=dst256, edx=max -> escape JSON. Leaf.
.c_esc:
    xor ecx, ecx
    xor r8d, r8d
.ce_l:
    cmp ecx, edx
    jae .ce_end
    cmp r8d, 254
    jae .ce_end
    mov al, [rsi+rcx]
    test al, al
    jz .ce_end
    cmp al, '"'
    je .ce_esc
    cmp al, '\'
    je .ce_esc
    cmp al, 0x20
    jb .ce_q
    mov [rdi], al
    inc rdi
    inc r8d
    inc ecx
    jmp .ce_l
.ce_q:
    mov byte [rdi], '?'
    inc rdi
    inc r8d
    inc ecx
    jmp .ce_l
.ce_esc:
    cmp r8d, 253
    ja .ce_end
    mov byte [rdi], '\'
    inc rdi
    mov [rdi], al
    inc rdi
    add r8d, 2
    inc ecx
    jmp .ce_l
.ce_end:
    mov byte [rdi], 0
    ret
;-----------------------------------------------------------------------------
; Erros do segundo arquivo (stderr própria) + limpeza + retorno 2|3.
; [rbp-72]=chandle (0=fechado), [rbp-88]=cbase (0=sem mapa).
;-----------------------------------------------------------------------------
.err_io2:
    lea rcx, [rel s_c_io2]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 2
    add rsp, 328
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.err_io2_close:
    mov rcx, [rbp-72]
    sub rsp, 32
    call dex_close
    add rsp, 32
    jmp .err_io2
.err_pe2:
    mov rcx, [rbp-88]
    test rcx, rcx
    jz .err_pe2_nounmap
    sub rsp, 32
    call dex_unmap
    add rsp, 32
.err_pe2_nounmap:
    mov rcx, [rbp-72]
    sub rsp, 32
    call dex_close
    add rsp, 32
    lea rcx, [rel s_c_pe2]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 3
    add rsp, 328
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.cleanup_ok:
    mov rcx, [rbp-88]
    sub rsp, 32
    call dex_unmap
    add rsp, 32
    mov rcx, [rbp-72]
    sub rsp, 32
    call dex_close
    add rsp, 32
    xor eax, eax
    add rsp, 328
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

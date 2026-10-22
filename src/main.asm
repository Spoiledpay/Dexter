;=============================================================================
; Dexter/src/main.asm
; Entry point: parse_args -> open/mmap -> pe_load -> parses -> verbose ->
; generate -> rebuild opcional. Sem CRT (/ENTRY:main).
;
; Requisitos atendidos: Projeto.md §6 (main), R-0.x, R-4.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"
%include "pe.inc"

global main

extern dex_parse_args
extern dex_print_help
extern dex_print_version
extern dex_print_banner
extern dex_open_read
extern dex_file_size
extern dex_mmap_read
extern dex_unmap
extern dex_close
extern dex_pe_load
extern dex_pe_parse_imports
extern dex_pe_parse_exports
extern dex_pe_parse_relocs
extern dex_generate_asm
extern dex_rebuild
extern dex_console_print_cstr
extern dex_console_print_err
extern dex_console_print_u64hex
extern dex_console_print_u64dec
extern dex_console_newline
extern dex_strlen
extern dex_streq
extern dex_overview
extern dex_func
extern dex_xrefs
extern dex_trace
extern dex_rsrc_list
extern dex_doctor
extern dex_snapshot
extern dex_compare

section .rodata
s_usage    db "Uso: dexter <input.exe> [opcoes]  (-h para ajuda)", 13, 10, 0
s_err_io   db "dexter: cannot open/read input file", 13, 10, 0
s_err_pe   db "dexter: invalid or unsupported PE file", 13, 10, 0
s_err_rsrc db "dexter: corrupt resource directory", 13, 10, 0
s_err_gen  db "dexter: failed to generate asm", 13, 10, 0
s_err_gcceh db "dexter: -native -r refused: GCC C++ exception tables are position-sensitive (pcrel); use -m bin", 13, 10, 0
s_pers_v0  db "__gxx_personality_v0", 0
s_pers_seh db "__gxx_personality_seh0", 0
s_pers_sj  db "__gxx_personality_sj0", 0
s_pers_gv0 db "__gcc_personality_v0", 0
s_pers_gseh db "__gcc_personality_seh0", 0
s_pers_gsj db "__gcc_personality_sj0", 0
s_ok_gen   db "OK: asm written", 13, 10, 0
s_ok_rb    db "OK: rebuild done", 13, 10, 0
s_v_base   db "ImageBase: 0x", 0
s_v_entry  db "EntryPoint RVA: 0x", 0
s_v_nsec   db "Sections: ", 0
s_v_sec    db "  [", 0
s_v_mid1   db "] vaddr=0x", 0
s_v_mid2   db " raw=0x", 0
s_v_mid3   db " size=0x", 0
s_v_nl     db 13, 10, 0
s_v_imp    db "Imports: ", 0
s_v_hex    db "  hex: ", 0
s_v_sp     db " ", 0
s_v_imp1   db "  ", 0
s_v_bang   db "!", 0
s_v_iat    db " iat=0x", 0
s_v_ord    db " ord=", 0
s_v_exp    db "Exports: ", 0
s_v_rel    db "Relocs: ", 0

section .bss
align 16
g_cfg:      resb 192
g_img:      resb 128
g_sections: resb 3072          ; 96 * 32

section .text

; main — sem args (usa GetCommandLineA via parse_args). Retorna via ExitProcess.
main:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56                ; 8 pushes -> rsp%16==8; 56 ok
    ; zerar cfg (144: DexConfig=142) + img (128)
    lea rdi, [rel g_cfg]
    xor eax, eax
    mov ecx, 18
    rep stosq                  ; 18*8 = 144
    lea rdi, [rel g_img]
    mov ecx, 16
    rep stosq
    lea rax, [rel g_sections]
    mov [rel g_img+PeImage.sections_ptr], rax
    ; banner (exceto quiet? parse ainda não rodou: sempre imprime? NÃO —
    ; banner só sem -q; como parse vem depois, imprimir banner depois do parse)
    lea rcx, [rel g_cfg]
    sub rsp, 32
    call dex_parse_args        ; rax = 0/1/2/3/4
    add rsp, 32
    cmp rax, 1
    je .exit1
    cmp rax, 2
    je .do_help
    cmp rax, 3
    je .do_ver
    cmp rax, 4
    je .do_banner
    ; ok: cfg preenchido
    mov eax, [rel g_cfg+DexConfig.quiet]
    test eax, eax
    jnz .no_banner
    sub rsp, 32
    call dex_print_banner
    add rsp, 32
.no_banner:
    ; abrir input
    mov rcx, [rel g_cfg+DexConfig.input_path]
    sub rsp, 32
    call dex_open_read
    add rsp, 32
    test rax, rax
    jz .err_io
    mov rbx, rax               ; handle
    mov rcx, rax
    sub rsp, 32
    call dex_file_size
    add rsp, 32
    cmp rax, -1
    je .err_io_close
    mov r12, rax               ; size
    mov rcx, rbx
    mov rdx, rax
    sub rsp, 32
    call dex_mmap_read
    add rsp, 32
    test rax, rax
    jz .err_io_close
    mov r13, rax               ; base
    ; pe_load
    lea rcx, [rel g_img]
    mov rdx, r13
    mov r8, r12
    sub rsp, 32
    call dex_pe_load
    add rsp, 32
    test eax, eax
    jnz .err_pe_um
    ; parses (respeitando NO_IMPORTS/NO_RELOCS)
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_NO_IMPORTS
    jnz .skip_imp
    lea rcx, [rel g_img]
    sub rsp, 32
    call dex_pe_parse_imports
    add rsp, 32
.skip_imp:
    lea rcx, [rel g_img]
    sub rsp, 32
    call dex_pe_parse_exports
    add rsp, 32
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_NO_RELOCS
    jnz .skip_rel
    lea rcx, [rel g_img]
    sub rsp, 32
    call dex_pe_parse_relocs
    add rsp, 32
.skip_rel:
    ; overview? (inspect-only: imprime e sai 0, ignora -q/generate/rebuild)
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_OVERVIEW
    jz .no_overview
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    sub rsp, 32
    call dex_overview
    add rsp, 32
    jmp .done_ok
.no_overview:
    ; queries? (inspect-only: precedência overview > doctor > rsrc > func
    ; > xrefs > trace; cada uma sai 0 após rodar)
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_DOCTOR
    jz .q_no_doctor
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    sub rsp, 32
    call dex_doctor
    add rsp, 32
    jmp .done_ok
.q_no_doctor:
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_RSRC
    jz .q_no_rsrc
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    sub rsp, 32
    call dex_rsrc_list
    add rsp, 32
    test eax, eax
    jnz .err_rsrc_um
    jmp .done_ok
.q_no_rsrc:
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_SNAP
    jz .q_no_snap
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    sub rsp, 32
    call dex_snapshot
    add rsp, 32
    test eax, eax
    jnz .err_q_um
    jmp .done_ok
.q_no_snap:
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_CMP
    jz .q_no_cmp
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    mov r8, [rel g_cfg+DexConfig.compare_path]
    sub rsp, 32
    call dex_compare
    add rsp, 32
    test eax, eax
    jnz .err_q_um
    jmp .done_ok
.q_no_cmp:
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_FUNC
    jz .q_no_func
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    mov r8, [rel g_cfg+DexConfig.func_addr]
    sub rsp, 32
    call dex_func
    add rsp, 32
    jmp .q_did
.q_no_func:
    test eax, DF_XREFS
    jz .q_no_xrefs
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    mov r8, [rel g_cfg+DexConfig.xrefs_addr]
    sub rsp, 32
    call dex_xrefs
    add rsp, 32
    jmp .q_did
.q_no_xrefs:
    test eax, DF_TRACE
    jz .q_none
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    mov r8, [rel g_cfg+DexConfig.trace_addr]
    sub rsp, 32
    call dex_trace
    add rsp, 32
.q_did:
    jmp .done_ok
.q_none:
    ; verbose? (respeita -q: silêncio total)
    mov eax, [rel g_cfg+DexConfig.quiet]
    test eax, eax
    jnz .no_verbose
    mov eax, [rel g_cfg+DexConfig.verbose]
    test eax, eax
    jz .no_verbose
    sub rsp, 32
    call .dump_verbose
    add rsp, 32
.no_verbose:
    ; D-19 2c-2: EH C++ do GCC/MinGW usa tabelas POSICIONAIS (pcrel no
    ; LSDA e nas secoes /NNN). O link.exe move as secoes e nao ha relocacao
    ; para esses offsets -> o .exe reconstruido salta p/ endereco invalido.
    ; Recusa honesta: -native -r no modo link com personalidade GCC; o
    ; caminho fiel e `-m bin` (layout preservado). Imports ja parseados.
    cmp dword [rel g_cfg+DexConfig.mode], DEX_MODE_BIN
    je .gen_go
    mov eax, [rel g_cfg+DexConfig.flags]
    mov ecx, eax
    and ecx, DF_NATIVE|DF_REBUILD
    cmp ecx, DF_NATIVE|DF_REBUILD
    jne .gen_go
    lea rcx, [rel g_img]
    sub rsp, 32
    call .has_gcc_eh
    add rsp, 32
    test eax, eax
    jnz .err_gcceh_um
.gen_go:
    ; generate
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    sub rsp, 32
    call dex_generate_asm
    add rsp, 32
    test eax, eax
    jnz .err_gen_um
    mov eax, [rel g_cfg+DexConfig.quiet]
    test eax, eax
    jnz .chk_rebuild
    lea rcx, [rel s_ok_gen]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.chk_rebuild:
    mov eax, [rel g_cfg+DexConfig.flags]
    test eax, DF_REBUILD
    jz .done_ok
    lea rcx, [rel g_cfg]
    lea rdx, [rel g_img]
    sub rsp, 32
    call dex_rebuild
    add rsp, 32
    test eax, eax
    jnz .exit5_um
    mov eax, [rel g_cfg+DexConfig.quiet]
    test eax, eax
    jnz .done_ok
    lea rcx, [rel s_ok_rb]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.done_ok:
    mov rcx, r13
    sub rsp, 32
    call dex_unmap
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_close
    add rsp, 32
    xor ecx, ecx
    call ExitProcess
.exit1:
    lea rcx, [rel s_usage]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov ecx, 1
    call ExitProcess
.do_help:
    sub rsp, 32
    call dex_print_help
    add rsp, 32
    xor ecx, ecx
    call ExitProcess
.do_ver:
    sub rsp, 32
    call dex_print_version
    add rsp, 32
    xor ecx, ecx
    call ExitProcess
.do_banner:
    sub rsp, 32
    call dex_print_banner
    add rsp, 32
    sub rsp, 32
    call dex_print_help
    add rsp, 32
    xor ecx, ecx
    call ExitProcess
.err_io:
    lea rcx, [rel s_err_io]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov ecx, 2
    call ExitProcess
.err_io_close:
    mov rcx, rbx
    sub rsp, 32
    call dex_close
    add rsp, 32
    jmp .err_io
.err_pe_um:
    mov rcx, r13
    sub rsp, 32
    call dex_unmap
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_close
    add rsp, 32
    lea rcx, [rel s_err_pe]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov ecx, 3
    call ExitProcess
.err_rsrc_um:
    mov rcx, r13
    sub rsp, 32
    call dex_unmap
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_close
    add rsp, 32
    lea rcx, [rel s_err_rsrc]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov ecx, 3
    call ExitProcess
.err_q_um:
    mov r14d, eax                ; código 2|3 do dex_snapshot/compare
    mov rcx, r13
    sub rsp, 32
    call dex_unmap
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_close
    add rsp, 32
    mov ecx, r14d
    call ExitProcess
.err_gen_um:
    mov rcx, r13
    sub rsp, 32
    call dex_unmap
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_close
    add rsp, 32
    lea rcx, [rel s_err_gen]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov ecx, 2
    call ExitProcess
.err_gcceh_um:
    mov rcx, r13
    sub rsp, 32
    call dex_unmap
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_close
    add rsp, 32
    lea rcx, [rel s_err_gcceh]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov ecx, 4
    call ExitProcess
.exit5_um:
    mov r14, rax
    mov rcx, r13
    sub rsp, 32
    call dex_unmap
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_close
    add rsp, 32
    mov ecx, 5
    call ExitProcess

; .has_gcc_eh — rcx=img -> eax=1 se a import table traz personalidade C++
; do GCC/MinGW (__gxx/__gcc_personality_*). Funcao local de main.
; Por quê: essas personalidades usam tabelas pcrel (D-19 2c-2) que o link
; nao relocaliza; o guard recusa `-native -r` no modo link. Nao executa o PE.
; Frame: 5 pushes (40B) + sub 40 = 80 ≡ 0. Calls com shadow embutido.
.has_gcc_eh:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    mov rbx, rcx                 ; img
    mov r13, [rbx+PeImage.imports_ptr]
    mov r12d, [rbx+PeImage.imports_count]
    test r13, r13
    jz .ge_no
    xor r14d, r14d               ; i
.ge_l:
    cmp r14d, r12d
    jae .ge_no
    mov eax, r14d
    imul eax, SIZEOF_IMPORT_ENTRY
    mov r15, [r13+rax+ImportEntry.func_name]
    test r15, r15
    jz .ge_next
    mov rcx, r15
    lea rdx, [rel s_pers_v0]
    call dex_streq
    test eax, eax
    jnz .ge_yes
    mov rcx, r15
    lea rdx, [rel s_pers_seh]
    call dex_streq
    test eax, eax
    jnz .ge_yes
    mov rcx, r15
    lea rdx, [rel s_pers_sj]
    call dex_streq
    test eax, eax
    jnz .ge_yes
    mov rcx, r15
    lea rdx, [rel s_pers_gv0]
    call dex_streq
    test eax, eax
    jnz .ge_yes
    mov rcx, r15
    lea rdx, [rel s_pers_gseh]
    call dex_streq
    test eax, eax
    jnz .ge_yes
    mov rcx, r15
    lea rdx, [rel s_pers_gsj]
    call dex_streq
    test eax, eax
    jnz .ge_yes
.ge_next:
    inc r14d
    jmp .ge_l
.ge_yes:
    mov eax, 1
    jmp .ge_out
.ge_no:
    xor eax, eax
.ge_out:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; .dump_verbose — imprime base/entry/seções/imports/exports/relocs
.dump_verbose:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40
    lea rbx, [rel g_img]
    lea rcx, [rel s_v_base]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbx+PeImage.image_base]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_v_entry]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbx+PeImage.entry_point]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_v_nsec]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbx+PeImage.num_sections]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; seções
    mov r12d, [rbx+PeImage.num_sections]
    mov r13, [rbx+PeImage.sections_ptr]
    xor r14d, r14d
.dv_sec:
    cmp r14d, r12d
    jae .dv_imp
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea r15, [r13+rax]         ; sec
    lea rcx, [rel s_v_sec]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    ; nome (8 bytes, pode não ter NUL): copiar p/ tmp e terminar
    sub rsp, 48
    lea rdi, [rsp+32]
    mov rax, [r15+PeSection.name]
    mov [rdi], rax
    mov byte [rdi+8], 0
    mov rcx, rdi
    call dex_console_print_cstr
    lea rcx, [rel s_v_mid1]
    call dex_console_print_cstr
    mov ecx, [r15+PeSection.vaddr]
    xor edx, edx
    call dex_console_print_u64hex
    lea rcx, [rel s_v_mid2]
    call dex_console_print_cstr
    mov ecx, [r15+PeSection.raw_ptr]
    xor edx, edx
    call dex_console_print_u64hex
    lea rcx, [rel s_v_mid3]
    call dex_console_print_cstr
    mov ecx, [r15+PeSection.raw_size]
    xor edx, edx
    call dex_console_print_u64hex
    lea rcx, [rel s_v_nl]
    call dex_console_print_cstr
    add rsp, 48
    ; -vv: hexdump dos primeiros 64 bytes da seção
    mov eax, [rel g_cfg+DexConfig.verbose]
    cmp eax, 2
    jb .dv_next_sec
    mov rcx, rbx               ; img (preservado? rbx é non-vol nas prints ✓)
    mov rdx, r15               ; sec
    sub rsp, 32
    call .dv_hexdump
    add rsp, 32
.dv_next_sec:
    inc r14d
    jmp .dv_sec
.dv_imp:
    lea rcx, [rel s_v_imp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbx+PeImage.imports_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ; listar até 64 imports (dll!func)
    mov r12d, [rbx+PeImage.imports_count]
    cmp r12d, 64
    jbe .dv_imp_n
    mov r12d, 64
.dv_imp_n:
    mov r13, [rbx+PeImage.imports_ptr]
    xor r14d, r14d
.dv_imp_l:
    cmp r14d, r12d
    jae .dv_exp
    mov eax, r14d
    shl eax, 5
    lea r15, [r13+rax]
    lea rcx, [rel s_v_imp1]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [r15+0]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_v_bang]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    cmp byte [r15+18], 0       ; is_ordinal @18
    jne .dv_ord
    mov rcx, [r15+8]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    jmp .dv_iat
.dv_ord:
    lea rcx, [rel s_v_ord]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    movzx ecx, word [r15+16]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
.dv_iat:
    lea rcx, [rel s_v_iat]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [r15+24]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    inc r14d
    jmp .dv_imp_l
.dv_exp:
    lea rcx, [rel s_v_exp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov r13, [rbx+PeImage.exports_ptr]
    test r13, r13
    jz .dv_exp0
    mov rcx, [r13]             ; count (primeiro qword)
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    jmp .dv_rel
.dv_exp0:
    mov ecx, 0
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
.dv_rel:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_v_rel]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbx+PeImage.relocs_count]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; .dv_hexdump — rcx=img, rdx=sec: imprime "  hex: HH ..." (até 64 bytes).
.dv_hexdump:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push r12
    push r13
    sub rsp, 48                ; 5 pushes -> rsp%16==0; 48 ok
    mov rbx, [rcx+PeImage.file_buffer]
    mov r12d, [rdx+PeSection.raw_size]
    cmp r12d, 64
    jbe .dvh_n
    mov r12d, 64
.dvh_n:
    test r12d, r12d
    jz .dvh_done
    mov eax, [rdx+PeSection.raw_ptr]
    add rbx, rax               ; p
    lea rcx, [rel s_v_hex]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor r13d, r13d             ; i
.dvh_l:
    cmp r13d, r12d
    jae .dvh_nl
    movzx ecx, byte [rbx+r13]
    mov edx, 2                 ; 2 dígitos
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_v_sp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    inc r13d
    jmp .dvh_l
.dvh_nl:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.dvh_done:
    add rsp, 48
    pop r13
    pop r12
    pop rsi
    pop rbx
    pop rbp
    ret

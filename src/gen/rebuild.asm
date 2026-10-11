;=============================================================================
; Dexter/src/gen/rebuild.asm
; dex_generate_asm — gera o .asm (seções + labels + db + rewrite de IAT).
; dex_rebuild — invoca nasm.exe + link.exe via CreateProcessA.
; Estratégia: cópia byte-exata de TODAS as seções (inclusive .idata);
; rewrite mínimo: call/jmp [rel IAT] viram `call|jmp [rel __imp_X]` com
; stubs __imp_ reais. Rebuild exige mesma base (/BASE + /DYNAMICBASE:NO).
;
; dex_rebuild assinatura: rcx=cfg, rdx=img (img p/ base/entry/subsystem).
; Requisitos atendidos: R-4.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"
%include "pe.inc"

global dex_generate_asm
global dex_generate_bin
global dex_emit_imp_label
global dex_build_impname
global dex_rebuild
global dex_patch_dirs

extern asmbuf_new
extern asmbuf_append
extern asmbuf_append_str
extern asmbuf_append_u64_hex
extern asmbuf_free
extern dex_emit_set_hex
extern asmbuf_len
extern asmbuf_data
extern dex_malloc
extern dex_free
extern dex_strlen
extern dex_memcpy
extern dex_memcmp
extern dex_streq
extern dex_u64_to_hex
extern dex_disasm_one
extern dex_build_operands
extern dex_emit_insn
extern dex_emit_native
extern dex_emit_data
extern dex_emit_label
extern symtab_new
extern symtab_lookup_va
extern symtab_insert_va
extern symtab_free
extern dex_open_write
extern dex_open_rw
extern dex_write_all
extern dex_file_size
extern dex_mmap_rw
extern dex_unmap
extern dex_file_write_at
extern dex_file_read_at
extern dex_close
extern dex_pe_find_section
extern dex_console_print_cstr
extern dex_console_print_err
extern dex_console_print_u64hex
extern dex_console_print_u64dec
extern dex_console_newline
extern dex_parse_asm
extern dex_ast_dump
extern dex_ast_free_unit
extern dex_lift_insn
extern dex_codegen_ir
extern symtab_to_sorted
extern GetLastError

section .rodata
s_hdr1  db "; ===================================================================", 13, 10
        db "; Gerado por Dexter v0.2 (nasm/win64) - nao editar manualmente", 13, 10
        db "; Rebuild: nasm -f win64 + link /BASE:idem /DYNAMICBASE:NO", 13, 10
        db "; ===================================================================", 13, 10
        db "bits 64", 13, 10, "default rel", 13, 10, 13, 10, 0
s_global db "global ", 0
s_sect  db "section ", 0
s_code  db " code", 13, 10, 0
s_data  db " data", 13, 10, 0
s_rdata db " rdata", 13, 10, 0
s_crlf2 db 13, 10, 0
s_pdata  db ".pdata", 0
s_xdata  db ".xdata", 0
s_nop    db "    nop", 13, 10, 0
s_int3   db "    int3", 13, 10, 0
s_bin_hdr db "; ===================================================================", 13, 10
          db "; Gerado por Dexter v0.2 -m bin (nasm -f bin) - nao editar", 13, 10
          db "; Rebuild byte-fiel: headers + secoes + overlay", 13, 10
          db "; ===================================================================", 13, 10
          db "bits 64", 13, 10, 13, 10, 0
s_bin_warn db "dexter: warning: disasm options ignored in bin mode", 13, 10, 0
s_times db "    times 0x", 0
s_db0   db " db 0", 13, 10, 0
s_secpre db 13, 10, "; ---- ", 0
s_bssnote db " (bss: sem bytes no arquivo)", 13, 10, 0
s_ovl   db 13, 10, "; ---- overlay ----", 13, 10, 0
s_semi2 db "; ", 0
s_ext   db "extern ", 0
s_imp_l db "__imp_", 0
s_dq    db ": dq ", 0
s_reloc db ".reloc", 0
s_lab    db "label_", 0
s_dotname db ".", 0
s_csdbg  db "[cs] sec=", 0
s_csdbg2 db " n=", 0
s_db_pre db '    db "', 0
s_q34    db '", 34, "', 0
s_q0     db '", 0', 13, 10, 0
s_dot_o db ".obj", 0
s_dot_e db ".exe", 0
s_dot_rb db ".rebuild.exe", 0
s_q     db '"', 0
s_sp    db " ", 0
s_nasm_args db " -f win64 -o ", 0
s_bin_args  db " -f bin -o ", 0
s_link_pre db " /NOLOGO /NODEFAULTLIB /DEBUG:NONE /SUBSYSTEM:", 0
s_console db "CONSOLE", 0
s_windows db "WINDOWS", 0
s_dynbase db " /DYNAMICBASE:NO /BASE:0x", 0
s_entry db " /ENTRY:", 0
s_out   db " /OUT:", 0
e_gen_o db "dexter: cannot write output asm", 13, 10, 0
e_gen_m db "dexter: out of memory (generate)", 13, 10, 0
e_rb_n  db "dexter: nasm failed", 13, 10, 0
e_rb_l  db "dexter: link failed", 13, 10, 0
e_rb_c  db "dexter: cannot spawn child process", 13, 10, 0
e_astdump db "dexter: warning: -ast-dump skipped (asm too large or out of memory)", 13, 10, 0
s_imp_colon db ":", 13, 10, 0

section .bss
align 16
g_insn:    resb 160
g_secname: resb 16
g_impname: resb 512
g_symD:    resq 1                  ; symtab de VAs decodificadas (R-4.5)
g_symR:    resq 1                  ; symtab de alvos RIP em dados (R-4.5)
g_liftctx: resq 1                  ; DexLiftCtx.img (R-6.4; setado por seção)
g_ir:      resb 24                 ; DexIR scratch do walker (R-6.4)
g_rarr:    resq 1                  ; VAs RIP->dados ordenadas (R-6.4 2b; -native)
g_rn:      resq 1                  ; count (qword)
g_chunkimg: resq 1                 ; img p/ .wds_chunks (evita 7º arg pilha)

section .text

;-----------------------------------------------------------------------------
; dex_generate_asm — rcx=cfg, rdx=img -> rax=0 ok, 2 io, 6 oom
;-----------------------------------------------------------------------------
dex_generate_asm:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov eax, [rcx+DexConfig.mode]
    cmp eax, DEX_MODE_BIN
    je .gen_bin
    jmp .gen_win64
.gen_bin:
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    jmp dex_generate_bin
.gen_win64:
    mov rbx, rcx               ; cfg
    mov r15, rdx               ; img
    mov [rel g_liftctx], r15   ; ctx do lifter (R-6.4; img estável aqui)
    ; propaga -hex p/ o emitter (cl=1 se DF_HEXDUMP)
    mov eax, [rbx+DexConfig.flags]
    xor ecx, ecx
    test eax, DF_HEXDUMP
    jz .no_hex_w
    mov ecx, 1
.no_hex_w:
    sub rsp, 32
    call dex_emit_set_hex
    add rsp, 32
    mov rcx, 0x10000
    sub rsp, 32
    call asmbuf_new
    add rsp, 32
    test rax, rax
    jz .oom
    mov r14, rax               ; buf
    ; header
    lea rdx, [rel s_hdr1]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .oom_free
    ; global <entry_label>
    lea rdx, [rel s_global]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .oom_free
    ; entry_va = base + entry_rva
    mov rax, [r15+PeImage.image_base]
    add rax, [r15+PeImage.entry_point]
    mov [rbp-72], rax          ; entry_va
    mov rcx, r14
    mov rdx, rax
    sub rsp, 32
    call .emit_label_only
    add rsp, 32
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_crlf2]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .oom_free
    lea rdx, [rel s_crlf2]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .oom_free
    ; ---- símbolos R-4.5: tabelas D (VAs decodificadas) e R (RIP→dados)
    mov ecx, 256
    sub rsp, 32
    call symtab_new
    add rsp, 32
    test rax, rax
    jz .oom_free
    mov [rel g_symD], rax
    mov ecx, 256
    sub rsp, 32
    call symtab_new
    add rsp, 32
    test rax, rax
    jz .oom_free
    mov [rel g_symR], rax
    ; ---- passada 1: coleta alvos (sem emitir)
    mov rcx, rbx
    mov rdx, r15
    sub rsp, 32
    call .collect_syms
    add rsp, 32
    test eax, eax
    jnz .oom_free
    ; ---- R-6.4 2b: array ordenado de alvos RIP->dados (só -native;
    ; 0 = OOM de verdade: n==0 retorna dummy ≠ 0)
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NATIVE
    jz .no_rarr
    mov rcx, [rel g_symR]
    sub rsp, 32
    call symtab_to_sorted
    add rsp, 32
    test rax, rax
    jz .oom_free
    mov [rel g_rarr], rax
    mov [rel g_rn], rdx
.no_rarr:
    ; ---- loop de seções ----
    mov edi, [r15+PeImage.num_sections]
    xor r13d, r13d             ; i
.sect:
    cmp r13d, edi
    jae .free_syms
    mov eax, r13d
    imul eax, SIZEOF_PE_SECTION
    mov rsi, [r15+PeImage.sections_ptr]
    lea r12, [rsi+rax]         ; sec
    ; .reloc + NO_RELOCS => pula seção
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NO_RELOCS
    jz .keep_sec
    lea rcx, [rel s_reloc]
    lea rdx, [r12+PeSection.name]
    sub rsp, 32
    call .secname_eq
    add rsp, 32
    test eax, eax
    jnz .next_sect             ; igual a ".reloc": pula
.keep_sec:
    ; "section <nome> <code|data>\r\n"
    lea rdx, [rel s_sect]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .oom_free
    lea rdx, [r12+PeSection.name]
    mov rcx, r14
    sub rsp, 32
    call .emit_secname
    add rsp, 32
    test eax, eax
    jnz .oom_free
    mov eax, [r12+PeSection.characterist]
    test eax, IMAGE_SCN_CNT_CODE
    jnz .is_code
    test eax, IMAGE_SCN_MEM_EXECUTE
    jz .is_not_exec
.is_code:
    lea rdx, [rel s_code]
    jmp .after_cls
.is_not_exec:
    test eax, IMAGE_SCN_MEM_WRITE
    jnz .is_data
    lea rdx, [rel s_rdata]     ; somente-leitura: classe rdata (funde com linker)
    jmp .after_cls
.is_data:
    lea rdx, [rel s_data]
.after_cls:
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .oom_free
    ; escolhe walker: código ou dados
    ; (-s <secao>: só a seção filtrada é desassemblada; demais viram db)
    mov rax, [rbx+DexConfig.section_filter]
    test rax, rax
    jz .no_filter
    mov rcx, rax
    lea rdx, [r12+PeSection.name]
    sub rsp, 32
    call .secname_eq
    add rsp, 32
    test eax, eax
    jnz .no_filter             ; é a seção do filtro: walker normal
    jmp .walk_data             ; outra seção: db
.no_filter:
    mov eax, [r12+PeSection.characterist]
    test eax, IMAGE_SCN_CNT_CODE
    jnz .walk_code
    test eax, IMAGE_SCN_MEM_EXECUTE
    jz .walk_data
    jmp .walk_code
.walk_code:
    mov rcx, rbx
    mov rdx, r15
    mov r8, r14
    mov r9, r12
    sub rsp, 32
    call .walk_code_sec
    add rsp, 32
    test eax, eax
    jnz .oom_free
    jmp .next_sect
.walk_data:
    mov rcx, rbx
    mov rdx, r15
    mov r8, r14
    mov r9, r12
    sub rsp, 32
    call .walk_data_sec
    add rsp, 32
    test eax, eax
    jnz .oom_free
.next_sect:
    inc r13d
    jmp .sect
.free_syms:
    ; libera tabelas da passada 1 (existem aqui)
    mov rcx, [rel g_symD]
    sub rsp, 32
    call symtab_free
    add rsp, 32
    mov rcx, [rel g_symR]
    sub rsp, 32
    call symtab_free
    add rsp, 32
    mov rcx, [rel g_rarr]
    sub rsp, 32
    call dex_free                ; NULL-safe; array R-6.4 2b (ou 0)
    add rsp, 32
    mov qword [rel g_symD], 0
    mov qword [rel g_symR], 0
    mov qword [rel g_rarr], 0
    mov qword [rel g_rn], 0
    jmp .write_out
.write_out:
    ; abrir output_asm e escrever
    mov rcx, [rbx+DexConfig.output_asm]
    sub rsp, 32
    call dex_open_write
    add rsp, 32
    test rax, rax
    jz .io_err
    mov rdi, rax               ; handle
    mov rcx, r14
    sub rsp, 32
    call asmbuf_data
    add rsp, 32
    mov rsi, rax
    mov rcx, r14
    sub rsp, 32
    call asmbuf_len
    add rsp, 32
    mov r8, rax
    mov rcx, rdi
    mov rdx, rsi
    sub rsp, 32
    call dex_write_all
    add rsp, 32
    mov r13d, eax
    mov rcx, rdi
    sub rsp, 32
    call dex_close
    add rsp, 32
    ; -ast-dump (R-6.5): parse-back do .asm gerado + resumo em stdout.
    ; Buffer ainda vivo aqui (r14); data/len RECARREGADOS (rsi/r8 voláteis
    ; morrem nos calls acima). Geração inalterada.
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_ASTDUMP
    jz .no_astdump_w
    mov rcx, r14
    sub rsp, 32
    call asmbuf_data
    add rsp, 32
    mov rsi, rax
    mov rcx, r14
    sub rsp, 32
    call asmbuf_len
    add rsp, 32
    mov rdx, rax
    mov rcx, rsi
    mov r8, rbx
    sub rsp, 32
    call gen_astdump_emit
    add rsp, 32
.no_astdump_w:
    mov rcx, r14
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    mov eax, r13d
    test eax, eax
    jnz .io
    xor eax, eax
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.oom_free:
    mov rcx, r14
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    ; libera symtabs se existirem (cobre falha parcial)
    mov rcx, [rel g_symD]
    test rcx, rcx
    jz .oom_freenor
    sub rsp, 32
    call symtab_free
    add rsp, 32
    mov qword [rel g_symD], 0
.oom_freenor:
    mov rcx, [rel g_symR]
    test rcx, rcx
    jz .oom_freerarr
    sub rsp, 32
    call symtab_free
    add rsp, 32
    mov qword [rel g_symR], 0
.oom_freerarr:
    mov rcx, [rel g_rarr]
    sub rsp, 32
    call dex_free                ; NULL-safe
    add rsp, 32
    mov qword [rel g_rarr], 0
    mov qword [rel g_rn], 0
.oom:
    mov eax, 6
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.io_err:
.io:
    mov rcx, r14
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    lea rcx, [rel e_gen_o]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 2
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; Helpers internos do generate
;-----------------------------------------------------------------------------

; .emit_label_only — rcx=buf, rdx=va -> "label_<hex>" (sem : e sem nl)
.emit_label_only:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    lea rdx, [rel s_lab]
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .elo_done
    mov rcx, rbx
    mov rdx, r12
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
.elo_done:
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

; .emit_secname — rcx=buf, rdx=name8 (não-NUL) -> nome sanitizado
.emit_secname:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov rbx, rcx
    mov r12, rdx
    xor r13d, r13d             ; len real (até 8, para em NUL)
.sn_len:
    cmp r13d, 8
    jae .sn_emit
    movzx eax, byte [r12+r13]
    test al, al
    jz .sn_emit
    inc r13d
    jmp .sn_len
.sn_emit:
    test r13d, r13d
    jnz .sn_copy
    ; nome vazio: usa "data" (seção sem nome; nunca deve ocorrer em PE válido)
    lea rdx, [rel s_data+1]    ; "data\r\n\0"
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    jmp .sn_done
.sn_copy:
    mov rcx, rbx
    mov rdx, r12
    mov r8d, r13d
    sub rsp, 32
    call asmbuf_append
    add rsp, 32
.sn_done:
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; .secname_eq — rcx=esperado(NUL), rdx=name8 -> eax=1 igual
.secname_eq:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    mov rcx, rbx
    call dex_strlen
    cmp rax, 8
    ja .sne_no
    mov [rbp-24], rax          ; len (r8 morre no dex_memcmp)
    mov r8, rax
    mov rcx, r12
    mov rdx, rbx
    call dex_memcmp
    test eax, eax
    jnz .sne_no
    ; checar resto zerado/espaco até 8
    mov rcx, [rbp-24]
.sne_tail:
    cmp rcx, 8
    jae .sne_yes
    movzx eax, byte [r12+rcx]
    test al, al
    jz .sne_inc
    cmp al, 32
    jne .sne_no
.sne_inc:
    inc rcx
    jmp .sne_tail
.sne_yes:
    mov eax, 1
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret
.sne_no:
    xor eax, eax
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

    xor eax, eax
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; .collect_syms — rcx=cfg, rdx=img -> eax=0 ok, 1 oom
; Passada 1 (R-4.5): decodifica seções de código (mesmo filtro/range do
; walker) e registra: D = toda VA decodificada; R = alvos RIP-rel em dados.
;-----------------------------------------------------------------------------
.collect_syms:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov rbx, rcx               ; cfg
    mov r15, rdx               ; img
    mov edi, [r15+PeImage.num_sections]
    mov [rbp-60], edi          ; count em slot (rdi é reusado como
                               ; image_base em .cs_walk; ver fix 2026-10-07)
    xor r13d, r13d             ; i (seção)
.cs_sec:
    mov edi, [rbp-60]          ; recarrega (rdi morre em .cs_walk/inner)
    cmp r13d, edi
    jae .cs_ok
    mov [rbp-120], r13d        ; dbg: i
    mov [rbp-112], edi         ; dbg: count
    lea rcx, [rel s_csdbg]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-120]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_csdbg2]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-112]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    mov edi, [rbp-112]
    mov r13d, [rbp-120]
    mov eax, r13d
    imul eax, SIZEOF_PE_SECTION
    mov rsi, [r15+PeImage.sections_ptr]
    lea r12, [rsi+rax]         ; sec
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NO_RELOCS
    jnz .cs_chkrel
    jmp .cs_iscode
.cs_chkrel:
    lea rcx, [rel s_reloc]
    lea rdx, [r12+PeSection.name]
    sub rsp, 32
    call .secname_eq
    add rsp, 32
    test eax, eax
    jnz .cs_next
.cs_iscode:
    mov eax, [r12+PeSection.characterist]
    test eax, IMAGE_SCN_CNT_CODE
    jnz .cs_code
    test eax, IMAGE_SCN_MEM_EXECUTE
    jz .cs_next
.cs_code:
    mov rax, [rbx+DexConfig.section_filter]
    test rax, rax
    jz .cs_walk
    mov rcx, rax
    lea rdx, [r12+PeSection.name]
    sub rsp, 32
    call .secname_eq
    add rsp, 32
    test eax, eax
    jz .cs_next
.cs_walk:
    mov rsi, [r15+PeImage.file_buffer]
    mov rdi, [r15+PeImage.image_base]
    mov eax, [r12+PeSection.vaddr]
    lea r10, [rdi+rax]         ; va_base
    mov [rbp-72], r10
    mov eax, [r12+PeSection.raw_size]
    mov [rbp-80], eax          ; raw
    xor r14d, r14d             ; k
.cs_loop:
    mov eax, [rbp-80]
    cmp r14d, eax
    jae .cs_next
    mov eax, [r12+PeSection.vaddr]
    add eax, r14d              ; rva
    mov [rbp-96], eax
    cmp byte [rbx+DexConfig.has_start], 0
    je .cs_no_s
    mov edx, [rbx+DexConfig.start_rva]
    cmp [rbp-96], edx
    jb .cs_adv1
.cs_no_s:
    cmp byte [rbx+DexConfig.has_end], 0
    je .cs_in
    mov edx, [rbx+DexConfig.end_rva]
    mov eax, [rbp-96]
    cmp eax, edx
    jae .cs_adv1
.cs_in:
    mov rax, [rbp-72]
    mov edx, r14d
    add rax, rdx               ; va
    mov [rbp-104], rax         ; spill va
    mov rcx, r15
    mov rdx, rax
    lea r8, [rel g_insn]
    sub rsp, 32
    call dex_disasm_one
    add rsp, 32
    test eax, eax
    jz .cs_adv1b
    mov [rbp-112], eax         ; len
    ; D DESLIGADO (2026-10-07): insert por-VA com 2 HeapAllocs + lookup
    ; O(n^2/256) trava binários grandes (.text 45MB do ld.lld = horas) e a
    ; tabela D não tem nenhum leitor hoje (verificado: só insert/free).
    ; R-6.4 vai reconstruir code-vs-data com estrutura adequada (intervalos).
    ; g_symD continua alocada/liberada (infra pronta, custo ~0). R continua.
    ; RIP-ref em dados? (disp32, sem 67, rm==101, sem SIB)
    lea rax, [rel g_insn]
    cmp byte [rax+Insn.has_modrm], 0
    je .cs_adv
    cmp byte [rax+Insn.disp_size], 4
    jne .cs_adv
    cmp byte [rax+Insn.legacy67], 0
    jne .cs_adv
    movzx ecx, byte [rax+Insn.modrm]
    and ecx, 0xC7
    cmp ecx, 0x05
    jne .cs_adv
    cmp byte [rax+Insn.has_sib], 0
    jne .cs_adv
    ; target = va + len + disp
    mov rax, [rbp-104]
    mov ecx, [rbp-112]
    add rax, rcx
    add rax, [rel g_insn+Insn.disp]
    mov [rbp-120], rax         ; spill target
    ; alvo em seção de CÓDIGO? (então D cobre; R só p/ dados)
    mov rdx, rax
    sub rdx, rdi               ; trva (rdi=base intacto? calls preservam rdi?
    ; symtab_insert PRESERVA rdi (push)? symbols.asm: lookup/insert push rdi? —
    ; insert pushes rdi ✓ (verificado). disasm push rdi ✓. OK rdi intacto.
    mov [rbp-120], rdx         ; (reuso: trva; target não mais preciso)
    mov rcx, r15
    sub rsp, 32
    call .cs_in_code
    add rsp, 32
    test eax, eax
    jnz .cs_adv                ; em código: D cobre
    ; R[trva] = .
    mov rcx, [rel g_symR]
    mov rdx, [rbp-120]
    lea r8, [rel s_dotname]
    sub rsp, 32
    call symtab_insert_va
    add rsp, 32
    test rax, rax
    jz .cs_fail
    jmp .cs_adv
.cs_adv1b:
    inc r14d
    jmp .cs_loop
.cs_adv1:
    inc r14d
    jmp .cs_loop
.cs_adv:
    mov eax, [rbp-112]
    add r14d, eax
    jmp .cs_loop
.cs_next:
    inc r13d
    jmp .cs_sec
.cs_ok:
    xor eax, eax
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.cs_fail:
    mov eax, 1
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; .cs_in_code — rcx=img, rdx=trva -> eax=1 se trva cai em seção CODE/EXEC.
.cs_in_code:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    sub rsp, 32
    mov rbx, rcx
    mov esi, edx               ; trva (32b basta: RVAs < 4GB)
    mov ecx, [rbx+PeImage.num_sections]
    mov rdx, [rbx+PeImage.sections_ptr]
    test ecx, ecx
    jz .cic_no
.cic_l:
    test ecx, ecx
    jz .cic_no
    dec ecx
    mov eax, ecx
    imul eax, SIZEOF_PE_SECTION
    lea rax, [rdx+rax]         ; sec
    mov r8d, [rax+PeSection.vaddr]
    cmp esi, r8d
    jb .cic_l
    mov r9d, [rax+PeSection.vsize]
    mov r10d, [rax+PeSection.raw_size]
    cmp r9d, r10d
    jae .cic_span
    mov r9d, r10d
.cic_span:
    mov r10d, esi
    sub r10d, r8d               ; delta em r10d (esi/trva intacto p/ as
    cmp r10d, r9d               ; próximas seções; mutar esi aqui errava
    jae .cic_l                  ; alvos além do fim (fix 2026-10-07))
    mov eax, [rax+PeSection.characterist]
    test eax, IMAGE_SCN_CNT_CODE
    jnz .cic_yes
    test eax, IMAGE_SCN_MEM_EXECUTE
    jz .cic_l
.cic_yes:
    mov eax, 1
    add rsp, 32
    pop rsi
    pop rbx
    pop rbp
    ret
.cic_no:
    xor eax, eax
    add rsp, 32
    pop rsi
    pop rbx
    pop rbp
    ret

; .walk_code_sec — rcx=cfg, rdx=img, r8=buf, r9=sec -> eax=0 ok, 1 oom
; Varredura linear com emissor NATIVO (R-4.5) + fallback db.
.walk_code_sec:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov rbx, rcx               ; cfg
    mov r15, rdx               ; img
    mov r14, r8                ; buf
    mov r12, r9                ; sec
    mov rsi, [r15+PeImage.file_buffer]
    mov rdi, [r15+PeImage.image_base]
    mov eax, [r12+PeSection.vaddr]
    lea r10, [rdi+rax]         ; va_base
    mov [rbp-72], r10
    mov eax, [r12+PeSection.raw_size]
    mov [rbp-80], eax          ; raw_size
    mov eax, [r12+PeSection.raw_ptr]
    lea r11, [rsi+rax]         ; file ptr base
    mov [rbp-88], r11
    xor r13d, r13d             ; k
.wcs_loop:
    mov eax, [rbp-80]
    cmp r13d, eax
    jae .wcs_ok
    ; rva = vaddr + k
    mov eax, [r12+PeSection.vaddr]
    add eax, r13d
    mov [rbp-96], eax          ; rva (slot)
    ; filtro start/end?
    mov ecx, [rbx+DexConfig.flags]
    cmp byte [rbx+DexConfig.has_start], 0
    je .wcs_no_s
    mov edx, [rbx+DexConfig.start_rva]
    cmp [rbp-96], edx
    jae .wcs_no_s
    jmp .wcs_oor
.wcs_no_s:
    cmp byte [rbx+DexConfig.has_end], 0
    je .wcs_in
    mov edx, [rbx+DexConfig.end_rva]
    mov eax, [rbp-96]
    cmp eax, edx
    jb .wcs_in
.wcs_oor:
    ; fora do range: lote contíguo como db
    mov r10d, r13d             ; j = k
.wcs_oor_l:
    mov eax, [rbp-80]
    cmp r10d, eax
    jae .wcs_oor_e
    mov eax, [r12+PeSection.vaddr]
    add eax, r10d              ; rva_j
    cmp byte [rbx+DexConfig.has_start], 0
    je .wcs_oor_ck_e
    cmp eax, [rbx+DexConfig.start_rva]
    jb .wcs_oor_nx
    jmp .wcs_oor_e
.wcs_oor_ck_e:
    cmp byte [rbx+DexConfig.has_end], 0
    je .wcs_oor_nx             ; sem filtros? não deveria estar aqui; sai
    cmp eax, [rbx+DexConfig.end_rva]
    jb .wcs_oor_e
.wcs_oor_nx:
    inc r10d
    ; limitar lote a 256 bytes por chamada
    mov eax, r10d
    sub eax, r13d
    cmp eax, 256
    jb .wcs_oor_l
.wcs_oor_e:
    cmp r10d, r13d
    je .wcs_in                 ; nada fora (reavaliar como in-range)
    mov rax, [rbp-72]
    mov edx, r13d
    add rax, rdx               ; va
    mov rcx, r14
    mov rdx, [rbp-88]
    add rdx, r13
    mov r8d, r10d
    sub r8d, r13d
    mov r9, rax                ; va do início do lote
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .wcs_fail
    mov r13d, r10d
    jmp .wcs_loop
.wcs_in:
    ; -nop-pad: runs de 0x90/0xCC viram mnemônicos reais (mesmos bytes)
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NOP_PAD
    jz .wcs_disasm
    mov rax, [rbp-88]          ; fptr
    movzx ecx, byte [rax+r13]
    cmp cl, 0x90
    je .wcs_pad_nop
    cmp cl, 0xCC
    jne .wcs_disasm
    lea rdx, [rel s_int3]
    jmp .wcs_pad_emit
.wcs_pad_nop:
    lea rdx, [rel s_nop]
.wcs_pad_emit:
    mov [rbp-104], rdx         ; spill str
    mov rax, [rbp-72]
    mov edx, r13d
    add rax, rdx               ; va
    mov rcx, r14
    mov rdx, rax
    sub rsp, 32
    call dex_emit_label
    add rsp, 32
    test eax, eax
    jnz .wcs_fail
    mov rdx, [rbp-104]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .wcs_fail
    inc r13d
    jmp .wcs_loop
.wcs_disasm:
    mov rax, [rbp-72]
    mov edx, r13d
    add rax, rdx               ; va
    mov rcx, r15
    mov rdx, rax
    lea r8, [rel g_insn]
    sub rsp, 32
    call dex_disasm_one
    add rsp, 32
    mov [rbp-104], eax         ; len
    mov eax, [rbp-104]
    test eax, eax
    jnz .wcs_have_len
    ; defensivo: byte inacessível (não deveria ocorrer) -> db 1
    mov rax, [rbp-88]
    movzx ecx, byte [rax+r13]
    lea rax, [rel g_insn]
    mov dword [rax+Insn.length], 1
    mov [rax+Insn.raw], cl
    mov dword [rbp-104], 1
.wcs_have_len:
    ; cruza o fim da seção?
    mov eax, r13d
    add eax, [rbp-104]
    cmp eax, [rbp-80]
    jbe .wcs_emit
    ; truncada no fim: resto como db e termina
    mov rcx, r14
    mov rdx, [rbp-88]
    add rdx, r13
    mov eax, [rbp-80]
    sub eax, r13d
    mov r8d, eax
    mov rax, [rbp-72]
    mov r9d, r13d
    add r9, rax
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .wcs_fail
    jmp .wcs_ok
.wcs_emit:
    ; R-6.4 (fatia 2a): lift classifica+resolve (o oploop manual de refs
    ; morreu aqui); codegen emite (label+nativo, rollback interno) ou
    ; devolve 1 -> db. Comportamento idêntico ao anterior: tkind DATA e
    ; IMPORT seguem db (fatias 2b/3 ligam); suite + fc /b provam.
    ; NOTA: sem rewrite de IAT — db preserva os disp32 RIP-rel originais
    ; e a .idata é copiada byte-exata (mesma base). Ver ARQUITETURA.md.
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NATIVE
    jz .wcs_emit_db
    lea rcx, [rel g_insn]
    sub rsp, 32
    call dex_build_operands
    add rsp, 32
    test eax, eax
    jnz .wcs_emit_db
    lea rcx, [rel g_insn]
    lea rdx, [rel g_liftctx]
    lea r8, [rel g_ir]
    sub rsp, 32
    call dex_lift_insn
    add rsp, 32
    test eax, eax
    jnz .wcs_emit_db              ; defensivo (args sempre válidos aqui)
    ; IMPORT? nome __imp_ em g_impname (r9); sem entry/nome -> db.
    ; (R-6.4 fatia 3: label-at-slot, sem extern — vale p/ qualquer DLL.)
    xor r9d, r9d
    cmp dword [rel g_ir+DexIR.tkind], IRT_IMPORT
    jne .wcs_cg
    mov rax, [rel g_ir+DexIR.imp]
    test rax, rax
    jz .wcs_cg
    mov r8, [rax+ImportEntry.dll_name]
    mov r9, [rax+ImportEntry.func_name]
    movzx edx, byte [rax+ImportEntry.is_ordinal]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_impname]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .wcs_emit_db             ; nome impossível: db honesto
    lea r9, [rel g_impname]
.wcs_cg:
    mov rcx, r14
    lea rdx, [rel g_insn]
    lea r8, [rel g_ir]
    sub rsp, 32
    call dex_codegen_ir
    add rsp, 32
    test eax, eax
    jz .wcs_emit_ok
    cmp eax, ERR_OOM
    je .wcs_fail                  ; OOM real (label): fatal
    jmp .wcs_emit_db              ; 1 -> db (rollback já feito no codegen)
.wcs_emit_db:
    mov rcx, r14
    lea rdx, [rel g_insn]
    xor r8d, r8d               ; impname = NULL
    xor r9d, r9d               ; kind = 0 (db)
    sub rsp, 32
    call dex_emit_insn
    add rsp, 32
    test eax, eax
    jnz .wcs_fail
.wcs_emit_ok:
    add r13d, [rbp-104]
    jmp .wcs_loop
.wcs_ok:
    xor eax, eax
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.wcs_fail:
    mov eax, 1
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; .walk_data_sec — rcx=cfg, rdx=img, r8=buf, r9=sec -> eax=0 ok, 1 oom
; Dados como db; com DF_STRINGS, runs ASCII>=8+NUL viram db "...", 0.
.walk_data_sec:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov rbx, rcx               ; cfg
    mov r15, rdx               ; img
    mov r14, r8                ; buf
    mov r12, r9                ; sec
    mov rsi, [r15+PeImage.file_buffer]
    mov rdi, [r15+PeImage.image_base]
    mov eax, [r12+PeSection.vaddr]
    add rax, rdi
    mov [rbp-72], rax          ; va_base
    mov eax, [r12+PeSection.raw_size]
    mov [rbp-80], eax          ; raw
    mov eax, [r12+PeSection.raw_ptr]
    lea rax, [rsi+rax]
    mov [rbp-88], rax          ; fptr
    ; trim .pdata/.xdata p/ vsize (link valida unwind; zeros finais = LNK1223)
    lea rcx, [rel s_pdata]
    lea rdx, [r12+PeSection.name]
    sub rsp, 32
    call .secname_eq
    add rsp, 32
    test eax, eax
    jnz .wds_trim
    lea rcx, [rel s_xdata]
    lea rdx, [r12+PeSection.name]
    sub rsp, 32
    call .secname_eq
    add rsp, 32
    test eax, eax
    jz .wds_notrim
.wds_trim:
    mov eax, [r12+PeSection.vsize]
    test eax, eax
    jz .wds_notrim
    mov ecx, [rbp-80]          ; raw
    cmp eax, ecx
    jae .wds_notrim            ; vsize >= raw: nada a aparar
    ; guarda: align_up(vaddr+trim)==align_up(vaddr+raw)?
    mov [rbp-104], eax         ; spill vsize
    mov [rbp-112], ecx         ; spill raw
    mov rax, [r15+PeImage.opt_header]
    mov eax, [rax+ OH64_SECTION_ALIGN]
    test eax, eax
    jz .wds_notrim_r
    mov ecx, eax
    dec ecx                    ; mask = align-1 (align é potência de 2)
    mov eax, [r12+PeSection.vaddr]
    add eax, [rbp-112]         ; vaddr+raw
    and eax, ecx               ; page_off
    mov edx, [rbp-112]
    sub edx, [rbp-104]         ; trim = raw-vsize
    test eax, eax
    jz .wds_trim_ok            ; termina em boundary: seguro
    cmp eax, edx
    jbe .wds_notrim_r          ; cruzaria boundary: não aparar
.wds_trim_ok:
    mov eax, [rbp-104]
    mov [rbp-80], eax          ; raw = vsize
    jmp .wds_notrim
.wds_notrim_r:
    mov eax, [rbp-112]
    mov [rbp-80], eax
.wds_notrim:
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_STRINGS
    jz .wds_plain
    xor r13d, r13d             ; k
.wds_loop:
    mov eax, [rbp-80]
    cmp r13d, eax
    jae .wds_ok
    mov rcx, [rbp-88]
    add rcx, r13               ; p
    mov edx, [rbp-80]
    sub edx, r13d              ; restante
    sub rsp, 32
    call .str_run              ; rax = run_len ou 0
    add rsp, 32
    test eax, eax
    jz .wds_gap
    mov [rbp-104], eax         ; slen
    ; R-6.4 2b (só -native): R estritamente dentro do run? O label do
    ; início cobre ref exata (lea msg); interior quebraria o "..." do
    ; qstr (split somaria NULs) — degrada o run p/ gap db (bytes iguais).
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NATIVE
    jz .wds_run
    mov rax, [rel g_rn]
    test rax, rax
    jz .wds_run
    mov rcx, [rel g_rarr]
    xor r10d, r10d               ; idx (sem calls aqui: voláteis livres)
    mov r11, [rbp-72]
    mov edx, r13d
    add r11, rdx                 ; lo = va+k (exclusivo)
    mov edx, [rbp-104]
    inc edx                      ; +NUL
    add rdx, r11                 ; hi = va+k+slen+1 (exclusivo)
.wrd_l:
    cmp r10, rax
    jae .wrd_impscan
    mov r8, [rcx+r10*8]          ; key (ordenado: va crescente)
    mov r9, rdi
    add r9, r8                   ; va
    cmp r9, r11
    jbe .wrd_nx
    cmp r9, rdx
    jae .wrd_impscan             ; ordenado: resto também fora
    jmp .wds_run_degrade
.wrd_nx:
    inc r10
    jmp .wrd_l
.wrd_impscan:
    ; Slots de import estritamente dentro do run? (imports NÃO são
    ; ordenados por VA: varre tudo, sem break cedo.) lo/hi como acima.
    ; img/base via global em rsi (rdi/r15 do walker intactos).
    mov rax, [rel g_liftctx]
    mov rsi, [rax+PeImage.image_base]
    mov ecx, [rax+PeImage.imports_count]
    mov rax, [rax+PeImage.imports_ptr]
    test rax, rax
    jz .wds_run
    test ecx, ecx
    jz .wds_run
    xor r10d, r10d               ; i
.wrd_il:
    cmp r10d, ecx
    jae .wds_run
    mov r8d, r10d
    imul r8d, SIZEOF_IMPORT_ENTRY
    add r8, rax                  ; entry
    mov r9d, [r8+ImportEntry.iat_rva]
    mov r8, rsi
    add r8, r9                   ; slotVA
    cmp r8, r11
    jbe .wrd_inx
    cmp r8, rdx
    jae .wrd_inx                 ; fora (mas segue: sem ordem)
    jmp .wds_run_degrade
.wrd_inx:
    inc r10d
    jmp .wrd_il
.wds_run_degrade:
    mov eax, [rbp-104]
    mov r10d, r13d
    add r10d, eax
    inc r10d                     ; j = k+slen+1 (regra lab0 do gap vale)
    jmp .wds_gap_emit
.wds_run:
    mov rax, [rbp-72]
    mov edx, r13d
    add rax, rdx               ; va
    mov rcx, r14
    mov rdx, rax
    sub rsp, 32
    call dex_emit_label
    add rsp, 32
    test eax, eax
    jnz .wds_fail
    mov rcx, r14
    mov rdx, [rbp-88]
    add rdx, r13
    mov r8d, [rbp-104]
    sub rsp, 32
    call .emit_qstr
    add rsp, 32
    test eax, eax
    jnz .wds_fail
    mov eax, [rbp-104]
    add eax, 1                 ; +NUL
    add r13d, eax
    jmp .wds_loop
.wds_gap:
    mov r10d, r13d             ; j = k
.wds_gap_l:
    mov eax, [rbp-80]
    cmp r10d, eax
    jae .wds_gap_e
    mov eax, r10d
    sub eax, r13d
    cmp eax, 256
    jae .wds_gap_e
    mov rcx, [rbp-88]
    add rcx, r10
    mov edx, [rbp-80]
    sub edx, r10d
    mov [rbp-104], r10d        ; spill j
    mov [rbp-112], r13d        ; spill k
    sub rsp, 32
    call .str_run
    add rsp, 32
    mov r10d, [rbp-104]
    mov r13d, [rbp-112]
    test eax, eax
    jnz .wds_gap_e
    inc r10d
    jmp .wds_gap_l
.wds_gap_e:
    mov rcx, r14
    mov rdx, [rbp-88]
    add rdx, r13
    mov r8d, r10d
    sub r8d, r13d
    jz .wds_skip_gap           ; defensivo (não deve ocorrer)
    test r13d, r13d
    jnz .wds_gap_nolab
    mov r9, [rbp-72]
    jmp .wds_gap_emit
.wds_gap_nolab:
    mov r9, -1
.wds_gap_emit:
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_NATIVE
    jz .wds_gap_db              ; sem -native: legado
    mov rcx, r14                ; buf
    mov rdx, [rbp-88]           ; fptr
    mov r8, [rbp-72]            ; va_base
    mov r9d, r13d               ; k0 = k (k1 = j já está em r10d)
    test r13d, r13d
    jnz .wds_gap_labok
    mov r11, [rbp-72]           ; k==0: lab0 = va_base (igual ao legado)
    jmp .wds_gap_go
.wds_gap_labok:
    mov r11, -1                 ; meio: sem label (igual ao legado)
.wds_gap_go:
    mov rax, [rel g_liftctx]     ; img p/ chunks (via global dedicada)
    mov [rel g_chunkimg], rax
    mov [rbp-120], r10d          ; spill j (r10d volátil morre no call)
    sub rsp, 32
    call .wds_chunks
    add rsp, 32
    test eax, eax
    jnz .wds_fail
    mov r13d, [rbp-120]          ; k = j (era r10d)
    jmp .wds_loop
.wds_gap_db:
    mov rcx, r14
    mov rdx, [rbp-88]
    add rdx, r13
    mov r8d, r10d
    sub r8d, r13d
    mov r9, -1
    test r13d, r13d
    jnz .wds_gap_dbgo
    mov r9, [rbp-72]
.wds_gap_dbgo:
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .wds_fail
    mov r13d, r10d
    jmp .wds_loop
.wds_skip_gap:
    inc r13d
    jmp .wds_loop
.wds_plain:
    mov eax, [rbp-80]
    test eax, eax
    jz .wds_ok
    mov ecx, [rbx+DexConfig.flags]
    test ecx, DF_NATIVE
    jz .wds_plain_db            ; sem -native: byte-idêntico ao legado
    ; R-6.4 2b: fatia [0,raw) nos alvos R (labels reais p/ refs RIP).
    mov rcx, r14                ; buf
    mov rdx, [rbp-88]           ; fptr
    mov r8, [rbp-72]            ; va_base
    xor r9d, r9d                ; k0 = 0
    mov r10d, eax               ; k1 = raw
    mov r11, [rbp-72]           ; lab0 = va_base (igual ao legado)
    mov rax, [rel g_liftctx]     ; img p/ chunks (via global dedicada)
    mov [rel g_chunkimg], rax
    sub rsp, 32
    call .wds_chunks
    add rsp, 32
    test eax, eax
    jnz .wds_fail
    jmp .wds_ok
.wds_plain_db:
    mov rcx, r14
    mov rdx, [rbp-88]
    mov r8d, [rbp-80]
    mov r9, [rbp-72]
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .wds_fail
.wds_ok:
    xor eax, eax
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.wds_fail:
    mov eax, 1
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; .wds_chunks — rcx=buf, rdx=fptr, r8=va_base, r9=k0, r10=k1, r11=lab0
; (img via g_chunkimg, setado pelo caller) -> eax=0 ok | 1 oom.
; Emite [k0,k1) fatiado nos alvos R estritamente dentro (cada fatia com
; label da própria VA); 1ª fatia usa lab0 (-1 = sem label, igual ao
; legado). Chunks vazios pulados; R fora do intervalo ignorado (break
; cedo, ordenado). Fatias rotuladas ainda ganham `__imp_X:` se o início
; for slot de import (fatia 3). Slots em [rbp-104,-64): fora do shadow
; dos calls internos (estrito).
.wds_chunks:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rdi
    push rsi                     ; 8 pushes (64B) + sub 40 = 104 ≡ 8
    sub rsp, 40
    mov rbx, rcx                 ; buf (primeiro: rcx morre abaixo)
    mov r12, rdx                 ; fptr
    mov r13, r8                  ; va_base
    mov r14d, r9d                ; cur = k0
    mov r15d, r10d               ; k1
    mov rdi, r11                 ; curlab = lab0
    mov rax, [rel g_chunkimg]    ; img (global dedicada, setada pelo caller)
    mov rsi, [rax+PeImage.image_base] ; base
    mov [rbp-104], rax           ; img (p/ __imp_; slot livre; era -100 que
                               ; colidia com va em -96: 2 qwords a 4B!)
    mov rax, [rel g_rn]
    mov [rbp-80], rax            ; n
    mov rax, [rel g_rarr]
    mov [rbp-88], rax            ; rarr
    mov qword [rbp-72], 0        ; idx
.wcc_l:
    mov rax, [rbp-80]            ; n
    cmp [rbp-72], rax
    jae .wcc_tail
    mov rcx, [rbp-88]            ; rarr
    mov rdx, [rbp-72]            ; idx
    mov rax, [rcx+rdx*8]         ; key
    add rax, rsi                 ; va
    mov rcx, r13
    mov edx, r14d
    add rcx, rdx                 ; pos = va_base+cur
    cmp rax, rcx
    jb .wcc_next                 ; antes de cur: pula
    mov rcx, r13
    mov edx, r15d
    add rcx, rdx                 ; fim = va_base+k1
    cmp rax, rcx
    jae .wcc_tail                ; ordenado: resto fora
    mov [rbp-96], rax            ; va (sobrevive ao call)
    sub rax, r13                 ; off (cabe: < k1 <= raw < 2^32)
    cmp eax, r14d
    je .wcc_uplab                ; na posição: promove label, sem fatia
    ; __imp_ no início deste chunk? (slot; antes do emit: regs vivos)
    mov rax, r13
    mov ecx, r14d
    add rax, rcx                 ; chunkVA = va_base+cur
    mov rcx, rbx
    mov rdx, rax
    mov r8, [rbp-104]            ; img
    sub rsp, 32
    call dex_emit_imp_label
    add rsp, 32
    test eax, eax
    jnz .wcc_fail
    mov rax, [rbp-96]            ; va (recarrega: call matou voláteis)
    sub rax, r13                 ; off
    mov r10d, eax
    sub r10d, r14d               ; len (>0: off > cur)
    mov rcx, rbx
    lea rdx, [r12+r14]
    mov r8d, r10d
    mov r9, rdi                  ; curlab
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .wcc_fail
    mov rax, [rbp-96]            ; va
    sub rax, r13
    mov r14d, eax                ; cur = off
    mov rdi, [rbp-96]            ; curlab = va
.wcc_next:
    inc qword [rbp-72]
    jmp .wcc_l
.wcc_uplab:
    mov rdi, [rbp-96]            ; curlab = va
    inc qword [rbp-72]
    jmp .wcc_l
.wcc_tail:
    cmp r14d, r15d
    jae .wcc_done
    ; __imp_ no início do tail?
    mov rax, r13
    mov ecx, r14d
    add rax, rcx                 ; chunkVA = va_base+cur
    mov rcx, rbx
    mov rdx, rax
    mov r8, [rbp-104]            ; img
    sub rsp, 32
    call dex_emit_imp_label
    add rsp, 32
    test eax, eax
    jnz .wcc_fail
    mov r10d, r15d
    sub r10d, r14d               ; len (tail)
    mov rcx, rbx
    lea rdx, [r12+r14]
    mov r8d, r10d
    mov r9, rdi
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .wcc_fail
.wcc_done:
    xor eax, eax
    add rsp, 40
    pop rsi
    pop rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.wcc_fail:
    mov eax, 1
    add rsp, 40
    pop rsi
    pop rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; .str_run — rcx=p, edx=restante -> rax=run_len (>=8, seguido de NUL) ou 0
.str_run:
    push rbx
    mov rbx, rcx
    xor eax, eax               ; n
.sr_l:
    cmp eax, edx
    jae .sr_no
    movzx ecx, byte [rbx+rax]
    cmp cl, 32
    jb .sr_ck
    cmp cl, 126
    jbe .sr_nx
.sr_ck:
    cmp eax, 8
    jb .sr_no
    test cl, cl
    jnz .sr_no
    pop rbx
    ret
.sr_nx:
    inc eax
    jmp .sr_l
.sr_no:
    xor eax, eax
    pop rbx
    ret

; .emit_qstr — rcx=buf, rdx=ptr, r8d=len -> '    db "...", 0' (escapa ")
.emit_qstr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    mov r13d, r8d
    lea rdx, [rel s_db_pre]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .eq_fail
    xor r14d, r14d
.eq_l:
    cmp r14d, r13d
    jae .eq_end
    movzx eax, byte [r12+r14]
    cmp al, '"'
    je .eq_esc
    mov [rbp-48], al
    lea rdx, [rbp-48]
    mov rcx, rbx
    mov r8, 1
    sub rsp, 32
    call asmbuf_append
    add rsp, 32
    test eax, eax
    jnz .eq_fail
    inc r14d
    jmp .eq_l
.eq_esc:
    lea rdx, [rel s_q34]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .eq_fail
    inc r14d
    jmp .eq_l
.eq_end:
    lea rdx, [rel s_q0]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
.eq_fail:
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_rebuild — rcx=cfg, rdx=img -> rax=0 ok, 5 falha
; Ownership: paths derivados vazam p/ o processo (exit em seguida).
;-----------------------------------------------------------------------------
dex_rebuild:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov rbx, rcx               ; cfg
    mov r15, rdx               ; img
    mov eax, [rcx+DexConfig.mode]
    cmp eax, DEX_MODE_BIN
    je .rb_bin
    ; obj = ext(output_asm, ".obj")
    mov rcx, [rbx+DexConfig.output_asm]
    lea rdx, [rel s_dot_o]
    sub rsp, 32
    call .derive_ext
    add rsp, 32
    test rax, rax
    jz .rb_fail
    mov [rbp-72], rax          ; obj
    jmp .rb_exe_common
.rb_bin:
    ; modo bin: nasm -f bin -o <exe> <asm> (sem obj, sem link, sem patch)
    mov rax, [rbx+DexConfig.output_exe]
    test rax, rax
    jnz .rb_bin_exe
    mov rcx, [rbx+DexConfig.input_path]
    lea rdx, [rel s_dot_rb]
    sub rsp, 32
    call .derive_ext
    add rsp, 32
    test rax, rax
    jz .rb_fail
    mov [rbx+DexConfig.output_exe], rax
.rb_bin_exe:
    mov rax, [rbx+DexConfig.output_exe]
    mov [rbp-80], rax          ; exe
    mov rcx, 32768
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .rb_fail
    mov r14, rax
    mov [rbp-88], rax          ; cmd
    mov rcx, rax
    mov rdx, [rbx+DexConfig.nasm_path]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    mov r14, rax
    test rax, rax
    jz .rb_fail
    lea rdx, [rel s_bin_args]
    mov rcx, r14
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov r14, rax
    test rax, rax
    jz .rb_fail
    mov rcx, r14
    mov rdx, [rbp-80]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    mov r14, rax
    test rax, rax
    jz .rb_fail
    mov rcx, r14
    mov edx, ' '
    sub rsp, 32
    call .cmd_putc
    add rsp, 32
    mov r14, rax
    test rax, rax
    jz .rb_fail
    mov rcx, r14
    mov rdx, [rbx+DexConfig.output_asm]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    test rax, rax
    jz .rb_fail
    mov rcx, [rbp-88]
    sub rsp, 32
    call .run_one
    add rsp, 32
    cmp rax, 0
    jne .rb_nasm_fail
    xor eax, eax
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.rb_exe_common:
    ; exe = output_exe ou ext(input, ".rebuild.exe")
    mov rax, [rbx+DexConfig.output_exe]
    test rax, rax
    jnz .rb_exe_set
    mov rcx, [rbx+DexConfig.input_path]
    lea rdx, [rel s_dot_rb]
    sub rsp, 32
    call .derive_ext
    add rsp, 32
    test rax, rax
    jz .rb_fail
    mov [rbx+DexConfig.output_exe], rax
.rb_exe_set:
    mov rax, [rbx+DexConfig.output_exe]
    mov [rbp-80], rax          ; exe
    ; cmd = malloc(32768)
    mov rcx, 32768
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .rb_fail
    mov r14, rax               ; cmd buf
    mov [rbp-88], rax
    ; ---- comando nasm ----
    mov rcx, r14
    mov rdx, [rbx+DexConfig.nasm_path]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    mov r14, rax
    lea rdx, [rel s_nasm_args]
    mov rcx, r14
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov r14, rax
    mov rcx, r14
    mov rdx, [rbp-72]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    mov r14, rax
    mov rcx, r14
    mov edx, ' '
    sub rsp, 32
    call .cmd_putc
    add rsp, 32
    mov r14, rax
    mov rcx, r14
    mov rdx, [rbx+DexConfig.output_asm]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    mov r14, rax
    test rax, rax
    jz .rb_fail
    mov rcx, [rbp-88]
    sub rsp, 32
    call .run_one
    add rsp, 32
    cmp rax, 0
    jne .rb_nasm_fail
    ; ---- comando link ----
    mov r14, [rbp-88]
    mov byte [r14], 0          ; reutilizar buffer
    mov rcx, r14
    mov rdx, [rbx+DexConfig.linker_path]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    mov r14, rax
    lea rdx, [rel s_link_pre]
    mov rcx, r14
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov r14, rax
    ; subsystem: opt+68: 2=WINDOWS senão CONSOLE
    mov rax, [r15+PeImage.opt_header]
    movzx eax, word [rax+ OH64_SUBSYSTEM]
    cmp eax, 2
    je .rb_gui
    lea rdx, [rel s_console]
    jmp .rb_sub
.rb_gui:
    lea rdx, [rel s_windows]
.rb_sub:
    mov rcx, r14
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov r14, rax
    lea rdx, [rel s_dynbase]
    mov rcx, r14
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov r14, rax
    ; base hex
    mov rcx, r14
    mov rdx, [r15+PeImage.image_base]
    sub rsp, 32
    call .cmd_hex
    add rsp, 32
    mov r14, rax
    lea rdx, [rel s_entry]
    mov rcx, r14
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov r14, rax
    ; "label_<entry_va hex>"
    mov rax, [r15+PeImage.image_base]
    add rax, [r15+PeImage.entry_point]
    mov [rbp-96], rax
    mov rcx, r14
    lea rdx, [rel s_lab]
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov r14, rax
    mov rcx, r14
    mov rdx, [rbp-96]
    sub rsp, 32
    call .cmd_hex
    add rsp, 32
    mov r14, rax
    lea rdx, [rel s_out]
    mov rcx, r14
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov r14, rax
    mov rcx, r14
    mov rdx, [rbp-80]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    mov r14, rax
    mov rcx, r14
    mov edx, ' '
    sub rsp, 32
    call .cmd_putc
    add rsp, 32
    mov r14, rax
    mov rcx, r14
    mov rdx, [rbp-72]
    sub rsp, 32
    call .cmd_quoted
    add rsp, 32
    test rax, rax
    jz .rb_fail
    mov rcx, [rbp-88]
    sub rsp, 32
    call .run_one
    add rsp, 32
    cmp rax, 0
    jne .rb_link_fail
    ; adotar DataDirectories originais (imports/recursos/pdata/...) que o
    ; linker não regenerou a partir de bytes db
    mov rcx, rbx
    mov rdx, r15
    sub rsp, 32
    call dex_patch_dirs
    add rsp, 32
    test eax, eax
    jnz .rb_link_fail
    xor eax, eax
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.rb_nasm_fail:
    lea rcx, [rel e_rb_n]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    jmp .rb_5
.rb_link_fail:
    lea rcx, [rel e_rb_l]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    jmp .rb_5
.rb_fail:
    lea rcx, [rel e_rb_c]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
.rb_5:
    mov eax, 5
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

.derive_ext:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    sub rsp, 32
    mov rbx, rcx               ; src
    mov r14, rdx               ; ext
    mov rcx, rbx
    sub rsp, 32
    call dex_strlen
    add rsp, 32
    mov r12, rax               ; slen
    mov rcx, r14
    sub rsp, 32
    call dex_strlen
    add rsp, 32
    mov r13, rax               ; elen
    ; achar corte: último '.' após última barra
    mov rsi, rbx
    add rsi, r12               ; fim
    mov rdi, rsi               ; dot = fim (default: anexar)
    mov rax, rbx               ; cur
.de_scan:
    cmp rax, rsi
    jae .de_have
    movzx ecx, byte [rax]
    cmp cl, 92
    je .de_sep
    cmp cl, 47
    je .de_sep
    cmp cl, 46
    je .de_dot
    inc rax
    jmp .de_scan
.de_sep:
    mov rdi, rsi               ; reset dot após separador
    inc rax
    jmp .de_scan
.de_dot:
    mov rdi, rax
    inc rax
    jmp .de_scan
.de_have:
    ; cut = (dot==fim) ? slen : dot-src
    mov rax, r12
    cmp rdi, rsi
    je .de_cut_ok
    mov rax, rdi
    sub rax, rbx
.de_cut_ok:
    lea rcx, [rax+r13+1]
    mov [rbp-80], rax          ; cut (slot)
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .de_fail
    mov rdi, rax               ; dst
    mov rcx, rax
    mov rdx, rbx
    mov r8, [rbp-80]
    sub rsp, 32
    call dex_memcpy
    add rsp, 32
    mov rcx, rdi
    add rcx, [rbp-80]
    mov rdx, r14
    mov r8, r13
    add r8, 1                  ; +NUL
    sub rsp, 32
    call dex_memcpy
    add rsp, 32
    mov rax, rdi
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.de_fail:
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; .cmd_appends — rcx=dst, rdx=cstr -> rax=novo dst (0 se >16KB)
.cmd_appends:
    push rbx
    push rdi
    mov rbx, rcx
    mov rdi, rdx
    mov rcx, rdi
    sub rsp, 32
    call dex_strlen
    add rsp, 32
    cmp rax, 16000
    ja .ca_oom
    mov rcx, rbx               ; dst (rcx ainda tem src do strlen!)
    mov rdx, rdi               ; src
    mov r8, rax                ; len
    test r8, r8
    jz .ca_done
    sub rsp, 32
    call dex_memcpy
    add rsp, 32
.ca_done:
    mov rax, rbx
    add rax, r8
    mov byte [rax], 0
    pop rdi
    pop rbx
    ret
.ca_oom:
    xor eax, eax
    pop rdi
    pop rbx
    ret

; .cmd_putc — rcx=dst, edx=char -> rax=novo dst
.cmd_putc:
    mov [rcx], dl
    mov byte [rcx+1], 0
    lea rax, [rcx+1]
    ret

; .cmd_quoted — rcx=dst, rdx=path -> rax=novo dst ('"path"')
.cmd_quoted:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    mov byte [rbx], '"'
    lea rcx, [rbx+1]
    mov rdx, r12
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    mov byte [rax], '"'
    lea rax, [rax+1]
    mov byte [rax], 0
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

; .cmd_hex — rcx=dst, rdx=valor -> rax=novo dst
.cmd_hex:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 48
    mov rbx, rcx
    mov r12, rdx
    sub rsp, 32
    lea rdx, [rbp-48]          ; tmp 16B ([rbp-48..-33]; NUL cabe até [-32])
    mov rcx, r12
    xor r8d, r8d
    call dex_u64_to_hex        ; rax = len (0..16)
    add rsp, 32
    lea rcx, [rbp-48]
    mov byte [rcx+rax], 0      ; NUL-terminar (len<=16: máx [rbp-32], seguro)
    mov rdx, rcx
    mov rcx, rbx
    sub rsp, 32
    call .cmd_appends
    add rsp, 32
    add rsp, 48
    pop r12
    pop rbx
    pop rbp
    ret

; .run_one — rcx=cmdline(mutável) -> rax=exit code ou -1
; Frame 224, sem sub interno: sombra em [rsp..31], args em [rsp+32..79],
; STARTUPINFO em [rsp+80..183], PROCESS_INFORMATION em [rsp+184..207],
; exit code em [rsp+208].
.run_one:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push r12
    sub rsp, 216               ; 4 pushes -> rsp%16==8; 216%16==8 => ok
    mov rbx, rcx               ; cmd
    lea rdi, [rsp+80]
    xor eax, eax
    mov ecx, 32                ; 32*4 = 128 bytes (si 104 + pi 24)
    rep stosd
    mov dword [rsp+80], 104    ; si.cb
    ; CreateProcessA(NULL, cmd, NULL,NULL,FALSE, 0, NULL,NULL, &si, &pi)
    xor ecx, ecx               ; lpApp = NULL
    mov rdx, rbx               ; lpCmd
    xor r8d, r8d
    xor r9d, r9d
    mov qword [rsp+32], 0      ; bInherit
    mov qword [rsp+40], 0      ; flags
    mov qword [rsp+48], 0      ; env
    mov qword [rsp+56], 0      ; dir
    lea rax, [rsp+80]
    mov [rsp+64], rax          ; si
    lea rax, [rsp+184]
    mov [rsp+72], rax          ; pi
    call CreateProcessA
    test eax, eax
    jz .ro_fail
    mov rcx, [rsp+184]         ; hProcess
    mov edx, INFINITE
    call WaitForSingleObject
    mov rcx, [rsp+184]
    lea rdx, [rsp+208]
    call GetExitCodeProcess
    mov r12d, [rsp+208]        ; exit code DWORD (lê 32 bits: alto é lixo!)
    mov rcx, [rsp+184]         ; hProcess
    call CloseHandle
    mov rcx, [rsp+192]         ; hThread (pi+8)
    call CloseHandle
    mov rax, r12
    add rsp, 216
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret
.ro_fail:
    mov rax, -1
    add rsp, 216
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_patch_dirs — rcx=cfg, rdx=img -> rax=0 ok, 5 falha
; Para cada DataDirectory 0..15: se o ORIGINAL tem (rva,size) e o REBUILD
; tem slot vazio, copia os valores originais direto na imagem mapeada RW
; (tabelas copiadas byte-exato nos mesmos RVAs). Sem heap/seek/OVERLAPPED.
; Nunca sobrescreve diretório gerado pelo linker.
;-----------------------------------------------------------------------------
dex_patch_dirs:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56                ; 8 pushes -> rsp%16==8; 56%16==8 => alinhado
    mov rbx, rcx               ; cfg
    mov r15, rdx               ; img (original, ainda mapeado)
    mov rcx, [rbx+DexConfig.output_exe]
    sub rsp, 32
    call dex_open_rw
    add rsp, 32
    test rax, rax
    jz .pd_fail
    mov r14, rax               ; handle exe rebuildado
    mov rcx, rax
    sub rsp, 32
    call dex_file_size
    add rsp, 32
    cmp rax, -1
    je .pd_fail_close
    test rax, rax
    jz .pd_fail_close
    mov r13, rax               ; fsize
    mov rcx, r14
    mov rdx, rax
    sub rsp, 32
    call dex_mmap_rw
    add rsp, 32
    test rax, rax
    jz .pd_fail_close
    mov r12, rax               ; base rebuildada (rw)
    ; validar MZ + PE + x64 + opt mínimo dentro do arquivo
    cmp word [r12+0], 0x5A4D
    jne .pd_fail_um
    mov esi, [r12+0x3C]        ; e_lfanew
    mov rax, rsi
    add rax, 300
    cmp rax, r13
    ja .pd_fail_um
    cmp dword [r12+rsi], 0x4550
    jne .pd_fail_um
    cmp word [r12+rsi+4], 0x8664
    jne .pd_fail_um
    movzx eax, word [r12+rsi+20]  ; SizeOfOpt rebuild
    cmp eax, 240
    jb .pd_fail_um
    lea rdi, [r12+rsi+24]      ; opt rebuildada
    mov rax, [r15+PeImage.opt_header]  ; opt original
    mov rsi, rax
    mov eax, [rsi+108]         ; NumRva orig
    cmp eax, 16
    ja .pd_fail_um
    mov ecx, [rdi+108]         ; NumRva rebuild
    cmp ecx, 16
    ja .pd_fail_um
    xor r10d, r10d             ; i
.pd_l:
    cmp r10d, 16
    jae .pd_ok
    mov eax, r10d
    cmp eax, [rsi+108]
    jae .pd_next
    cmp eax, [rdi+108]
    jae .pd_next
    shl eax, 3                 ; i*8
    mov ecx, [rsi+112+rax]     ; orig rva
    mov edx, [rsi+112+rax+4]   ; orig size
    test ecx, ecx
    jz .pd_next
    test edx, edx
    jz .pd_next
    cmp dword [rdi+112+rax], 0
    jne .pd_next
    cmp dword [rdi+112+rax+4], 0
    jne .pd_next
    mov [rdi+112+rax], ecx     ; patch direto na memória (rw)
    mov [rdi+112+rax+4], edx
.pd_next:
    inc r10d
    jmp .pd_l
.pd_ok:
    mov rcx, r12
    sub rsp, 32
    call dex_unmap             ; flush + unmap
    add rsp, 32
    mov rcx, r14
    sub rsp, 32
    call dex_close
    add rsp, 32
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
.pd_fail_um:
    mov rcx, r12
    sub rsp, 32
    call dex_unmap
    add rsp, 32
.pd_fail_close:
    mov rcx, r14
    sub rsp, 32
    call dex_close
    add rsp, 32
.pd_fail:
    mov eax, 5
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

;-----------------------------------------------------------------------------
; dex_generate_bin — rcx=cfg, rdx=img -> rax=0 ok, 2 io, 6 oom
; Modo bin: .asm = cópia byte-fiel (headers + seções + overlay) p/ nasm -f bin.
; Sem desassemblagem; labels só p/ legibilidade. Determinístico.
;-----------------------------------------------------------------------------
dex_generate_bin:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov rbx, rcx               ; cfg
    mov r15, rdx               ; img
    mov eax, [rbx+DexConfig.flags]
    xor ecx, ecx
    test eax, DF_HEXDUMP
    jz .no_hex_b
    mov ecx, 1
.no_hex_b:
    sub rsp, 32
    call dex_emit_set_hex
    add rsp, 32
    mov eax, [rbx+DexConfig.flags]
    and eax, DF_NOP_PAD | DF_NO_IMPORTS | DF_NO_RELOCS | DF_STRINGS | DF_NATIVE
    jz .gb_noflagwarn
    cmp qword [rbx+DexConfig.section_filter], 0
    jne .gb_warn
    cmp byte [rbx+DexConfig.has_start], 0
    jne .gb_warn
    cmp byte [rbx+DexConfig.has_end], 0
    jne .gb_warn
    test eax, eax
    jz .gb_noflagwarn
.gb_warn:
    cmp dword [rbx+DexConfig.quiet], 0
    jne .gb_noflagwarn
    lea rcx, [rel s_bin_warn]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
.gb_noflagwarn:
    mov rcx, 0x10000
    sub rsp, 32
    call asmbuf_new
    add rsp, 32
    test rax, rax
    jz .gb_oom
    mov r14, rax               ; buf
    lea rdx, [rel s_bin_hdr]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    mov rsi, [r15+PeImage.file_buffer]
    mov rdi, rsi               ; file base (rdi preservado: sem uso volátil aqui? não—
                               ; rdi é non-vol e não o usamos como scratch abaixo. OK)
    mov rax, [r15+PeImage.file_size]
    mov [rbp-72], rax          ; fsize
    mov rax, [r15+PeImage.opt_header]
    mov eax, [rax+ OH64_SIZE_OF_HEADERS]
    test eax, eax
    jz .gb_io_free
    cmp rax, [rbp-72]
    ja .gb_io_free
    mov [rbp-80], rax          ; hdrsz
    ; headers como db
    mov rcx, r14
    mov rdx, rsi
    mov r8d, eax
    mov r9, -1
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    mov r13, [rbp-80]          ; cur = hdrsz
    ; seções em ordem de cabeçalho
    mov eax, [r15+PeImage.num_sections]
    mov [rbp-88], eax          ; nsec
    xor r10d, r10d             ; i
    mov r12, [r15+PeImage.sections_ptr]
.gb_sec:
    cmp r10d, [rbp-88]
    jae .gb_overlay
    mov eax, r10d
    imul eax, SIZEOF_PE_SECTION
    lea rax, [r12+rax]         ; sec
    mov [rbp-96], rax          ; spill sec
    mov [rbp-104], r10d        ; spill i
    mov ecx, [rax+PeSection.raw_size]
    mov edx, [rax+PeSection.raw_ptr]
    test ecx, ecx
    jz .gb_bss                 ; sem bytes: só comentário
    cmp rdx, r13
    jb .gb_io_free             ; overlap: PE inválido p/ bin
    je .gb_nopad
    ; pad: "    times 0x<N> db 0\n"
    mov [rbp-112], rcx         ; spill raw
    mov [rbp-120], rdx         ; spill rptr
    lea rdx, [rel s_times]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    mov rax, [rbp-120]
    sub rax, r13               ; N = rptr - cur
    mov rcx, r14
    mov rdx, rax
    xor r8d, r8d
    sub rsp, 32
    call asmbuf_append_u64_hex
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    lea rdx, [rel s_db0]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    mov rcx, [rbp-112]
    mov rdx, [rbp-120]
    mov r13, rdx
    add r13, rcx               ; cur = rptr + raw (atualiza já)
    mov [rbp-112], rcx         ; (re-spill p/ uso abaixo; rdx será reusado)
    jmp .gb_emit_sec
.gb_nopad:
    mov [rbp-112], rcx         ; raw
    mov r13, rdx
    add r13, rcx               ; cur = rptr + raw
.gb_emit_sec:
    ; comentário "; ---- <nome> ----" + label + db
    mov rax, [rbp-96]          ; sec
    lea rdx, [rel s_secpre]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    mov rax, [rbp-96]
    lea rdx, [rax+PeSection.name]
    mov rcx, r14
    sub rsp, 32
    call .gb_secname
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    lea rdx, [rel s_crlf2]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    ; label VA (legibilidade)
    mov rax, [r15+PeImage.image_base]
    mov rcx, [rbp-96]          ; sec (64 bits! não truncar)
    mov ecx, [rcx+PeSection.vaddr]
    add rax, rcx
    mov rcx, r14
    mov rdx, rax
    sub rsp, 32
    call dex_emit_label
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    ; db dos bytes
    mov rax, [rbp-96]
    mov ecx, [rax+PeSection.raw_ptr]
    lea rdx, [rsi+rcx]         ; file_base + rptr
    mov r8d, [rbp-112]         ; raw
    mov rcx, r14
    mov r9, -1
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
.gb_next:
    mov r10d, [rbp-104]
    inc r10d
    jmp .gb_sec
.gb_bss:
    ; seção sem bytes (bss): comentário
    lea rdx, [rel s_secpre]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    mov rax, [rbp-96]
    lea rdx, [rax+PeSection.name]
    mov rcx, r14
    sub rsp, 32
    call .gb_secname
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    lea rdx, [rel s_bssnote]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    jmp .gb_next
.gb_overlay:
    ; overlay (bytes após última seção)
    mov rax, [rbp-72]          ; fsize
    cmp r13, rax
    jae .gb_write
    lea rdx, [rel s_ovl]
    mov rcx, r14
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
    mov rax, [rbp-72]
    sub rax, r13               ; restante
    mov rdx, rsi
    add rdx, r13               ; ptr
    mov r8, rax                ; len (cap 1GiB: cabe em r8d? overlay pode ser
                               ; grande; emit_data itera em linhas — len u64 ok?
                               ; dex_emit_data usa r8 como len u64? usa r12=u64 ✓)
    mov rcx, r14
    mov r9, -1
    sub rsp, 32
    call dex_emit_data
    add rsp, 32
    test eax, eax
    jnz .gb_oom_free
.gb_write:
    mov rcx, [rbx+DexConfig.output_asm]
    sub rsp, 32
    call dex_open_write
    add rsp, 32
    test rax, rax
    jz .gb_io_free2
    mov rdi, rax
    mov rcx, r14
    sub rsp, 32
    call asmbuf_data
    add rsp, 32
    mov rsi, rax
    mov rcx, r14
    sub rsp, 32
    call asmbuf_len
    add rsp, 32
    mov r8, rax
    mov rcx, rdi
    mov rdx, rsi
    sub rsp, 32
    call dex_write_all
    add rsp, 32
    mov r13d, eax
    mov rcx, rdi
    sub rsp, 32
    call dex_close
    add rsp, 32
    ; -ast-dump (R-6.5): idem path win64 (data/len recarregados).
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_ASTDUMP
    jz .no_astdump_b
    mov rcx, r14
    sub rsp, 32
    call asmbuf_data
    add rsp, 32
    mov rsi, rax
    mov rcx, r14
    sub rsp, 32
    call asmbuf_len
    add rsp, 32
    mov rdx, rax
    mov rcx, rsi
    mov r8, rbx
    sub rsp, 32
    call gen_astdump_emit
    add rsp, 32
.no_astdump_b:
    mov rcx, r14
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
    mov eax, r13d
    test eax, eax
    jnz .gb_io
    xor eax, eax
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.gb_oom_free:
    mov rcx, r14
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
.gb_oom:
    mov eax, 6
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.gb_io_free2:
    mov rcx, r14
    sub rsp, 32
    call asmbuf_free
    add rsp, 32
.gb_io_free:
.gb_io:
    mov eax, 2
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

; .gb_secname — rcx=buf, rdx=name8 -> nome (até NUL, máx 8)
.gb_secname:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32
    mov rbx, rcx
    mov r12, rdx
    xor r8d, r8d
.gs_l:
    cmp r8d, 8
    jae .gs_e
    movzx eax, byte [r12+r8]
    test al, al
    jz .gs_e
    inc r8d
    jmp .gs_l
.gs_e:
    test r8d, r8d
    jnz .gs_c
    xor eax, eax               ; nome vazio: nada a anexar, sucesso
    jmp .gs_d
.gs_c:
    mov rcx, rbx
    mov rdx, r12
    sub rsp, 32
    call asmbuf_append
    add rsp, 32
.gs_d:
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; gen_astdump_emit — helper file-scope do -ast-dump (R-6.5).
; Parseia o .asm gerado (já escrito em disco) e imprime o resumo AST.
; Args: rcx=data, rdx=len, r8=cfg. Ret: nada.
; Nunca falha a geração: parse sem memória ou .asm >16 MB = aviso em
; stderr (respeitado -q), geração segue 0. Preserva: rbx, rbp, rdi, rsi,
; r12-r15 (caller reutiliza rbx/r14/r13d após).
;-----------------------------------------------------------------------------
gen_astdump_emit:
    push rbp
    mov rbp, rsp
    push rbx
    push r14
    push r15                     ; 3 pushes + sub 32 = 56 (padrão do projeto)
    sub rsp, 32
    mov rbx, rcx                 ; data (fonte emprestada; AsmBuf segue vivo)
    mov r14, rdx                 ; len
    mov r15, r8                  ; cfg (p/ -q no aviso)
    mov qword [rbp-40], 0        ; unit=NULL
    mov rcx, rbx
    mov rdx, r14
    lea r8, [rbp-40]
    sub rsp, 32
    call dex_parse_asm
    add rsp, 32
    test eax, eax
    jnz .gae_warn
    mov rcx, [rbp-40]
    sub rsp, 32
    call dex_ast_dump
    add rsp, 32
    mov rcx, [rbp-40]
    sub rsp, 32
    call dex_ast_free_unit
    add rsp, 32
    jmp .gae_done
.gae_warn:
    mov eax, [r15+DexConfig.flags]
    test eax, DF_QUIET
    jnz .gae_done
    lea rcx, [rel e_astdump]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
.gae_done:
    add rsp, 32
    pop r15
    pop r14
    pop rbx
    pop rbp
    ret


;-----------------------------------------------------------------------------
; dex_emit_imp_label — rcx=buf, rdx=chunkVA, r8=img -> eax=0 | 1 oom.
; Se chunkVA for slot de import (qualquer DLL), emite `__imp_X:` (o loader
; preenche o slot no load; label-at-slot, sem extern — R-6.4 fatia 3).
; Nome impossível (build falha) = SKIP (0): o nasm apontará o símbolo
; ausente (alto e rastreável, nunca corrupção silenciosa). Preserva tudo
; não-volátil. (Global p/ teste direto em tests/imp_check.asm.)
;-----------------------------------------------------------------------------
dex_emit_imp_label:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14                     ; 5 pushes (40B) + sub 32 = 72 ≡ 8
    sub rsp, 32
    mov rbx, rcx                 ; buf
    mov r12, rdx                 ; va
    mov r13, r8                  ; img
    mov rax, [r13+PeImage.image_base]
    cmp r12, rax
    jb .wil_no
    sub r12, rax                 ; rva
    mov rax, r12
    shr rax, 32
    jnz .wil_no
    mov r14, [r13+PeImage.imports_ptr]
    test r14, r14
    jz .wil_no
    mov r13d, [r13+PeImage.imports_count]
    test r13d, r13d
    jz .wil_no
    xor r11d, r11d               ; i (r11 volátil; sem calls neste loop)
.wil_l:
    cmp r11d, r13d
    jae .wil_no
    mov eax, r11d
    imul eax, SIZEOF_IMPORT_ENTRY
    lea rax, [r14+rax]           ; entry
    cmp dword [rax+ImportEntry.iat_rva], r12d
    je .wil_hit
    inc r11d
    jmp .wil_l
.wil_hit:
    mov r8, [rax+ImportEntry.dll_name]
    mov r9, [rax+ImportEntry.func_name]
    movzx edx, byte [rax+ImportEntry.is_ordinal]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_impname]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .wil_no                  ; nome impossível: skip (nasm apontará)
    lea rdx, [rel g_impname]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .wil_oom
    lea rdx, [rel s_imp_colon]
    mov rcx, rbx
    sub rsp, 32
    call asmbuf_append_str
    add rsp, 32
    test eax, eax
    jnz .wil_oom
.wil_no:
    xor eax, eax
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.wil_oom:
    mov eax, 1
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret



; dex_build_impname — rcx=dst, r8=dll, r9=func|0, edx=is_ordinal, eax=ordinal
; Escreve "__imp_<dll>_<func|ordN>" sanitizado. eax=0 ok.
; (Global desde R-6.4.3: file-scope quebraria o escopo dos locais
; se movida; ver D-12. Chamadores: walker + dex_emit_imp_label.)
dex_build_impname:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    sub rsp, 40
    mov rbx, rcx
    mov r12, r8
    mov r13, r9
    mov esi, edx
    mov edi, eax
    ; checagem de comprimento total (dst tem 512 bytes; evita overflow)
    mov rdx, r12
    sub rsp, 32
    call .imp_strlen
    add rsp, 32
    mov ecx, eax
    test r13, r13
    jz .imp_len_ord
    mov rdx, r13
    sub rsp, 32
    call .imp_strlen
    add rsp, 32
    add ecx, eax
.imp_len_ord:
    add ecx, 16
    cmp ecx, 500
    ja .bi_fail
    lea rax, [rel s_imp_l]
.copy_pre:
    movzx ecx, byte [rax]
    test cl, cl
    jz .cp_dll
    mov [rbx], cl
    inc rbx
    inc rax
    jmp .copy_pre
.cp_dll:
    mov rax, r12
.cp_san:
    movzx ecx, byte [rax]
    test cl, cl
    jz .cp_us
    call .san_ch
    mov [rbx], cl
    inc rbx
    inc rax
    jmp .cp_san
.cp_us:
    mov byte [rbx], '_'
    inc rbx
    test esi, esi
    jnz .cp_ord
    mov rax, r13
    test rax, rax
    jz .bi_fail                 ; sem func e sem ordinal: inválido
    jmp .cp_san2
.cp_ord:
    mov byte [rbx], 'o'
    mov byte [rbx+1], 'r'
    mov byte [rbx+2], 'd'
    add rbx, 3
    mov eax, edi
    and eax, 0xFFFF
    test eax, eax
    jz .bi_fail
    ; decimal simples
    sub rsp, 32
    mov [rbp-64], rbx          ; salva dst (slot)
    lea rcx, [rbp-80]          ; tmp 8B ([rbp-80..-72] livre no frame)
    mov rdx, rax
    call .u16_dec
    mov rbx, [rbp-64]
    add rsp, 32
    lea rax, [rbp-80]
.cp_cat:
    movzx ecx, byte [rax]
    test cl, cl
    jz .cp_end
    mov [rbx], cl
    inc rbx
    inc rax
    jmp .cp_cat
.cp_san2:
    movzx ecx, byte [rax]
    test cl, cl
    jz .cp_end
    call .san_ch
    mov [rbx], cl
    inc rbx
    inc rax
    jmp .cp_san2
.cp_end:
    mov byte [rbx], 0
    xor eax, eax
    add rsp, 40
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.bi_fail:
    mov eax, 1
    add rsp, 40
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
; .imp_strlen: rdx=str -> rax=len (cap 300). Leaf, só usa rax/rcx.
.imp_strlen:
    xor eax, eax
.is_l:
    cmp eax, 300
    jae .is_d
    cmp byte [rdx+rax], 0
    je .is_d
    inc rax
    jmp .is_l
.is_d:
    ret
; .san_ch: cl -> alnum ou '_' (clobber: nada além de ecx)
.san_ch:
    cmp cl, 'A'
    jb .san_d
    cmp cl, 'Z'
    jbe .san_ok
    cmp cl, 'a'
    jb .san_u
    cmp cl, 'z'
    jbe .san_ok
    jmp .san_x
.san_d:
    cmp cl, '0'
    jb .san_x
    cmp cl, '9'
    jbe .san_ok
    jmp .san_x
.san_u:
    cmp cl, '_'
    je .san_ok
.san_x:
    mov cl, '_'
.san_ok:
    ret
; .u16_dec: rdx=u16, rcx=tmp(8B) -> NUL-terminado
.u16_dec:
    push rbx
    mov rax, rdx
    mov rbx, rcx
    test eax, eax
    jnz .ud_c
    mov byte [rbx], '0'
    mov byte [rbx+1], 0
    pop rbx
    ret
.ud_c:
    sub rsp, 16
    xor ecx, ecx
.ud_l:
    xor edx, edx
    mov r8d, 10
    div r8
    add dl, '0'
    mov [rsp+rcx], dl
    inc rcx
    test rax, rax
    jnz .ud_l
    xor r8d, r8d
.ud_r:
    dec rcx
    mov dl, [rsp+rcx]
    mov [rbx+r8], dl
    inc r8d
    test rcx, rcx
    jnz .ud_r
    mov byte [rbx+r8], 0
    add rsp, 16
    pop rbx
    ret
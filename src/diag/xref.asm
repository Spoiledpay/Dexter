;=============================================================================
; Dexter/src/diag/xref.asm
; dex_xrefs - quem referencia uma VA (call/jmp/branch via target_va +
; refs RIP-rel a dados), linear-sweep nas secoes de codigo.
;
; O que: lista (VA, kind, detalhe) de toda instrucao cujo alvo e a VA.
; Por que: responder "quem chama / quem usa este endereco" sem gerar .asm
;  (navegacao estilo REA: get_navigation_context/xrefs - R-7.2, marco.md).
; Contrato:
;   Args: rcx = DexConfig* (DF_JSON seleciona JSON), rdx = PeImage*
;         (validado), r8 = query VA.
;   Ret:  eax = 0 sempre (lista vazia e resposta honesta, nunca erro).
;   kinds: call | jmp (mne exato) | branch (jcc/outros) | data (RIP?dado).
;   detail: nome __imp_ se o alvo e slot IAT, senao "".
;   Cap: 256 refs exibidas; alem disso conta total + truncated (honesto).
;   Clobber: rax, rcx, rdx, r8-r11.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\run_tests.bat secao [17].
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"
%include "pe.inc"

global dex_xrefs

extern dex_disasm_one
extern dex_console_print_cstr
extern dex_console_print_u64hex
extern dex_console_print_u64dec
extern dex_console_newline
extern dex_streq
extern dex_build_impname

section .rodata
s_x_hdr      db "XRefs to 0x", 0
s_x_kind_c   db "call", 0
s_x_kind_j   db "jmp", 0
s_x_kind_b   db "branch", 0
s_x_kind_d   db "data", 0
s_x_mne_j    db "jmp", 0
s_x_sp       db "  0x", 0
s_x_mid      db " ", 0
s_x_imp_o    db " [", 0
s_x_imp_c    db "]", 0
s_x_tot      db "total: ", 0
s_x_trunc    db " (truncated)", 0
s_x_nl       db 13, 10, 0
s_j_open     db '{"tool":"dexter","version":"', 0
s_j_dot      db ".", 0
s_j_query    db '","query":"0x', 0
s_j_total    db '","total":', 0
s_j_trunc    db ',"truncated":', 0
s_j_refs     db ',"refs":[', 0
s_j_ropen    db '{"va":"0x', 0
s_j_rkind    db '","kind":"', 0
s_j_rdet     db '","detail":"', 0
s_j_rclose   db '"}', 0
s_j_comma    db ",", 0
s_j_close    db "]}", 0

section .bss
align 16
g_xinsn:  resb 160                ; scratch do decoder (SIZEOF_INSN)
g_xrefs:  resb 4096               ; 256 x {va qword, kind dword, pad dword}
g_ximp:   resb 512                ; tmp p/ nome __imp_

section .text

;-----------------------------------------------------------------------------
; dex_xrefs - rcx=cfg, rdx=img, r8=queryVA -> eax=0.
; Frame: 8 pushes + sub 96 (slots ate [rbp-152]).
; Slots: -72 base, -80 total, -88 truncated, -96 sec, -104 vaddr,
;  -112 raw, -120 va_base, -128 k/stored, -136 va/len, -144 len/kind,
;  -152 entry (imp).
;-----------------------------------------------------------------------------
dex_xrefs:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15                     ; 8 pushes (64B) + sub 96 = 160 ? 8
    sub rsp, 96
    mov rbx, rcx                 ; cfg
    mov r15, rdx                 ; img
    mov rdi, r8                  ; query
    mov rsi, [r15+PeImage.image_base]
    mov [rbp-72], rsi            ; base
    mov dword [rbp-80], 0          ; total (slot: r10d morre nos calls!)
    mov dword [rbp-84], 0          ; stored (slot: r11d morre nos calls!)
    mov dword [rbp-88], 0        ; truncated
    mov r12d, [r15+PeImage.num_sections]
    mov r13, [r15+PeImage.sections_ptr]
    xor r14d, r14d               ; si
.x_sec:
    cmp r14d, r12d
    jae .x_print
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    lea rax, [r13+rax]           ; sec
    mov [rbp-96], rax
    mov eax, [rax+PeSection.characterist]
    test eax, IMAGE_SCN_CNT_CODE
    jnz .x_csec
    test eax, IMAGE_SCN_MEM_EXECUTE
    jz .x_next_sec
.x_csec:
    mov rax, [rbp-96]
    mov ecx, [rax+PeSection.vaddr]
    mov [rbp-104], ecx
    mov edx, [rax+PeSection.raw_size]
    mov [rbp-112], edx
    mov rax, [rbp-72]
    add rax, rcx
    mov [rbp-120], rax           ; va_base
    xor ecx, ecx                 ; k
.x_loop:
    cmp ecx, [rbp-112]
    jae .x_next_sec
    mov [rbp-128], ecx           ; spill k
    mov rax, [rbp-120]
    add rax, rcx                 ; va
    mov [rbp-136], rax           ; spill va
    mov rcx, r15
    mov rdx, rax
    lea r8, [rel g_xinsn]
    sub rsp, 32
    call dex_disasm_one
    add rsp, 32
    test eax, eax
    jz .x_adv1                   ; sem bytes? avanca 1 (nunca trava)
    mov [rbp-144], eax           ; len
    lea rax, [rel g_xinsn]
    movzx edx, byte [rax+Insn.is_call]
    test edx, edx
    jnz .x_is_call
    movzx edx, byte [rax+Insn.is_branch]
    test edx, edx
    jz .x_is_data
    ; branch: kind jmp se mne exato, senao branch (r8d NAO atravessa calls!)
    mov rcx, [rax+Insn.mne]
    test rcx, rcx
    jz .x_kind_branch
    lea rdx, [rel s_x_mne_j]
    sub rsp, 32
    call dex_streq               ; rcx=mne, rdx="jmp" (rax=1/0; r8 morre!)
    add rsp, 32
    test eax, eax
    jz .x_kind_branch
    ; kind=jmp: resolve alvo
    lea rax, [rel g_xinsn]       ; rax morreu no streq: recarrega!
    mov rdx, [rax+Insn.target_va]
    test rdx, rdx
    jnz .x_chkq_jmp
    sub rsp, 32
    call .xrip_t                 ; rax=insn, rdx=t|0 (leaf, sem calls)
    add rsp, 32
    test rdx, rdx
    jz .x_adv
    cmp rdx, rdi
    jne .x_adv
    mov edx, 1
    jmp .x_record
.x_chkq_jmp:
    cmp rdx, rdi
    jne .x_adv
    mov edx, 1
    jmp .x_record
.x_kind_branch:
    ; kind=branch: resolve alvo
    lea rax, [rel g_xinsn]
    mov rdx, [rax+Insn.target_va]
    test rdx, rdx
    jnz .x_chkq_br
    sub rsp, 32
    call .xrip_t
    add rsp, 32
    test rdx, rdx
    jz .x_adv
    cmp rdx, rdi
    jne .x_adv
    mov edx, 2
    jmp .x_record
.x_chkq_br:
    cmp rdx, rdi
    jne .x_adv
    mov edx, 2
    jmp .x_record
.x_is_call:
    ; kind=call: resolve alvo
    mov rdx, [rax+Insn.target_va]
    test rdx, rdx
    jnz .x_chkq_call
    sub rsp, 32
    call .xrip_t                 ; rax ainda e g_xinsn (sem calls no meio)
    add rsp, 32
    test rdx, rdx
    jz .x_adv
    cmp rdx, rdi
    jne .x_adv
    mov edx, 0
    jmp .x_record
.x_chkq_call:
    cmp rdx, rdi
    jne .x_adv
    mov edx, 0
    jmp .x_record
.x_is_data:
    ; nem call nem branch: so RIP-dado conta
    sub rsp, 32
    call .xrip_t
    add rsp, 32
    test rdx, rdx
    jz .x_adv
    cmp rdx, rdi
    jne .x_adv
    mov edx, 3                   ; data
.x_record:
    inc dword [rbp-80]           ; total
    cmp dword [rbp-84], 256
    jae .x_trunconly
    mov eax, [rbp-84]
    shl eax, 4                   ; idx*16
    lea rcx, [rel g_xrefs]
    add rax, rcx
    mov rcx, [rbp-136]
    mov [rax], rcx               ; va
    mov [rax+8], edx             ; kind
    inc dword [rbp-84]
    jmp .x_adv
.x_trunconly:
    mov dword [rbp-88], 1
    jmp .x_adv
.x_adv:
    mov eax, [rbp-144]
    mov ecx, [rbp-128]
    add ecx, eax
    jmp .x_loop
.x_adv1:
    mov ecx, [rbp-128]
    inc ecx
    jmp .x_loop
.x_next_sec:
    inc r14d
    jmp .x_sec
;-----------------------------------------------------------------------------
; Impressao (texto ou JSON por DF_JSON). total=[rbp-80], stored?[rbp-128].
;-----------------------------------------------------------------------------
.x_print:
    mov eax, [rbp-84]
    mov [rbp-128], eax
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .x_text
    jmp .x_json
.x_text:
    lea rcx, [rel s_x_hdr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, rdi
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_x_nl]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor r14d, r14d
.xt_l:
    cmp r14d, [rbp-128]
    jae .xt_tot
    mov eax, r14d
    shl eax, 4
    lea rcx, [rel g_xrefs]
    add rax, rcx
    mov rcx, [rax]
    mov [rbp-136], rcx
    mov edx, [rax+8]
    mov [rbp-144], edx
    lea rcx, [rel s_x_sp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-136]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_x_mid]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov edx, [rbp-144]
    cmp edx, 0
    je .xt_kc
    cmp edx, 1
    je .xt_kj
    cmp edx, 3
    je .xt_kd
    lea rcx, [rel s_x_kind_b]
    jmp .xt_kgo
.xt_kc:
    lea rcx, [rel s_x_kind_c]
    jmp .xt_kgo
.xt_kj:
    lea rcx, [rel s_x_kind_j]
    jmp .xt_kgo
.xt_kd:
    lea rcx, [rel s_x_kind_d]
.xt_kgo:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    ; detail: nome __imp_ se kind call/jmp e query e slot IAT
    mov edx, [rbp-144]
    cmp edx, 1
    ja .xt_nl
    mov rax, rdi                 ; query
    mov rdx, r15                 ; img
    sub rsp, 32
    call .ximp_find              ; rdx=entry|0 (leaf local, com shadow)
    add rsp, 32
    test rdx, rdx
    jz .xt_nl
    mov [rbp-152], rdx           ; spill entry
    mov r8, [rdx+ImportEntry.dll_name]
    mov r9, [rdx+ImportEntry.func_name]
    movzx edx, byte [rdx+ImportEntry.is_ordinal]
    mov rax, [rbp-152]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_ximp]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .xt_nl
    lea rcx, [rel s_x_imp_o]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel g_ximp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_x_imp_c]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.xt_nl:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    inc r14d
    jmp .xt_l
.xt_tot:
    lea rcx, [rel s_x_tot]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-80]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    cmp dword [rbp-88], 0
    je .xt_nl2
    lea rcx, [rel s_x_trunc]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.xt_nl2:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .x_done
;-----------------------------------------------------------------------------
; JSON.
;-----------------------------------------------------------------------------
.x_json:
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
    lea rcx, [rel s_j_query]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, rdi
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_total]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-80]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_trunc]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-88]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_refs]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor r14d, r14d
.xj_l:
    cmp r14d, [rbp-128]
    jae .xj_close
    test r14d, r14d
    jz .xj_first
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.xj_first:
    mov eax, r14d
    shl eax, 4
    lea rcx, [rel g_xrefs]
    add rax, rcx
    mov rcx, [rax]
    mov [rbp-136], rcx
    mov edx, [rax+8]
    mov [rbp-144], edx
    lea rcx, [rel s_j_ropen]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-136]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_rkind]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov edx, [rbp-144]
    cmp edx, 0
    je .xj_kc
    cmp edx, 1
    je .xj_kj
    cmp edx, 3
    je .xj_kd
    lea rcx, [rel s_x_kind_b]
    jmp .xj_kgo
.xj_kc:
    lea rcx, [rel s_x_kind_c]
    jmp .xj_kgo
.xj_kj:
    lea rcx, [rel s_x_kind_j]
    jmp .xj_kgo
.xj_kd:
    lea rcx, [rel s_x_kind_d]
.xj_kgo:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_rdet]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov edx, [rbp-144]
    cmp edx, 1
    ja .xj_nodet
    mov rax, rdi
    mov rdx, r15
    sub rsp, 32
    call .ximp_find
    add rsp, 32
    test rdx, rdx
    jz .xj_nodet
    mov [rbp-152], rdx
    mov r8, [rdx+ImportEntry.dll_name]
    mov r9, [rdx+ImportEntry.func_name]
    movzx edx, byte [rdx+ImportEntry.is_ordinal]
    mov rax, [rbp-152]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_ximp]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .xj_nodet
    lea rcx, [rel g_ximp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.xj_nodet:
    lea rcx, [rel s_j_rclose]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    inc r14d
    jmp .xj_l
.xj_close:
    lea rcx, [rel s_j_close]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.x_done:
    xor eax, eax
    add rsp, 96
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
; .xrip_t - rax=g_xinsn -> rdx=alvo RIP-MEM (va+len+disp) ou 0.
; Leaf (sem calls, sem stack). Clobber: rax?, rcx, rdx. Preserva o resto.
; (rax preservado na pratica: so lido.)
;-----------------------------------------------------------------------------
.xrip_t:
    cmp byte [rax+Insn.has_modrm], 0
    je .xrt_no
    cmp byte [rax+Insn.disp_size], 4
    jne .xrt_no
    cmp byte [rax+Insn.legacy67], 0
    jne .xrt_no
    movzx ecx, byte [rax+Insn.modrm]
    and ecx, 0xC7
    cmp ecx, 0x05
    jne .xrt_no
    cmp byte [rax+Insn.has_sib], 0
    jne .xrt_no
    mov rdx, [rbp-136]           ; va
    mov ecx, [rbp-144]           ; len
    add rdx, rcx
    add rdx, [rax+Insn.disp]
    ret
.xrt_no:
    xor edx, edx
    ret
;-----------------------------------------------------------------------------
; .ximp_find - rax=VA, rdx=img -> rdx=ImportEntry* ou 0.
; Leaf (sem calls). Preserva rbx/rdi/rsi/r12-r15; clobber rax,rcx,rdx,r8.
;-----------------------------------------------------------------------------
.ximp_find:
    mov r8, rdx                  ; img
    mov rcx, [r8+PeImage.image_base]
    cmp rax, rcx
    jb .xif_miss
    sub rax, rcx                 ; rva
    mov rdx, rax
    shr rdx, 32
    jnz .xif_miss
    mov edx, eax
    mov rcx, [r8+PeImage.imports_ptr]
    test rcx, rcx
    jz .xif_miss
    mov r8d, [r8+PeImage.imports_count]
    test r8d, r8d
    jz .xif_miss
    mov rax, rcx
    xor ecx, ecx
.xif_l:
    cmp ecx, r8d
    jae .xif_miss
    cmp dword [rax+ImportEntry.iat_rva], edx
    je .xif_hit
    add rax, SIZEOF_IMPORT_ENTRY
    inc ecx
    jmp .xif_l
.xif_hit:
    mov rdx, rax
    ret
.xif_miss:
    xor edx, edx
    ret

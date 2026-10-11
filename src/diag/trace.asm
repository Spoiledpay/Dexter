;=============================================================================
; Dexter/src/diag/trace.asm
; dex_trace a?? cadeia de calls a partir de uma VA (first-call DFS com
; limite de profundidade honesto).
;
; O quA?: do endereA?o inicial, varre linearmente atA? a PRIMEIRA call com
;  alvo resolvido (REL ou slot RIP-rel); desce no alvo se for cA?digo
;  ainda nA?o visitado; repete atA? depth (default 8, -depth 1..64).
; Por quA?: responder "para onde esta funA?A?o chama, em cadeia" sem gerar
;  .asm (R-7.2, marco.md). LimitaA?A?es honestas e documentadas: sA? segue
;  CALLS (jmp-out encerra o nA?vel como leaf); sA? a primeira call de cada
;  nA?vel; calls indiretas sem alvo sA?o puladas; nA?o A? CFG completo.
; Contrato:
;   Args: rcx = DexConfig* (DF_JSON; depth/has_depth), rdx = PeImage*,
;         r8 = start VA.
;   Ret:  eax = 0 sempre (not-found/leaf sA?o respostas honestas).
;   end a?? leaf | import | cycle | depth | outside (sempre impresso) +
;   truncated 0/1.
;   Clobber: rax, rcx, rdx, r8-r11.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\run_tests.bat seA?A?o [17].
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"
%include "pe.inc"

global dex_trace

extern dex_disasm_one
extern dex_console_print_cstr
extern dex_console_print_u64hex
extern dex_console_print_u64dec
extern dex_console_newline
extern dex_streq
extern dex_build_impname

section .rodata
s_t_hdr      db "Trace from 0x", 0
s_t_depth    db " (depth ", 0
s_t_depth_e  db "):", 0
s_t_nf       db ": not found", 0
s_t_arrow    db "  0x", 0
s_t_call     db " --call--> 0x", 0
s_t_jmp      db " --jmp--> 0x", 0
s_t_imp_o    db " [", 0
s_t_imp_c    db "]", 0
s_t_end      db "end: ", 0
s_t_trunc    db "truncated: ", 0
s_t_yes      db "yes", 0
s_t_no       db "no", 0
s_t_e_leaf   db "leaf", 0
s_t_e_imp    db "import", 0
s_t_e_cyc    db "cycle", 0
s_t_e_dep    db "depth", 0
s_t_e_out    db "outside", 0
s_t_nl       db 13, 10, 0
s_t_mne_j    db "jmp", 0
s_j_open     db '{"tool":"dexter","version":"', 0
s_j_dot      db ".", 0
s_j_from     db '","from":"0x', 0
s_j_depth    db '","depth":', 0
s_j_trunc    db ',"truncated":', 0
s_j_end      db ',"end":"', 0
s_j_end_e    db '",', 0
s_j_chain    db '"chain":[', 0
s_j_copen    db '{"from":"0x', 0
s_j_cto      db '","to":"0x', 0
s_j_ckind    db '","kind":"', 0
s_t_callnm   db "call", 0
s_t_jmpnm    db "jmp", 0
s_j_cimp     db '","imp":"', 0
s_j_cclose   db '"}', 0
s_j_comma    db ",", 0
s_j_close    db "]}", 0
s_j_nf       db '{"tool":"dexter","version":"', 0

section .bss
align 16
g_tinsn:  resb 160                ; scratch do decoder
g_tvis:   resb 512                ; 64 VAs visitadas
g_timp:   resb 512                ; tmp __imp_

section .text

;-----------------------------------------------------------------------------
; dex_trace a?? rcx=cfg, rdx=img, r8=startVA -> eax=0.
; Frame: 8 pushes + sub 64. Slots: -72 cur, -80 callsite, -88 target,
;  -96 endcode(0=leaf,1=import,2=cycle,3=depth,4=outside), -104 trunc,
;  -112 k, -120 len, -128 seclimit.
;-----------------------------------------------------------------------------
dex_trace:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 80
    mov rbx, rcx                 ; cfg
    mov r15, rdx                 ; img
    mov rdi, r8                  ; start
    mov rsi, [r15+PeImage.image_base]
    ; depth (default 8)
    mov r12d, 8
    cmp byte [rbx+DexConfig.has_depth], 0
    je .t_depth_ok
    mov r12, [rbx+DexConfig.depth]
.t_depth_ok:
    mov [rbp-72], rdi            ; cur
    xor r14d, r14d               ; nvis
    mov dword [rbp-104], 0       ; trunc
    mov dword [rbp-136], 0       ; nchain (slot: r11d morre nos calls!)
    xor r13d, r13d               ; level
.t_level:
    cmp r13d, r12d
    jae .t_end_depth
    ; valida cur em cA?digo + acha seclimit (rva)
    mov rax, [rbp-72]
    mov rdx, r15
    sub rsp, 32
    call .t_seclimit             ; eax=seclimit_rva|0, zf? (eax=0 => fora)
    add rsp, 32
    test eax, eax
    jz .t_end_outside
    mov [rbp-128], eax
    mov rax, [rbp-72]
    sub rax, rsi                 ; cur_rva
    mov [rbp-112], eax           ; k = cur_rva (relativo? NA?O: sweep usa VA;
                                 ; k como offset da VA inicial: zerar)
    mov dword [rbp-112], 0       ; k=0 (slot: r10d morre nos calls!)
.t_sweep:
    cmp dword [rbp-112], 65536
    jae .t_end_leaf
    mov rax, [rbp-72]
    mov ecx, [rbp-112]
    add rax, rcx                 ; va = cur + k
    mov rdx, rax
    sub rdx, rsi                 ; rva
    cmp edx, [rbp-128]
    jae .t_end_leaf
    mov [rbp-80], rax            ; callsite?
    mov rcx, r15
    mov rdx, rax
    lea r8, [rel g_tinsn]
    sub rsp, 32
    call dex_disasm_one
    add rsp, 32
    test eax, eax
    jz .t_end_leaf
    mov [rbp-120], eax           ; len
    lea rax, [rel g_tinsn]
    cmp byte [rax+Insn.is_ret], 0
    jne .t_end_leaf
    cmp byte [rax+Insn.is_call], 0
    jne .t_found_call
    ; jmp incondicional para o sweep; jcc/outros seguem
    cmp byte [rax+Insn.is_branch], 0
    je .t_sweep_adv
    mov rcx, [rax+Insn.mne]
    test rcx, rcx
    jz .t_sweep_adv
    lea rdx, [rel s_t_mne_j]
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .t_sweep_adv
    ; jmp-out: se o alvo e slot IAT, registra aresta e termina em import;
    ; senao leaf sem aresta (documentado: trace segue CALLS).
    lea rax, [rel g_tinsn]       ; rax morreu no streq: recarrega!
    mov rdx, [rax+Insn.target_va]
    test rdx, rdx
    jnz .t_jmp_chk
    sub rsp, 32
    call .t_rip_tgt
    add rsp, 32
    test rdx, rdx
    jz .t_end_leaf
.t_jmp_chk:
    mov [rbp-88], rdx            ; target ([rbp-80] = callsite atual)
    mov rax, rdx
    mov rdx, r15
    sub rsp, 32
    call .timp_find
    add rsp, 32
    test rdx, rdx
    jz .t_end_leaf
    mov dword [rbp-148], 1       ; kind=jmp (thunk p/ import)
    sub rsp, 32
    call .t_push_edge
    add rsp, 32
    mov dword [rbp-96], 1        ; end=import
    jmp .t_print              ; jmp-out: nA?vel termina sem call
.t_found_call:
    mov rdx, [rax+Insn.target_va]
    test rdx, rdx
    jnz .t_gototgt
    sub rsp, 32
    call .t_rip_tgt              ; rax=insn ainda? SIM (sem calls no meio)
    add rsp, 32
    test rdx, rdx
    jz .t_sweep_adv              ; indireta: pula, segue varrendo
.t_gototgt:
    mov [rbp-88], rdx            ; target
    jmp .t_follow
.t_sweep_adv:
    mov eax, [rbp-120]
    add [rbp-112], eax           ; k += len
    jmp .t_sweep
.t_follow:
    jmp .t_follow_go
.t_follow_go:
    mov rdx, [rbp-88]
    mov rax, rdx
    mov rdx, r15
    sub rsp, 32
    call .timp_find              ; rdx=entry|0
    add rsp, 32
    test rdx, rdx
    jz .t_chk_code
    mov dword [rbp-148], 0       ; kind=call
    sub rsp, 32
    call .t_push_edge
    add rsp, 32
    mov dword [rbp-96], 1        ; end=import
    jmp .t_print
.t_chk_code:
    mov rax, [rbp-88]
    mov rdx, r15
    sub rsp, 32
    call .t_seclimit             ; eax<>0 <=> alvo em codigo
    add rsp, 32
    test eax, eax
    jz .t_is_outside
    mov rax, [rbp-88]
    xor ecx, ecx
.t_cyc:
    cmp ecx, r14d
    jae .t_no_cyc
    lea rdx, [rel g_tvis]
    cmp [rdx+rcx*8], rax
    je .t_is_cycle
    inc ecx
    jmp .t_cyc
.t_no_cyc:
    lea rdx, [rel g_tvis]
    mov [rdx+r14*8], rax
    inc r14d
    mov rcx, [rbp-88]
    mov [rbp-72], rcx            ; cur = target: desce
    mov dword [rbp-148], 0       ; kind=call
    sub rsp, 32
    call .t_push_edge
    add rsp, 32
    inc r13d                     ; level++
    jmp .t_level
.t_is_outside:
    mov dword [rbp-148], 0       ; kind=call
    sub rsp, 32
    call .t_push_edge
    add rsp, 32
    mov dword [rbp-96], 4        ; end=outside
    jmp .t_print
.t_is_cycle:
    mov dword [rbp-148], 0       ; kind=call
    sub rsp, 32
    call .t_push_edge
    add rsp, 32
    mov dword [rbp-96], 2        ; end=cycle
    mov dword [rbp-104], 1       ; truncated
    jmp .t_print
.t_end_depth:
    mov dword [rbp-96], 3        ; end=depth
    mov dword [rbp-104], 1
    jmp .t_print
.t_end_leaf:
    mov dword [rbp-96], 0        ; end=leaf
    jmp .t_print
.t_end_outside:
    mov dword [rbp-96], 4        ; start fora de codigo
    jmp .t_print
;-----------------------------------------------------------------------------
; .t_push_edge - guarda ([rbp-80] from, [rbp-88] to) em g_tchain[nchain++].
; Com shadow pelo chamador. Clobber: rax, rcx. Preserva o resto.
; (nchain <= 64 sempre: 1 aresta por nivel, niveis <= depth <= 64;
;  nchain vive em [rbp-136]: r11d morre nos calls!)
;-----------------------------------------------------------------------------
.t_push_edge:
    mov ecx, [rbp-136]
    mov eax, ecx
    shl ecx, 4                   ; idx*16
    shl eax, 3                   ; idx*8
    add ecx, eax                 ; idx*24
    lea rax, [rel g_tchain]
    add rax, rcx
    mov rcx, [rbp-80]
    mov [rax], rcx
    mov rcx, [rbp-88]
    mov [rax+8], rcx
    mov ecx, [rbp-148]
    mov [rax+16], ecx
    inc dword [rbp-136]
    ret
.t_print:
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .t_text
    jmp .t_json
;-----------------------------------------------------------------------------
; Texto.
;-----------------------------------------------------------------------------
.t_text:
    lea rcx, [rel s_t_hdr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, rdi
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_t_depth]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, r12
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_t_depth_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    xor r14d, r14d               ; i (reuso: nvis nA?o mais preciso)
.tt_l:
    cmp r14d, [rbp-136]
    jae .tt_end
    mov eax, r14d
    mov ecx, r14d
    shl eax, 4                   ; i*16
    shl ecx, 3                   ; i*8
    add eax, ecx                 ; i*24
    lea rcx, [rel g_tchain]
    add rax, rcx
    mov rcx, [rax]
    mov [rbp-80], rcx            ; from (reuso de slot)
    mov rcx, [rax+8]
    mov [rbp-88], rcx            ; to
    mov ecx, [rax+16]
    mov [rbp-148], ecx           ; kind (reuso: so lido abaixo)
    lea rcx, [rel s_t_arrow]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-80]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    cmp dword [rbp-148], 1
    je .tt_jmp
    lea rcx, [rel s_t_call]
    jmp .tt_cgo
.tt_jmp:
    lea rcx, [rel s_t_jmp]
.tt_cgo:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-88]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    mov rax, [rbp-88]
    mov rdx, r15
    sub rsp, 32
    call .timp_find
    add rsp, 32
    test rdx, rdx
    jz .tt_nl
    mov [rbp-144], rdx           ; spill entry ([rbp-96] e o endcode!)
    mov r8, [rdx+ImportEntry.dll_name]
    mov r9, [rdx+ImportEntry.func_name]
    movzx edx, byte [rdx+ImportEntry.is_ordinal]
    mov rax, [rbp-144]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_timp]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .tt_nl
    lea rcx, [rel s_t_imp_o]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel g_timp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_t_imp_c]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.tt_nl:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    inc r14d
    jmp .tt_l
.tt_end:
    lea rcx, [rel s_t_end]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov eax, [rbp-96]
    cmp eax, 1
    je .tt_e_imp
    cmp eax, 2
    je .tt_e_cyc
    cmp eax, 3
    je .tt_e_dep
    cmp eax, 4
    je .tt_e_out
    lea rcx, [rel s_t_e_leaf]
    jmp .tt_ego
.tt_e_imp:
    lea rcx, [rel s_t_e_imp]
    jmp .tt_ego
.tt_e_cyc:
    lea rcx, [rel s_t_e_cyc]
    jmp .tt_ego
.tt_e_dep:
    lea rcx, [rel s_t_e_dep]
    jmp .tt_ego
.tt_e_out:
    lea rcx, [rel s_t_e_out]
.tt_ego:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_t_trunc]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    cmp dword [rbp-104], 0
    je .tt_tno
    lea rcx, [rel s_t_yes]
    jmp .tt_tgo
.tt_tno:
    lea rcx, [rel s_t_no]
.tt_tgo:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .t_done
;-----------------------------------------------------------------------------
; JSON.
;-----------------------------------------------------------------------------
.t_json:
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
    lea rcx, [rel s_j_from]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, rdi
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_depth]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, r12
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_trunc]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-104]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_end]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov eax, [rbp-96]
    cmp eax, 1
    je .tj_e_imp
    cmp eax, 2
    je .tj_e_cyc
    cmp eax, 3
    je .tj_e_dep
    cmp eax, 4
    je .tj_e_out
    lea rcx, [rel s_t_e_leaf]
    jmp .tj_ego
.tj_e_imp:
    lea rcx, [rel s_t_e_imp]
    jmp .tj_ego
.tj_e_cyc:
    lea rcx, [rel s_t_e_cyc]
    jmp .tj_ego
.tj_e_dep:
    lea rcx, [rel s_t_e_dep]
    jmp .tj_ego
.tj_e_out:
    lea rcx, [rel s_t_e_out]
.tj_ego:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_end_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_chain]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor r14d, r14d
.tj_l:
    cmp r14d, [rbp-136]
    jae .tj_close
    test r14d, r14d
    jz .tj_first
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.tj_first:
    mov eax, r14d
    mov ecx, r14d
    shl eax, 4                   ; i*16
    shl ecx, 3                   ; i*8
    add eax, ecx                 ; i*24
    lea rcx, [rel g_tchain]
    add rax, rcx
    mov rcx, [rax]
    mov [rbp-80], rcx
    mov rcx, [rax+8]
    mov [rbp-88], rcx
    mov ecx, [rax+16]
    mov [rbp-148], ecx           ; kind
    lea rcx, [rel s_j_copen]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-80]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_cto]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-88]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_ckind]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    cmp dword [rbp-148], 1
    je .tj_kjmp
    lea rcx, [rel s_t_callnm]
    jmp .tj_kgo
.tj_kjmp:
    lea rcx, [rel s_t_jmpnm]
.tj_kgo:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_cimp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rax, [rbp-88]
    mov rdx, r15
    sub rsp, 32
    call .timp_find
    add rsp, 32
    test rdx, rdx
    jz .tj_cclose
    mov [rbp-144], rdx           ; spill entry ([rbp-96] e o endcode!)
    mov r8, [rdx+ImportEntry.dll_name]
    mov r9, [rdx+ImportEntry.func_name]
    movzx edx, byte [rdx+ImportEntry.is_ordinal]
    mov rax, [rbp-144]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_timp]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .tj_cclose
    lea rcx, [rel g_timp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.tj_cclose:
    lea rcx, [rel s_j_cclose]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    inc r14d
    jmp .tj_l
.tj_close:
    lea rcx, [rel s_j_close]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.t_done:
    xor eax, eax
    add rsp, 80
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
; .t_seclimit a?? rax=VA, rdx=img -> eax=seclimit_rva ou 0 (fora de cA?digo).
; Com shadow pelo chamador. Clobber: rax,rcx,rdx,r8-r11.
; Preserva: rbx/rdi/rsi/r12-r15 (r13? usa r10/r11 locais).
;-----------------------------------------------------------------------------
.t_seclimit:
    push rbx                     ; spill sec (eax morre no teste abaixo!)
    mov r8, rdx
    mov rcx, [r8+PeImage.image_base]
    cmp rax, rcx
    jb .tsl_no
    sub rax, rcx
    mov rdx, rax
    shr rdx, 32
    jnz .tsl_no
    mov edx, eax
    mov ecx, [r8+PeImage.num_sections]
    mov r8, [r8+PeImage.sections_ptr]
    test ecx, ecx
    jz .tsl_no
    test r8, r8
    jz .tsl_no
.tsl_l:
    test ecx, ecx
    jz .tsl_no
    dec ecx
    mov eax, ecx
    imul eax, SIZEOF_PE_SECTION
    add rax, r8
    cmp edx, [rax+PeSection.vaddr]
    jb .tsl_l
    mov r10d, [rax+PeSection.vsize]
    mov r11d, [rax+PeSection.raw_size]
    cmp r10d, r11d
    jae .tsl_span
    mov r10d, r11d
.tsl_span:
    mov r11d, edx
    sub r11d, [rax+PeSection.vaddr]
    cmp r11d, r10d
    jae .tsl_l
    mov rbx, rax                 ; spill sec (eax morre no teste!)
    mov eax, [rax+PeSection.characterist]
    test eax, IMAGE_SCN_CNT_CODE
    jnz .tsl_yes
    test eax, IMAGE_SCN_MEM_EXECUTE
    jz .tsl_l
.tsl_yes:
    mov eax, [rbx+PeSection.vaddr]
    add eax, r10d
    pop rbx
    ret
.tsl_no:
    xor eax, eax
    pop rbx
    ret
;-----------------------------------------------------------------------------
; .t_rip_tgt a?? rax=g_tinsn -> rdx=slotVA ou 0. Leaf. Clobber: rax?,rcx,rdx.
;-----------------------------------------------------------------------------
.t_rip_tgt:
    cmp byte [rax+Insn.has_modrm], 0
    je .trt_no
    cmp byte [rax+Insn.disp_size], 4
    jne .trt_no
    cmp byte [rax+Insn.legacy67], 0
    jne .trt_no
    movzx ecx, byte [rax+Insn.modrm]
    and ecx, 0xC7
    cmp ecx, 0x05
    jne .trt_no
    cmp byte [rax+Insn.has_sib], 0
    jne .trt_no
    mov rdx, [rax+Insn.address]
    mov ecx, [rax+Insn.length]
    add rdx, rcx
    add rdx, [rax+Insn.disp]
    ret
.trt_no:
    xor edx, edx
    ret
;-----------------------------------------------------------------------------
; .timp_find a?? rax=VA, rdx=img -> rdx=entry|0. Leaf. Preserva non-volA?teis.
;-----------------------------------------------------------------------------
.timp_find:
    mov r8, rdx
    mov rcx, [r8+PeImage.image_base]
    cmp rax, rcx
    jb .tif_miss
    sub rax, rcx
    mov rdx, rax
    shr rdx, 32
    jnz .tif_miss
    mov edx, eax
    mov rcx, [r8+PeImage.imports_ptr]
    test rcx, rcx
    jz .tif_miss
    mov r8d, [r8+PeImage.imports_count]
    test r8d, r8d
    jz .tif_miss
    mov rax, rcx
    xor ecx, ecx
.tif_l:
    cmp ecx, r8d
    jae .tif_miss
    cmp dword [rax+ImportEntry.iat_rva], edx
    je .tif_hit
    add rax, SIZEOF_IMPORT_ENTRY
    inc ecx
    jmp .tif_l
.tif_hit:
    mov rdx, rax
    ret
.tif_miss:
    xor edx, edx
    ret

section .bss
align 16
g_tchain: resb 1536               ; 64 x {from qword, to qword, kind dword}

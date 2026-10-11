;=============================================================================
; Dexter/src/diag/func.asm
; dex_func - dossie de funcao por VA de entrada (linear-sweep, sem
; descida recursiva): bounds, chamadas e saltos com alvos.
;
; O que: a partir da VA, decodifica em sequencia ate ret / jmp
;  incondicional / byte invalido / fim da secao / 64KB; coleta calls
;  (target REL ou slot RIP-rel + nome __imp_ se IAT) e jmps.
; Por que: responder "o que esta funcao faz/chama" sem gerar .asm
;  (R-7.2, marco.md). Limitacao honesta e documentada: varredura
;  LINEAR (fallthrough), sem CFG/descida recursiva; jcc nao divide.
; Contrato:
;   Args: rcx = DexConfig* (DF_JSON seleciona JSON), rdx = PeImage*
;         (validado), r8 = entry VA.
;   Ret:  eax = 0 sempre (not-found e resposta honesta).
;   Cap: 64 calls + 64 jmps; alem disso truncated (honesto).
;   Clobber: rax, rcx, rdx, r8-r11.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\run_tests.bat secao [17].
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"
%include "pe.inc"

global dex_func

extern dex_disasm_one
extern dex_console_print_cstr
extern dex_console_print_u64hex
extern dex_console_print_u64dec
extern dex_console_newline
extern dex_streq
extern dex_build_impname

section .rodata
s_f_hdr      db "Function 0x", 0
s_f_nf       db ": not found", 0
s_f_size     db "  size: ", 0
s_f_bytes    db " bytes, instrs: ", 0
s_f_calls    db "  calls: ", 0
s_f_jmps     db "  jmps: ", 0
s_f_ret      db "  returns: ", 0
s_f_yes      db "yes", 0
s_f_no       db "no", 0
s_f_call     db "    call 0x", 0
s_f_jmp      db "    jmp 0x", 0
s_f_br       db "    branch 0x", 0
s_f_imp_o    db " [", 0
s_f_imp_c    db "]", 0
s_f_mne_j    db "jmp", 0
s_f_tot      db "total: ", 0
s_f_trunc    db " (truncated)", 0
s_f_nl       db 13, 10, 0
s_j_open     db '{"tool":"dexter","version":"', 0
s_j_dot      db ".", 0
s_j_entry    db '","entry":"0x', 0
s_j_found    db '","found":', 0
s_j_size     db ',"size":', 0
s_j_instrs   db ',"instrs":', 0
s_j_calls    db ',"calls":[', 0
s_j_copen    db '{"va":"0x', 0
s_j_cimp     db '","imp":"', 0
s_j_cclose   db '"}', 0
s_j_calls_e  db "],", 0
s_j_jmps     db '"jmps":[', 0
s_j_jopen    db '{"va":"0x', 0
s_j_jkind    db '","kind":"', 0
s_j_jclose   db '"}', 0
s_j_jmps_e   db "],", 0
s_j_ret      db '"has_ret":', 0
s_j_trunc    db ',"truncated":', 0
s_j_nf       db '{"tool":"dexter","version":"', 0
s_j_comma    db ",", 0
s_j_close    db "}", 0
s_j_kind_j   db "jmp", 0
s_j_kind_b   db "branch", 0

section .bss
align 16
g_finsn:  resb 160                ; scratch do decoder
g_fcalls: resb 512                ; 64 x VA qword
g_fjmps:  resb 1024               ; 64 x {va qword, kind dword, pad dword}
g_fimp:   resb 512                ; tmp __imp_

section .text

;-----------------------------------------------------------------------------
; dex_func - rcx=cfg, rdx=img, r8=entryVA -> eax=0.
; Frame: 8 pushes + sub 96.
; Slots: -72 img, -80 entry, -88 secend, -96 k, -104 len, -112 size,
;  -120 instrs, -128 ncalls, -136 njmps, -144 has_ret, -152 trunc,
;  -160 va_tmp.
;-----------------------------------------------------------------------------
dex_func:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15                     ; 8 pushes (64B) + sub 112 = 176 ? 8
    sub rsp, 112                 ; slots ate [rbp-176]: k=[rbp-164], instrs=[rbp-172]
    mov rbx, rcx                 ; cfg
    mov r15, rdx                 ; img
    mov rdi, r8                  ; entry
    mov [rbp-80], rdi
    ; --- entry cai em secao de codigo? (espelha .cs_in_code) ---
    mov rax, [r15+PeImage.image_base]
    cmp rdi, rax
    jb .notfound
    sub rdi, rax                 ; trva
    mov rdx, rdi
    shr rdx, 32
    jnz .notfound
    mov [rbp-160], rdi           ; trva (slot)
    mov ecx, [r15+PeImage.num_sections]
    mov rsi, [r15+PeImage.sections_ptr]
    test ecx, ecx
    jz .notfound
    test rsi, rsi
    jz .notfound
    mov rdx, [rbp-160]
.find_sec:
    test ecx, ecx
    jz .notfound
    dec ecx
    mov eax, ecx
    imul eax, SIZEOF_PE_SECTION
    lea rax, [rsi+rax]
    cmp edx, [rax+PeSection.vaddr]
    jb .find_sec
    mov r10d, [rax+PeSection.vsize]
    mov r11d, [rax+PeSection.raw_size]
    cmp r10d, r11d
    jae .f_span
    mov r10d, r11d
.f_span:
    mov r11d, edx
    sub r11d, [rax+PeSection.vaddr]
    cmp r11d, r10d
    jae .find_sec
    mov [rbp-96], rax            ; spill sec (eax morre no teste abaixo!)
    mov eax, [rax+PeSection.characterist]
    test eax, IMAGE_SCN_CNT_CODE
    jnz .f_in_code
    test eax, IMAGE_SCN_MEM_EXECUTE
    jz .find_sec
.f_in_code:
    mov rax, [rbp-96]            ; restore sec (era characteristics!)
    ; secend = vaddr+span (rva, para o limite do sweep)
    mov [rbp-88], r10d
    mov eax, [rax+PeSection.vaddr]
    add eax, r10d
    mov [rbp-88], eax            ; secend_rva (reuso do slot)
    mov rdi, [rbp-80]            ; entry
    mov [rbp-72], r15            ; img (slot; r15 vive, mas documenta)
    mov dword [rbp-164], 0       ; k (slot: r10d morre nos calls!)
    mov dword [rbp-172], 0       ; instrs (slot: r11d morre nos calls!)
    mov dword [rbp-128], 0       ; ncalls
    mov dword [rbp-136], 0       ; njmps
    mov dword [rbp-144], 0       ; has_ret
    mov dword [rbp-152], 0       ; trunc
.f_loop:
    cmp dword [rbp-164], 65536
    jae .f_sweep_end
    mov rax, [rbp-80]
    mov ecx, [rbp-164]
    add rax, rcx                 ; va = entry + k
    mov rdx, rax
    sub rdx, [r15+PeImage.image_base] ; rva
    cmp edx, [rbp-88]            ; >= secend?
    jae .f_sweep_end
    mov [rbp-160], rax           ; va_tmp
    mov rcx, r15
    mov rdx, rax                 ; va
    lea r8, [rel g_finsn]
    sub rsp, 32
    call dex_disasm_one
    add rsp, 32
    test eax, eax
    jz .f_sweep_end              ; invalido: para (honesto, sem erro)
    mov [rbp-104], eax           ; len
    lea rax, [rel g_finsn]
    cmp byte [rax+Insn.is_ret], 0
    jne .f_got_ret
    ; call com alvo? (REL ou slot RIP)
    cmp byte [rax+Insn.is_call], 0
    je .f_notcall
    mov rdx, [rax+Insn.target_va]
    test rdx, rdx
    jnz .f_add_call
    sub rsp, 32
    call .f_rip_tgt              ; rdx=slot|0 (leaf local, com shadow)
    add rsp, 32
    test rdx, rdx
    jz .f_adv                    ; indireto sem alvo: segue
    jmp .f_add_call
.f_notcall:
    ; jmp incondicional (mne)? branching condicional continua.
    cmp byte [rax+Insn.is_branch], 0
    je .f_adv
    mov rcx, [rax+Insn.mne]
    test rcx, rcx
    jz .f_adv
    lea rdx, [rel s_f_mne_j]
    sub rsp, 32
    call dex_streq
    add rsp, 32
    test eax, eax
    jz .f_adv                    ; jcc: segue o fallthrough
    ; jmp: registra alvo (REL ou RIP) e PARA
    lea rax, [rel g_finsn]
    mov rdx, [rax+Insn.target_va]
    test rdx, rdx
    jnz .f_add_jmp
    sub rsp, 32
    call .f_rip_tgt
    add rsp, 32
    test rdx, rdx
    jz .f_sweep_end              ; jmp indireto: para sem alvo
    jmp .f_add_jmp_stop
.f_add_call:
    mov eax, [rbp-128]
    cmp eax, 64
    jae .f_call_trunc
    lea rcx, [rel g_fcalls]
    mov [rcx+rax*8], rdx
    inc dword [rbp-128]
    jmp .f_adv
.f_call_trunc:
    mov dword [rbp-152], 1
    jmp .f_adv
.f_add_jmp:
    mov eax, [rbp-136]
    cmp eax, 64
    jae .f_jmp_trunc
    lea rcx, [rel g_fjmps]
    shl eax, 4
    add rax, rcx
    mov [rax], rdx               ; va
    mov dword [rax+8], 0         ; kind jmp
    inc dword [rbp-136]
    jmp .f_sweep_end
.f_add_jmp_stop:
    mov eax, [rbp-136]
    cmp eax, 64
    jae .f_jmp_trunc
    lea rcx, [rel g_fjmps]
    shl eax, 4
    add rax, rcx
    mov [rax], rdx
    mov dword [rax+8], 0
    inc dword [rbp-136]
    jmp .f_sweep_end
.f_jmp_trunc:
    mov dword [rbp-152], 1
    jmp .f_sweep_end
.f_got_ret:
    mov dword [rbp-144], 1
    jmp .f_sweep_end
.f_adv:
    mov eax, [rbp-104]
    add [rbp-164], eax           ; k += len
    inc dword [rbp-172]          ; instrs++
    jmp .f_loop
.f_sweep_end:
    mov eax, [rbp-164]
    mov [rbp-112], eax           ; size
    mov eax, [rbp-172]
    mov [rbp-120], eax           ; instrs (+1? conta: .f_adv conta; saida por
                                 ; ret/jmp/end nao soma a ultima - aceitar
                                 ; (documentado: instrs = decodificadas no fluxo))
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .f_text
    jmp .f_json
;-----------------------------------------------------------------------------
; Texto.
;-----------------------------------------------------------------------------
.f_text:
    lea rcx, [rel s_f_hdr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-80]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_f_nl]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_f_size]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-112]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_f_bytes]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-120]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    lea rcx, [rel s_f_calls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-128]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    xor r14d, r14d
.ft_c:
    cmp r14d, [rbp-128]
    jae .ft_jh
    lea rax, [rel g_fcalls]
    mov rcx, [rax+r14*8]
    mov [rbp-160], rcx
    lea rcx, [rel s_f_call]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-160]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    mov rax, [rbp-160]
    mov rdx, r15
    sub rsp, 32
    call .fimp_find
    add rsp, 32
    test rdx, rdx
    jz .ft_c_nl
    mov [rbp-96], rdx            ; spill entry ([rbp-96] livre aqui? sweep
                                 ; acabou; slots -88..-160 reusaveis)
    mov r8, [rdx+ImportEntry.dll_name]
    mov r9, [rdx+ImportEntry.func_name]
    movzx edx, byte [rdx+ImportEntry.is_ordinal]
    mov rax, [rbp-96]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_fimp]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .ft_c_nl
    lea rcx, [rel s_f_imp_o]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel g_fimp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_f_imp_c]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.ft_c_nl:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    inc r14d
    jmp .ft_c
.ft_jh:
    lea rcx, [rel s_f_jmps]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-136]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    xor r14d, r14d
.ft_j:
    cmp r14d, [rbp-136]
    jae .ft_ret
    mov eax, r14d
    shl eax, 4
    lea rcx, [rel g_fjmps]
    add rax, rcx
    mov rcx, [rax]
    mov [rbp-160], rcx
    mov edx, [rax+8]
    cmp edx, 0
    je .ft_jmp
    lea rcx, [rel s_f_br]
    jmp .ft_jgo
.ft_jmp:
    lea rcx, [rel s_f_jmp]
.ft_jgo:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-160]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    mov rax, [rbp-160]
    mov rdx, r15
    sub rsp, 32
    call .fimp_find
    add rsp, 32
    test rdx, rdx
    jz .ft_j_nl
    mov [rbp-96], rdx
    mov r8, [rdx+ImportEntry.dll_name]
    mov r9, [rdx+ImportEntry.func_name]
    movzx edx, byte [rdx+ImportEntry.is_ordinal]
    mov rax, [rbp-96]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_fimp]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .ft_j_nl
    lea rcx, [rel s_f_imp_o]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel g_fimp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_f_imp_c]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.ft_j_nl:
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    inc r14d
    jmp .ft_j
.ft_ret:
    lea rcx, [rel s_f_ret]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    cmp dword [rbp-144], 0
    je .ft_no
    lea rcx, [rel s_f_yes]
    jmp .ft_yn
.ft_no:
    lea rcx, [rel s_f_no]
.ft_yn:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    cmp dword [rbp-152], 0
    je .f_done
    lea rcx, [rel s_f_tot]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_f_trunc]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .f_done
;-----------------------------------------------------------------------------
; JSON.
;-----------------------------------------------------------------------------
.f_json:
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
    lea rcx, [rel s_j_entry]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-80]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_found]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, 1
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_size]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-112]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_instrs]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-120]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_calls]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor r14d, r14d
.fj_c:
    cmp r14d, [rbp-128]
    jae .fj_calls_e
    test r14d, r14d
    jz .fj_c0
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.fj_c0:
    lea rax, [rel g_fcalls]
    mov rcx, [rax+r14*8]
    mov [rbp-160], rcx
    lea rcx, [rel s_j_copen]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-160]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_cimp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rax, [rbp-160]
    mov rdx, r15
    sub rsp, 32
    call .fimp_find
    add rsp, 32
    test rdx, rdx
    jz .fj_c_close
    mov [rbp-96], rdx
    mov r8, [rdx+ImportEntry.dll_name]
    mov r9, [rdx+ImportEntry.func_name]
    movzx edx, byte [rdx+ImportEntry.is_ordinal]
    mov rax, [rbp-96]
    movzx eax, word [rax+ImportEntry.ordinal]
    lea rcx, [rel g_fimp]
    sub rsp, 32
    call dex_build_impname
    add rsp, 32
    test eax, eax
    jnz .fj_c_close
    lea rcx, [rel g_fimp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.fj_c_close:
    lea rcx, [rel s_j_cclose]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    inc r14d
    jmp .fj_c
.fj_calls_e:
    lea rcx, [rel s_j_calls_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_jmps]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor r14d, r14d
.fj_j:
    cmp r14d, [rbp-136]
    jae .fj_jmps_e
    test r14d, r14d
    jz .fj_j0
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.fj_j0:
    mov eax, r14d
    shl eax, 4
    lea rcx, [rel g_fjmps]
    add rax, rcx
    mov rcx, [rax]
    mov [rbp-160], rcx
    mov edx, [rax+8]
    mov [rbp-96+4], edx          ; kind em slot livre ([rbp-96] qword reusado pos-sweep)
    lea rcx, [rel s_j_jopen]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-160]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_jkind]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    cmp dword [rbp-96+4], 0
    je .fj_jmp
    lea rcx, [rel s_j_kind_b]
    jmp .fj_jgo
.fj_jmp:
    lea rcx, [rel s_j_kind_j]
.fj_jgo:
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_cclose]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    inc r14d
    jmp .fj_j
.fj_jmps_e:
    lea rcx, [rel s_j_jmps_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_j_ret]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-144]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_trunc]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-152]
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
    jmp .f_done
.notfound:
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .nf_text
    lea rcx, [rel s_j_nf]
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
    lea rcx, [rel s_j_entry]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-80]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_found]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, 0
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
    jmp .f_done
.nf_text:
    lea rcx, [rel s_f_hdr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-80]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_f_nf]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.f_done:
    xor eax, eax
    add rsp, 112
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
; .f_rip_tgt - rax=g_finsn -> rdx=slotVA ou 0 (RIP-rel MEM sem SIB).
; Leaf. Clobber: rax?, rcx, rdx.
;-----------------------------------------------------------------------------
.f_rip_tgt:
    cmp byte [rax+Insn.has_modrm], 0
    je .frt_no
    cmp byte [rax+Insn.disp_size], 4
    jne .frt_no
    cmp byte [rax+Insn.legacy67], 0
    jne .frt_no
    movzx ecx, byte [rax+Insn.modrm]
    and ecx, 0xC7
    cmp ecx, 0x05
    jne .frt_no
    cmp byte [rax+Insn.has_sib], 0
    jne .frt_no
    mov rdx, [rax+Insn.address]
    mov ecx, [rax+Insn.length]
    add rdx, rcx
    add rdx, [rax+Insn.disp]
    ret
.frt_no:
    xor edx, edx
    ret
;-----------------------------------------------------------------------------
; .fimp_find - rax=VA, rdx=img -> rdx=ImportEntry* ou 0.
; Leaf. Preserva rbx/rdi/rsi/r12-r15; clobber rax,rcx,rdx,r8.
;-----------------------------------------------------------------------------
.fimp_find:
    mov r8, rdx
    mov rcx, [r8+PeImage.image_base]
    cmp rax, rcx
    jb .fif_miss
    sub rax, rcx
    mov rdx, rax
    shr rdx, 32
    jnz .fif_miss
    mov edx, eax
    mov rcx, [r8+PeImage.imports_ptr]
    test rcx, rcx
    jz .fif_miss
    mov r8d, [r8+PeImage.imports_count]
    test r8d, r8d
    jz .fif_miss
    mov rax, rcx
    xor ecx, ecx
.fif_l:
    cmp ecx, r8d
    jae .fif_miss
    cmp dword [rax+ImportEntry.iat_rva], edx
    je .fif_hit
    add rax, SIZEOF_IMPORT_ENTRY
    inc ecx
    jmp .fif_l
.fif_hit:
    mov rdx, rax
    ret
.fif_miss:
    xor edx, edx
    ret

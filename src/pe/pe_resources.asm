;=============================================================================
; Dexter/src/pe/pe_resources.asm
; dex_rsrc_list — inventário da árvore de recursos PE (3 níveis fixos:
; tipo → nome → idioma), sem heap, sem decodificação de payload.
;
; O quê: lê DataDirectory[2], valida TUDO contra limites (dir e arquivo)
;  e lista cada folha (identidades numéricas ou strings UTF-16 com
;  escape) em texto ou JSON. Inspirado no inspect_pe_resources do REA.
; Por quê: responder "que recursos este exe carrega" sem gerar .asm
;  (R-7.3, marco.md).
; Contrato:
;   Args: rcx = DexConfig* (DF_JSON seleciona JSON), rdx = PeImage*
;         (validado; opt_header + file_buffer/size íntegros).
;   Ret:  eax = 0 ok (inventário vazio incluso) | 3 diretório com size>0
;         mas rva 0, fora de limites, forma inválida, payload não-mapeado
;         ou dir_size > 4MB (mensagem em stderr; nunca crasha, nunca
;         trunca silencioso). Duplicatas de irmãos são LISTADAS (anomalia
;         visível), sem erro — desvio documentado do REA.
;   Sem heap; sem recursão (3 níveis fixos: ciclos impossíveis).
;   Clobber: rax, rcx, rdx, r8-r11.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\run_tests.bat seção [18] (gcc manifest, ld.lld
;  version, vazio hello, 2 corrompidos, inspect-only).
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"
%include "pe.inc"

global dex_rsrc_list

extern dex_rva_to_offset
extern dex_console_print_cstr
extern dex_console_print_err
extern dex_console_print_u64hex
extern dex_console_print_u64dec
extern dex_console_newline

section .rodata
s_r_hdr      db "Resources: ", 0
s_r_path1    db "  /", 0
s_r_sep      db "/", 0
s_r_size     db " size=0x", 0
s_r_rva      db " rva=0x", 0
s_r_off      db " off=0x", 0
s_r_q        db '"', 0
s_r_nl       db 13, 10, 0
s_r_err      db "dexter: corrupt resource directory", 13, 10, 0
s_j_open     db '{"tool":"dexter","version":"', 0
s_j_dot      db ".", 0
s_j_count    db '","count":', 0
s_j_res      db ',"resources":[', 0
s_j_close    db "]}", 0
s_j_topen    db '{"type":', 0
s_j_tstr     db ',"type_str":"', 0
s_j_name     db '","name":', 0
s_j_nstr     db ',"name_str":"', 0
s_j_lang     db '","lang":', 0
s_j_lstr     db ',"lang_str":"', 0
s_j_size     db '","size":"0x', 0
s_j_rva      db '","rva":"0x', 0
s_j_off      db '","offset":"0x', 0
s_j_cp       db '","codepage":', 0
s_j_leaf_e   db "}", 0
s_j_comma    db ",", 0
s_j_m1       db "-1", 0

section .text

;-----------------------------------------------------------------------------
; dex_rsrc_list — rcx=cfg, rdx=img -> eax=0 | 3.
; Frame: 8 pushes + sub 448. jtmp 256B em [rbp-320,rbp-64).
; Slots: -328 file_end, -336 dir_end, -344 total, -352 dir_size,
;  -360 mode (0 conta, 1 imprime), -368 first (vírgula JSON).
; Non-voláteis: rbx=cfg, r15=img, rsi=dir_ptr, rdi=file_base,
;  r12=i, r13=j, r14=k.
;-----------------------------------------------------------------------------
dex_rsrc_list:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15                     ; 8 pushes (64B) + sub 448 = 512 ≡ 8
    sub rsp, 448
    mov rbx, rcx                 ; cfg
    mov r15, rdx                 ; img
    mov rsi, [r15+PeImage.file_buffer]
    mov rax, [r15+PeImage.file_size]
    lea rcx, [rsi+rax]
    mov [rbp-328], rcx           ; file_end
    mov rdi, rsi                 ; file_base
    mov rax, [r15+PeImage.opt_header]
    test rax, rax
    jz .empty
    mov ecx, [rax+OH64_NUM_RVA_SIZES]
    cmp ecx, 3
    jb .empty                    ; sem entrada de recursos: vazio honesto
    mov edx, [rax+OH64_DATA_DIR+16]   ; rsrc rva (entrada 2)
    mov eax, [rax+OH64_DATA_DIR+20]   ; rsrc size
    test eax, eax
    jz .empty                    ; size 0: sem recursos
    test edx, edx
    jz .malformed                ; size>0 com rva 0
    cmp eax, 0x400000
    ja .malformed                ; teto 4MB (documentado)
    mov [rbp-352], eax           ; dir_size
    mov rcx, r15
    sub rsp, 32
    call dex_rva_to_offset       ; rax=off (0 = fora)
    add rsp, 32
    test rax, rax
    jz .malformed
    lea rcx, [rdi+rax]           ; dir_ptr (ponteiro, não offset!)
    mov rdx, rcx
    add rdx, 16
    cmp rdx, [rbp-328]
    ja .malformed
    mov edx, [rbp-352]           ; dir_size (dword: zero-extend!)
    add rdx, rcx
    cmp rdx, [rbp-328]
    ja .malformed
    mov rsi, rcx                 ; dir_ptr
    mov [rbp-336], rdx           ; dir_end (exclusivo)
    ; ---- passada 1: conta+valida ----
    mov dword [rbp-360], 0       ; mode=conta
    sub rsp, 32
    call .rwalk
    add rsp, 32
    test eax, eax
    jnz .malformed_ret
    ; ---- header (com total) ----
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .hdr_text
    call .j_open_count
    jmp .pass2
.hdr_text:
    lea rcx, [rel s_r_hdr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-344]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
.pass2:
    ; ---- passada 2: imprime (revalida; impossível divergir) ----
    mov dword [rbp-360], 1       ; mode=imprime
    mov dword [rbp-368], 1       ; first=1
    sub rsp, 32
    call .rwalk
    add rsp, 32
    test eax, eax
    jnz .malformed_ret
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .done_ok
    lea rcx, [rel s_j_close]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .done_ok
.empty:
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .e_text
    call .j_open_count0
    jmp .done_ok
.e_text:
    lea rcx, [rel s_r_hdr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, 0
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    jmp .done_ok
.malformed:
    lea rcx, [rel s_r_err]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
.malformed_ret:
    mov eax, 3
    add rsp, 448
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.done_ok:
    xor eax, eax
    add rsp, 448
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
; .j_open_count — {"tool":"dexter","version":"M.m.p","count":N,"resources":[
; .j_open_count0 — idem com count 0 e fecha "]}" + newline (inventário vazio).
; Usam rbx=cfg, [rbp-344]=total. Clobber: rax,rcx,rdx.
;-----------------------------------------------------------------------------
.j_open_count:
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
    lea rcx, [rel s_j_count]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbp-344]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_j_res]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    ret
.j_open_count0:
    mov dword [rbp-344], 0
    sub rsp, 32
    call .j_open_count
    add rsp, 32
    lea rcx, [rel s_j_close]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    ret
;-----------------------------------------------------------------------------
; .rwalk — percorre 3 níveis; por folha valida tudo; conta sempre;
; emite só se mode==1 (texto ou JSON por DF_JSON).
; Índices em non-voláteis (r12=i, r13=j, r14=k: sobrevivem aos prints);
; counts e bases em slots ([rbp-392]=c0, [rbp-400]=c1, [rbp-408]=c2,
; [rbp-376]=sub1, [rbp-384]=sub2); total em [rbp-344]; first em [rbp-368].
; NADA volátil sobrevive a calls: recomputa-se tudo de slots/non-vols.
; Ret eax=0 ok | 3 malformado.
;-----------------------------------------------------------------------------
.rwalk:
    mov dword [rbp-344], 0       ; total (zera a cada passada)
    movzx ecx, word [rsi+12]
    movzx eax, word [rsi+14]
    add ecx, eax                 ; c0
    mov [rbp-392], ecx
    mov rax, rcx
    shl rax, 3
    lea rax, [rsi+rax+16]        ; fim das entradas L0
    cmp rax, [rbp-336]
    ja .rw_bad
    xor r12d, r12d               ; i
.rw_l0:
    cmp r12d, [rbp-392]
    jae .rw_ok
    mov eax, r12d
    shl eax, 3
    lea rax, [rsi+rax+16]        ; e0
    mov edx, [rax]               ; nid0
    mov r8d, [rax+4]             ; off0
    test r8d, 0x80000000
    jz .rw_bad                   ; L0 exige subdir
    and r8d, 0x7FFFFFFF
    lea rax, [rsi+r8]            ; sub1
    mov [rbp-376], rax
    lea rcx, [rax+16]
    cmp rcx, [rbp-336]
    ja .rw_bad
    movzx ecx, word [rax+12]
    movzx edx, word [rax+14]
    add ecx, edx                 ; c1
    mov [rbp-400], ecx
    mov rax, rcx
    shl rax, 3
    mov rdx, [rbp-376]
    lea rax, [rdx+rax+16]
    cmp rax, [rbp-336]
    ja .rw_bad
    xor r13d, r13d               ; j
.rw_l1:
    cmp r13d, [rbp-400]
    jae .rw_l0_next
    mov eax, r13d
    shl eax, 3
    mov rdx, [rbp-376]
    lea rax, [rdx+rax+16]        ; e1
    mov edx, [rax]               ; nid1
    mov r8d, [rax+4]             ; off1
    test r8d, 0x80000000
    jz .rw_bad                   ; L1 exige subdir
    and r8d, 0x7FFFFFFF
    lea rax, [rsi+r8]            ; sub2
    mov [rbp-384], rax
    lea rcx, [rax+16]
    cmp rcx, [rbp-336]
    ja .rw_bad
    movzx ecx, word [rax+12]
    movzx edx, word [rax+14]
    add ecx, edx                 ; c2
    mov [rbp-408], ecx
    mov rax, rcx
    shl rax, 3
    mov rdx, [rbp-384]
    lea rax, [rdx+rax+16]
    cmp rax, [rbp-336]
    ja .rw_bad
    xor r14d, r14d               ; k
.rw_l2:
    cmp r14d, [rbp-408]
    jae .rw_l1_next
    mov eax, r14d
    shl eax, 3
    mov rdx, [rbp-384]
    lea rax, [rdx+rax+16]        ; e2
    mov edx, [rax]               ; nid2 (lang)
    mov r8d, [rax+4]             ; off2
    test r8d, 0x80000000
    jnz .rw_bad                  ; L2 exige DADO (high clear)
    and r8d, 0x7FFFFFFF
    lea rax, [rsi+r8]            ; de (data entry)
    lea rcx, [rax+16]
    cmp rcx, [rbp-336]
    ja .rw_bad
    mov edx, [rax]               ; drva
    mov r8d, [rax+4]             ; dsize
    mov r9d, [rax+8]             ; cp
    mov [rbp-412], r9d           ; spill cp (dword isolado)
    test r8d, r8d
    jz .rw_leaf_empty
    test edx, edx
    jz .rw_bad                   ; size>0 com rva 0
    mov [rbp-416], r8d           ; spill dsize (r8 morre no call!)
    mov rcx, r15
    sub rsp, 32
    call dex_rva_to_offset       ; rax=foff (0 = fora)
    add rsp, 32
    test rax, rax
    jz .rw_bad
    mov [rbp-424], rax           ; spill foff (qword isolado)
    mov ecx, [rbp-416]           ; dsize
    add rcx, rax                 ; foff+dsize (64 bits, sem wrap)
    mov rdx, [rbp-328]           ; file_end
    sub rdx, rdi                 ; file_size (rdi=file_base intacto)
    cmp rcx, rdx
    ja .rw_bad                   ; payload além do arquivo
    jmp .rw_leaf_have
.rw_leaf_empty:
    mov qword [rbp-424], 0       ; foff=0 (vazio)
.rw_leaf_have:
    cmp dword [rbp-360], 0       ; mode==0? só conta
    je .rw_counted
    sub rsp, 32
    call .r_emit
    add rsp, 32
    test eax, eax
    jnz .rw_bad
.rw_counted:
    inc dword [rbp-344]          ; total
    inc r14d
    jmp .rw_l2
.rw_l1_next:
    inc r13d
    jmp .rw_l1
.rw_l0_next:
    inc r12d
    jmp .rw_l0
.rw_ok:
    xor eax, eax
    ret
.rw_bad:
    mov eax, 3
    ret
;-----------------------------------------------------------------------------
; .r_emit — emite UMA folha (modo 1). Recomputa tudo (nada volátil
; atravessa calls): e0/e1/e2, identidades, data entry, foff via slot.
; Usa r12/r13/r14 (idx), rsi (dir), slots. Ret eax=0.
;-----------------------------------------------------------------------------
.r_emit:
    mov eax, [rbx+DexConfig.flags]
    test eax, DF_JSON
    jz .re_text
    jmp .re_json
.re_text:
    lea rcx, [rel s_r_path1]     ; "  /"
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_id0                 ; T (num dec ou "str"); eax=0|3
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_r_sep]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_id1                 ; N
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_r_sep]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_id2                 ; L
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_r_size]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_dsize               ; hex do dsize (recomputa de)
    lea rcx, [rel s_r_rva]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_drva
    lea rcx, [rel s_r_off]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-424]           ; foff (spill do walker)
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    xor eax, eax
    ret
.re_json:
    cmp dword [rbp-368], 0       ; first? (1=primeira: sem vírgula)
    jne .re_jnoc
    lea rcx, [rel s_j_comma]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
.re_jnoc:
    mov dword [rbp-368], 0
    lea rcx, [rel s_j_topen]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_jid0                ; 24 ou -1
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_j_tstr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_jstr0               ; "str" ou "" (re-resolve)
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_j_name]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_jid1
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_j_nstr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_jstr1
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_j_lang]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_jid2
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_j_lstr]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_jstr2
    test eax, eax
    jnz .re_bad
    lea rcx, [rel s_j_size]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_dsize
    lea rcx, [rel s_j_rva]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_drva
    lea rcx, [rel s_j_off]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov rcx, [rbp-424]           ; foff (spill do walker)
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    lea rcx, [rel s_j_cp]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    call .re_cp
    lea rcx, [rel s_j_leaf_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor eax, eax
    ret
.re_bad:
    mov eax, 3
    ret
;-----------------------------------------------------------------------------
; Recomputa e0/e1/e2 + data entry. Cada helper rederiva do zero
; (slots + non-voláteis). Sem calls. Clobber: rax,rcx,rdx.
; .re_e0 -> rax=e0 | .re_e1 -> rax=e1 | .re_e2 -> rax=e2 | .re_de -> rax=de.
;-----------------------------------------------------------------------------
.re_e0:
    mov eax, r12d
    shl eax, 3
    lea rax, [rsi+rax+16]
    ret
.re_e1:
    mov eax, r13d
    shl eax, 3
    mov rdx, [rbp-376]
    lea rax, [rdx+rax+16]
    ret
.re_e2:
    mov eax, r14d
    shl eax, 3
    mov rdx, [rbp-384]
    lea rax, [rdx+rax+16]
    ret
.re_de:
    sub rsp, 32
    call .re_e2
    add rsp, 32
    mov edx, [rax+4]
    and edx, 0x7FFFFFFF
    lea rax, [rsi+rdx]
    ret
;-----------------------------------------------------------------------------
; .re_idN — imprime identidade do nível N (texto): dec ou "str".
; .re_jidN — idem p/ JSON numérico (ou -1 se string).
; .re_jstrN — imprime jtmp da string (ou "" se numérico).
; Resolvem via .rident na hora (nada atravessa calls).
;-----------------------------------------------------------------------------
.re_id0:
    sub rsp, 32
    call .re_e0
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_print
    add rsp, 32
    ret
.re_id1:
    sub rsp, 32
    call .re_e1
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_print
    add rsp, 32
    ret
.re_id2:
    sub rsp, 32
    call .re_e2
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_print
    add rsp, 32
    ret
.re_jid0:
    sub rsp, 32
    call .re_e0
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_num
    add rsp, 32
    ret
.re_jid1:
    sub rsp, 32
    call .re_e1
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_num
    add rsp, 32
    ret
.re_jid2:
    sub rsp, 32
    call .re_e2
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_num
    add rsp, 32
    ret
.re_jstr0:
    sub rsp, 32
    call .re_e0
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_str
    add rsp, 32
    ret
.re_jstr1:
    sub rsp, 32
    call .re_e1
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_str
    add rsp, 32
    ret
.re_jstr2:
    sub rsp, 32
    call .re_e2
    add rsp, 32
    mov edx, [rax]
    sub rsp, 32
    call .rident_str
    add rsp, 32
    ret
.re_dsize:
    sub rsp, 32
    call .re_de
    add rsp, 32
    mov ecx, [rax+4]
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    ret
.re_drva:
    sub rsp, 32
    call .re_de
    add rsp, 32
    mov ecx, [rax]               ; drva (dword! qword puxaria o size junto)
    xor edx, edx
    sub rsp, 32
    call dex_console_print_u64hex
    add rsp, 32
    ret
.re_cp:
    sub rsp, 32
    call .re_de
    add rsp, 32
    mov ecx, [rax+8]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    ret
;-----------------------------------------------------------------------------
; .rident_print — edx=nid -> imprime dec ou "str" (texto). Ret eax=0|3.
; .rident_num — edx=nid -> imprime dec ou -1 (JSON numérico). Ret eax=0|3.
; .rident_str — edx=nid -> imprime str com escape ou "" (JSON string).
; Ret eax=0|3. Usam jtmp + .rident (leaf). Clobber: rax,rcx,rdx.
;-----------------------------------------------------------------------------
.rident_print:
    sub rsp, 32
    call .rident
    add rsp, 32
    cmp eax, 3
    je .rip_bad
    test eax, eax
    jz .rip_dec
    lea rcx, [rel s_r_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rbp-320]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    lea rcx, [rel s_r_q]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor eax, eax
    ret
.rip_dec:
    mov ecx, edx
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    xor eax, eax
    ret
.rip_bad:
    mov eax, 3
    ret
.rident_num:
    sub rsp, 32
    call .rident
    add rsp, 32
    cmp eax, 3
    je .rin_bad
    test eax, eax
    jz .rin_dec
    lea rcx, [rel s_j_m1]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor eax, eax
    ret
.rin_dec:
    mov ecx, edx
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    xor eax, eax
    ret
.rin_bad:
    mov eax, 3
    ret
.rident_str:
    sub rsp, 32
    call .rident
    add rsp, 32
    cmp eax, 3
    je .ris_bad
    test eax, eax
    jz .ris_empty
    lea rcx, [rbp-320]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    xor eax, eax
    ret
.ris_empty:
    xor eax, eax
    ret                          ; string vazia: nada a imprimir (aspas já postas)
.ris_bad:
    mov eax, 3
    ret
;-----------------------------------------------------------------------------
; .rident — edx=nid -> eax=0 num (edx=num) | 1 str (jtmp) | 3 malformado.
; Valida limites SEMPRE (modo 0 e 1); copia p/ jtmp (cap 255+NUL).
; Leaf (sem calls). Clobber: rax,rcx,rdx,r8-r11. Preserva o resto.
; rsi=dir_ptr, [rbp-336]=dir_end, jtmp=[rbp-320].
;-----------------------------------------------------------------------------
.rident:
    test edx, 0x80000000
    jz .rid_num
    mov eax, edx
    and eax, 0x7FFFFFFF
    lea r10, [rsi+rax]           ; str_at
    mov rax, [rbp-336]
    lea rcx, [r10+2]
    cmp rcx, rax
    ja .rid_bad
    movzx r9d, word [r10]        ; len (wchars)
    mov rax, r9
    shl rax, 1
    lea rax, [r10+rax+2]
    cmp rax, [rbp-336]
    ja .rid_bad
    lea r8, [rbp-320]            ; dst
    xor ecx, ecx                 ; i
    xor r11d, r11d               ; n
.rid_l:
    cmp ecx, r9d
    jae .rid_end
    cmp r11d, 254
    jae .rid_end
    movzx eax, word [r10+rcx*2]
    mov edx, eax
    shr edx, 8
    test edx, edx
    jnz .rid_q
    cmp al, 0x20
    jb .rid_q
    cmp al, '"'
    je .rid_esc
    cmp al, '\'
    je .rid_esc
    mov [r8], al
    inc r8
    inc r11d
    inc ecx
    jmp .rid_l
.rid_q:
    mov byte [r8], '?'
    inc r8
    inc r11d
    inc ecx
    jmp .rid_l
.rid_esc:
    cmp r11d, 253
    ja .rid_end
    mov byte [r8], '\'
    inc r8
    mov [r8], al
    inc r8
    add r11d, 2
    inc ecx
    jmp .rid_l
.rid_end:
    mov byte [r8], 0
    mov eax, 1
    ret
.rid_num:
    mov eax, 0                   ; edx = num (high clear pelo test)
    ret
.rid_bad:
    mov eax, 3
    ret

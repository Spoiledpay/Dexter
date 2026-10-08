;=============================================================================
; Dexter/src/front/lexer.asm
; dex_lex_one — lexer NASM (tokens p/ o frontend R-6.3).
;
; O quê: tokeniza UM token NASM a partir de buf[pos].
; Por quê: o parser/AST (R-6.3) consome este stream (labels, mnemônicos,
;   registradores, números, strings, pontuação, comentários).
; Contrato:
;   Args: rcx=buf (não nulo), rdx=len, r8=pos, r9=&DexToken (não nulo).
;   Ret:  rax=consumidos (>0) ou 0 se pos>=len (fim) ou args nulos.
;   Token: kind (LEX_*), val, ptr, len, line (1-based), col (0-based).
;   line/col por rescan O(pos) — exato e simples; o parser R-6.3 rastreia
;   incremental p/ entradas grandes.
;   Total: nunca falha por conteúdo (desconhecido = LEX_UNKNOWN, 1 char).
;   Números >2^64 sofrem wrap natural (determinístico; corpus: pequenos).
;   Sufixos NASM (10h, 101b) NÃO são fundidos: NUM + IDENT (raro; nosso
;   emissor só gera 0x../decimal; documentado, sem erro falso).
;   Strings: `"` ou `'` até a aspa irmã (sem escapes — nosso emissor não
;   emite `"`/`\` dentro; `", 34, "` já vem partido); sem fechar: até EOL.
;   LABEL: ident imediatamente seguido de ':' (exceto seg es..gs, que sai
;   REG+COLON p/ override `[fs:x]`); `global x` (sem ':') = IDENT.
;   REG: GPRs via tabelas dex_r*_names (case-insensitive) + hi (ah..bh)
;   + seg (es..gs); resto dos idents = IDENT (xmm/mm/st/cr: parser decide).
;   Sem heap. Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\lex_check.asm sobre tests\hello.asm (golden).
;
; Requisitos atendidos: R-6.2 (dex_lex_one)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_lex_one
global dex_lex_match

extern dex_r64_names
extern dex_r32_names
extern dex_r16_names
extern dex_r8_names
extern dex_r8hi_names
extern dex_seg_names

section .text

;-----------------------------------------------------------------------------
; dex_lex_one — rcx=buf, rdx=len, r8=pos, r9=&tok -> rax=consumidos | 0.
; Estado: rbx=buf, r12=len, r13=tok, r14=pos0, r10=cursor, r11=start.
; Livres: rax, rcx, rdx, r8, r9. Chamadas internas (dex_lex_match) com shadow.
;-----------------------------------------------------------------------------
dex_lex_one:
    test rcx, rcx
    jz .ret0
    test r9, r9
    jz .ret0
    cmp r8, rdx
    jae .ret0
    jmp .lex_body
.ret0:
    xor eax, eax
    ret
.lex_body:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rcx                 ; buf
    mov r12, rdx                 ; len
    mov r13, r9                  ; tok
    mov r14, r8                  ; pos0
    mov r10, r8                  ; cursor
.skip_ws:
    cmp r10, r12
    jae .eof_end                 ; só espaços até EOF: 0 (fim limpo)
    movzx eax, byte [rbx+r10]
    cmp al, ' '
    je .ws_adv
    cmp al, 9                    ; \t
    jne .classify
.ws_adv:
    inc r10
    jmp .skip_ws
.eof_end:
    xor eax, eax
    jmp .out
.classify:
    mov r11, r10                 ; start
    cmp al, 13                   ; \r
    je .t_eol
    cmp al, 10                   ; \n
    je .t_eol
    cmp al, ';'
    je .t_comment
    cmp al, '"'
    je .t_str
    cmp al, "'"
    je .t_str
    cmp al, '['
    je .t_lb
    cmp al, ']'
    je .t_rb
    cmp al, ','
    je .t_co
    cmp al, ':'
    je .t_cc
    cmp al, '+'
    je .t_pl
    cmp al, '-'
    je .t_mi
    cmp al, '*'
    je .t_st
    cmp al, '/'
    je .t_sl
    cmp al, '0'
    jb .t_idq
    cmp al, '9'
    jbe .t_num
.t_idq:
    cmp al, 'A'
    jb .t_idq2
    cmp al, 'Z'
    jbe .t_ident
    cmp al, '_'
    je .t_ident
    cmp al, 'a'
    jb .t_unk
    cmp al, 'z'
    jbe .t_ident
    jmp .t_unk
.t_idq2:
    cmp al, '.'
    je .t_ident
    cmp al, '$'
    je .t_ident
    cmp al, '_'
    je .t_ident
.t_unk:
    ; desconhecido: 1 char (total: nunca 0 por conteúdo)
    mov dword [r13+DexToken.kind], LEX_UNKNOWN
    mov qword [r13+DexToken.val], 0
    lea rax, [rbx+r11]
    mov [r13+DexToken.ptr], rax
    mov qword [r13+DexToken.len], 1
    lea r10, [r11+1]
    jmp .fill_lc

; ---- EOL: \r\n (par) ou char único ----
.t_eol:
    mov dword [r13+DexToken.kind], LEX_EOL
    mov qword [r13+DexToken.val], 0
    lea rax, [rbx+r11]
    mov [r13+DexToken.ptr], rax
    cmp al, 13
    jne .eol_1
    lea rax, [r11+1]
    cmp rax, r12
    jae .eol_1
    cmp byte [rbx+rax], 10
    jne .eol_1
    mov qword [r13+DexToken.len], 2
    add r10, 2
    jmp .fill_lc
.eol_1:
    mov qword [r13+DexToken.len], 1
    inc r10
    jmp .fill_lc

; ---- comentário: ';' até (sem incluir) \r \n EOF ----
.t_comment:
    mov dword [r13+DexToken.kind], LEX_COMMENT
    mov qword [r13+DexToken.val], 0
    lea rax, [rbx+r11]
    mov [r13+DexToken.ptr], rax
.tc_l:
    cmp r10, r12
    jae .tc_e
    movzx eax, byte [rbx+r10]
    cmp al, 13
    je .tc_e
    cmp al, 10
    je .tc_e
    inc r10
    jmp .tc_l
.tc_e:
    mov rax, r10
    sub rax, r11
    mov [r13+DexToken.len], rax
    jmp .fill_lc

; ---- string: aspa-irmã ou EOL/EOF (conteúdo sem as aspas) ----
.t_str:
    mov r8b, al                    ; quote (r8 livre: pos0 está em r14)
    mov dword [r13+DexToken.kind], LEX_STR
    mov qword [r13+DexToken.val], 0
    lea rax, [rbx+r11+1]
    mov [r13+DexToken.ptr], rax
    inc r10
.ts_l:
    cmp r10, r12
    jae .ts_e
    movzx eax, byte [rbx+r10]
    cmp al, r8b
    je .ts_close
    cmp al, 13
    je .ts_e
    cmp al, 10
    je .ts_e
    inc r10
    jmp .ts_l
.ts_close:
    inc r10
    lea rax, [r11+1]               ; offsets (nunca endereço!): len = end
    mov rcx, r10                   ;   - (start+1) - 1 (aspa final)
    sub rcx, rax
    dec rcx
    mov [r13+DexToken.len], rcx
    jmp .fill_lc
.ts_e:
    lea rax, [r11+1]               ; offsets: len = end - (start+1)
    mov rcx, r10                   ; (aberta, ou "" -> 0)
    sub rcx, rax
    mov [r13+DexToken.len], rcx
    jmp .fill_lc

; ---- pontuação de 1 char ----
.t_lb:
    mov eax, LEX_LBR
    jmp .t_single
.t_rb:
    mov eax, LEX_RBR
    jmp .t_single
.t_co:
    mov eax, LEX_COMMA
    jmp .t_single
.t_cc:
    mov eax, LEX_COLON
    jmp .t_single
.t_pl:
    mov eax, LEX_PLUS
    jmp .t_single
.t_mi:
    mov eax, LEX_MINUS
    jmp .t_single
.t_st:
    mov eax, LEX_STAR
    jmp .t_single
.t_sl:
    mov eax, LEX_SLASH
.t_single:
    mov [r13+DexToken.kind], eax
    mov qword [r13+DexToken.val], 0
    lea rax, [rbx+r11]
    mov [r13+DexToken.ptr], rax
    mov qword [r13+DexToken.len], 1
    inc r10
    jmp .fill_lc

; ---- número: 0x-hex ou decimal (wrap natural) ----
.t_num:
    mov dword [r13+DexToken.kind], LEX_NUM
    lea rax, [rbx+r11]
    mov [r13+DexToken.ptr], rax
    xor eax, eax                   ; val
    cmp byte [rbx+r11], '0'
    jne .num_dec
    lea rcx, [r11+1]
    cmp rcx, r12
    jae .num_dec
    movzx ecx, byte [rbx+r11+1]
    cmp cl, 'x'
    je .num_hex
    cmp cl, 'X'
    jne .num_dec
.num_hex:
    add r10, 2
    mov r8, r10                    ; marca dígitos (r8 livre aqui: pos0 em r14)
.num_hex_l:
    cmp r10, r12
    jae .num_hex_e
    movzx ecx, byte [rbx+r10]
    cmp cl, '0'
    jb .num_hex_e
    cmp cl, '9'
    jbe .num_hex_d
    or cl, 32                      ; fold case
    cmp cl, 'a'
    jb .num_hex_e
    cmp cl, 'f'
    ja .num_hex_e
    sub cl, 'a'-10
    jmp .num_hex_a
.num_hex_d:
    sub cl, '0'
.num_hex_a:
    shl rax, 4
    movzx ecx, cl
    add rax, rcx
    inc r10
    jmp .num_hex_l
.num_hex_e:
    cmp r10, r8
    jne .num_store                 ; dígitos? ok
    mov r10, r11
    inc r10                        ; `0x` sozinho: só o "0" (x relexa)
    xor eax, eax
    jmp .num_store
.num_dec:
    ; r10=start (primeiro char é dígito: consome ≥1)
.num_dec_l:
    cmp r10, r12
    jae .num_store
    movzx ecx, byte [rbx+r10]
    cmp cl, '0'
    jb .num_store
    cmp cl, '9'
    ja .num_store
    sub ecx, '0'
    lea rax, [rax+rax*4]           ; x5
    lea rax, [rcx+rax*2]           ; x10+d
    inc r10
    jmp .num_dec_l
.num_store:
    mov [r13+DexToken.val], rax
    mov rax, r10
    sub rax, r11
    mov [r13+DexToken.len], rax
    jmp .fill_lc

; ---- ident: [start,r10) já com 1º char válido ----
.t_ident:
    inc r10
.ti_l:
    cmp r10, r12
    jae .ti_e
    movzx eax, byte [rbx+r10]
    cmp al, 'A'
    jb .ti_ck0
    cmp al, 'Z'
    jbe .ti_adv
    cmp al, 'a'
    jb .ti_ck1                   ; faixa Z..a contém '_' (0x5F): cai nos
                                 ; especiais; [\]^` voltam em .ti_no (iguais)
    cmp al, 'z'
    jbe .ti_adv
    jmp .ti_no
.ti_ck0:
    cmp al, '0'
    jb .ti_ck1
    cmp al, '9'
    jbe .ti_adv
    jmp .ti_no
.ti_ck1:
    cmp al, '_'
    je .ti_adv
    cmp al, '.'
    je .ti_adv
    cmp al, '$'
    je .ti_adv
    cmp al, '?'
    je .ti_adv
    cmp al, '#'
    je .ti_adv
    cmp al, '@'
    je .ti_adv
    cmp al, '~'
    je .ti_adv
.ti_no:
    jmp .ti_e
.ti_adv:
    inc r10
    jmp .ti_l
.ti_e:
    ; ':' em seguida? (LABEL, exceto seg que sai REG+COLON)
    cmp r10, r12
    jae .reg_all
    cmp byte [rbx+r10], ':'
    jne .reg_all
    lea rcx, [rbx+r11]             ; ident ptr
    mov rdx, r10
    sub rdx, r11                   ; ident len
    lea r8, [rel dex_seg_names]
    mov r9d, 7
    sub rsp, 40
    call dex_lex_match
    add rsp, 40
    cmp rax, 0
    jle .mk_label                  ; -1/0: não é seg ([0]=nulo)
    ; REG-SEG (idx 1-6): sem consumir ':'. val = idx | size2<<8 | SEG.
    or rax, 0x20200
    jmp .reg_emit
.reg_all:
    lea rcx, [rbx+r11]
    mov rdx, r10
    sub rdx, r11
    lea r8, [rel dex_r64_names]
    mov r9d, 16
    sub rsp, 40
    call dex_lex_match
    add rsp, 40
    test rax, rax
    jns .got_r64
    lea r8, [rel dex_r32_names]
    mov r9d, 16
    sub rsp, 40
    call dex_lex_match
    add rsp, 40
    test rax, rax
    jns .got_r32
    lea r8, [rel dex_r16_names]
    mov r9d, 16
    sub rsp, 40
    call dex_lex_match
    add rsp, 40
    test rax, rax
    jns .got_r16
    lea r8, [rel dex_r8_names]
    mov r9d, 16
    sub rsp, 40
    call dex_lex_match
    add rsp, 40
    test rax, rax
    jns .got_r8
    lea r8, [rel dex_r8hi_names]
    mov r9d, 4
    sub rsp, 40
    call dex_lex_match
    add rsp, 40
    test rax, rax
    js .mk_ident
    add rax, 4                     ; reg 4-7
    or rax, 0x10100                ; size=1 + HI
    jmp .reg_emit
.got_r64:
    or rax, 0x800                  ; size=8
    jmp .reg_emit
.got_r32:
    or rax, 0x400                  ; size=4
    jmp .reg_emit
.got_r16:
    or rax, 0x200                  ; size=2
    jmp .reg_emit
.got_r8:
    or rax, 0x100                  ; size=1
    jmp .reg_emit
.reg_emit:
    mov [r13+DexToken.val], rax
    mov dword [r13+DexToken.kind], LEX_REG
    jmp .id_common
.mk_ident:
    mov dword [r13+DexToken.kind], LEX_IDENT
    mov qword [r13+DexToken.val], 0
    jmp .id_common
.mk_label:
    mov dword [r13+DexToken.kind], LEX_LABEL
    mov qword [r13+DexToken.val], 0
    lea rax, [rbx+r11]
    mov [r13+DexToken.ptr], rax
    mov rax, r10
    sub rax, r11
    mov [r13+DexToken.len], rax
    inc r10                        ; consome ':'
    jmp .fill_lc
.id_common:
    lea rax, [rbx+r11]
    mov [r13+DexToken.ptr], rax
    mov rax, r10
    sub rax, r11
    mov [r13+DexToken.len], rax
    jmp .fill_lc

; ---- line/col por rescan [0,start): O(pos), exato ----
.fill_lc:
    mov eax, 1                     ; line
    xor r8d, r8d                   ; i
    xor edx, edx                   ; bol
.fl_l:
    cmp r8, r11
    jae .fl_e
    movzx ecx, byte [rbx+r8]
    cmp cl, 10
    je .fl_nl
    cmp cl, 13
    jne .fl_nx
    lea ecx, [r8+1]
    cmp rcx, r11
    jae .fl_nl2
    cmp byte [rbx+rcx], 10
    je .fl_nx                      ; \r\n: o \n conta
.fl_nl2:
    inc eax
    lea edx, [r8+1]
    jmp .fl_nx
.fl_nl:
    inc eax
    lea edx, [r8+1]
.fl_nx:
    inc r8
    jmp .fl_l
.fl_e:
    mov [r13+DexToken.line], eax
    mov ecx, r11d
    sub ecx, edx
    mov [r13+DexToken.col], ecx
    mov rax, r10
    sub rax, r14                   ; consumed = end - pos0 (>0 sempre)
    jmp .out
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

;-----------------------------------------------------------------------------
; dex_lex_match — rcx=ptr, rdx=len, r8=tab(NUL-ptrs), r9d=n -> rax=idx | -1.
; Compara case-insensitive, tamanho exato (entradas NUL-terminadas; NULL
; pula). Reusado pelo parser p/ keywords. Preserva rcx,rdx,r8,r9,rbx,rbp,
; rdi,rsi,r12-r15 (só rax + pushed r10,r11,rsi,rdi). Leaf (sem calls).
; Chamada COM shadow (sub rsp,32+) pelo chamador.
;-----------------------------------------------------------------------------
dex_lex_match:
.match_tab:
    push r10
    push r11
    push rsi
    push rdi
    mov rsi, rcx
    xor r10d, r10d                 ; i
.mt_l:
    cmp r10d, r9d
    jae .mt_no
    mov rdi, [r8+r10*8]            ; entry (pode ser 0: pula)
    test rdi, rdi
    jz .mt_next
    xor r11d, r11d                 ; j
.mt_c:
    cmp r11d, edx
    jae .mt_echeck
    mov al, [rsi+r11]
    cmp al, 'A'
    jb .mt_cmp
    cmp al, 'Z'
    ja .mt_cmp
    add al, 32
.mt_cmp:
    cmp al, [rdi+r11]
    jne .mt_next
    inc r11d
    jmp .mt_c
.mt_echeck:
    cmp byte [rdi+r11], 0          ; entrada termina aqui? (exato)
    jne .mt_next
    mov rax, r10
    pop rdi
    pop rsi
    pop r11
    pop r10
    ret
.mt_next:
    inc r10d
    jmp .mt_l
.mt_no:
    mov rax, -1
    pop rdi
    pop rsi
    pop r11
    pop r10
    ret

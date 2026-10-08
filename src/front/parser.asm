;=============================================================================
; Dexter/src/front/parser.asm
; dex_parse_asm — parser textual NASM -> AST (R-6.3).
;
; O quê: parseia fonte NASM (buf/len) em AstUnit (funcs/blocos/CFG + dados).
; Por quê: o lift/codegen (R-6.4) consome a AST; o teste golden valida aqui.
; Contrato:
;   Args: rcx=buf, rdx=len, r8=&out_unit.
;   Ret:  eax=0 ok | 6 OOM | 7 entrada >16 MB | 8 args inválidos.
;   Total fora OOM/limite: linhas estranhas viram AstData verbatim
;   (incl. db/equ/diretivas e operandos fora do subconjunto); comentários
;   e EOLs são descartados (re-emissão não os preserva — documentado).
;   Nomes/verbatim EMPRESTAM o fonte (ptr/len, sem cópia).
;   Regras de estrutura (determinísticas; detalhe noates abaixo):
;   - seção corrente: só atribuição (qualquer seção aceita código; db/equ
;     é dado em qualquer seção; `section X` atualiza + vira diretiva);
;   - nova Func: primeiro label de código, ou label chamado por `call`
;     (exceto recursão no próprio nome); resto é bloco;
;   - bloco novo: em todo label e após jmp/jcc/ret (calls NÃO dividem);
;   - succs: CALL/BRANCH/JMP por tname resolvido (blocos; -1 externo),
;     FALL p/ próximo bloco (exceto após jmp/ret);
;   - operandos: REG (do token), IMM (tamanho: marcador strict/byte/...,
;     senão mínimo pelo valor), REL (nome), MEM ([rel x], [abs n],
;     [base+idx*esc±disp], seg `fs:`); fora disso a LINHA vira diretiva;
;   - MEM sem marcador e sem REG: size 0 (R-6.4 infere); hi-bytes (ah..)
;     perdem o marcador HI (documentado); base r32 assume 64 (documentado);
;   - labels empilhados ficam com o ÚLTIMO; label solto no fim some;
;     `$`-sozinho e nomes sem def viram REL com tidx -1.
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\ast_check.asm (golden hello.asm + loop.asm).
;
; Requisitos atendidos: R-6.3 (dex_parse_asm)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_parse_asm

extern dex_lex_one
extern dex_lex_match
extern dex_malloc
extern dex_free
extern dex_realloc_grow
extern dex_memcmp
extern dex_ast_unit_new
extern dex_ast_unit_func
extern dex_ast_func_block
extern dex_ast_block_instr
extern dex_ast_block_succ
extern dex_ast_unit_data
extern dex_ast_free_unit

%define AST_MAX_FILE (16*1024*1024)

section .rodata
align 8
k_s_section: db "section", 0
k_s_global:  db "global", 0
k_s_extern:   db "extern", 0
k_s_bits:     db "bits", 0
k_s_default:  db "default", 0
k_t_dir:      dq k_s_section, k_s_global, k_s_extern, k_s_bits
               dq k_s_default
k_s_db:       db "db", 0
k_t_db:        dq k_s_db
k_s_equ:       db "equ", 0
k_t_equ:       dq k_s_equ
k_s_call:      db "call", 0
k_t_call:      dq k_s_call
k_s_ret:       db "ret", 0
k_s_retf:      db "retf", 0
k_t_ret:       dq k_s_ret, k_s_retf
k_s_jmp:       db "jmp", 0
k_t_jmp:       dq k_s_jmp
k_s_loop:      db "loop", 0
k_s_loope:     db "loope", 0
k_s_loopne:    db "loopne", 0
k_s_loopnz:    db "loopnz", 0
k_s_loopz:     db "loopz", 0
k_s_jecxz:     db "jecxz", 0
k_s_jrcxz:     db "jrcxz", 0
k_t_loop:      dq k_s_loop, k_s_loope, k_s_loopne, k_s_loopnz
                dq k_s_loopz, k_s_jecxz, k_s_jrcxz
k_s_byte:      db "byte", 0
k_s_word:      db "word", 0
k_s_dword:     db "dword", 0
k_s_qword:     db "qword", 0
k_t_size:      dq k_s_byte, k_s_word, k_s_dword, k_s_qword
k_s_lock:      db "lock", 0
k_s_rep:       db "rep", 0
k_s_repne:     db "repne", 0
k_t_lockrep:   dq k_s_lock, k_s_rep, k_s_repne
k_s_rel:       db "rel", 0
k_t_rel:       dq k_s_rel
k_s_abs:       db "abs", 0
k_t_abs:       dq k_s_abs
k_s_strict:    db "strict", 0
k_t_strict:    dq k_s_strict
k_t_section:   dq k_s_section

section .text

;-----------------------------------------------------------------------------
; dex_parse_asm — rcx=buf, rdx=len, r8=&out -> eax=0/6/7/8.
; Estado: rbx=buf, r12=len, r13=unit, r14=pos, r15=scratch.
; Frame (6 pushes + sub rsp,248; locais [rbp-296,rbp-48), fora da shadow):
;   linebuf[-56,-48) linecap[-64,-56) linen[-72,-64) (= spill de m no
;   .dispatch: .lex_line já retornou; .code_instr restaura de lá)
;   calltab[-80,-72) callcap[-88,-80) calln[-96,-88) ({ptr,len}16B, Pass A)
;   sect_ptr[-104,-96) sect_len[-112,-104)
;   pend_ptr[-120,-112) pend_len[-128,-120) has_pend[-132,-128)
;   cur_func[-136,-132) cur_block[-140,-136) (dword, -1 = nenhum)
;   tok_tmp(40B)[-180,-140) instr_tmp(96B)[-276,-180)
; Fases: A (call-targets, streaming) -> B (monta) -> C (resolve+succs).
; Todos os grows checados; .fail_oom libera linebuf+calltab+unit(parcial).
;-----------------------------------------------------------------------------
dex_parse_asm:
    test rcx, rcx
    jz .err_args
    test r8, r8
    jz .err_args
    cmp rdx, AST_MAX_FILE
    ja .err_big
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 248                  ; frame [rbp-296,rbp-48): instr_tmp vai a -276
    mov rbx, rcx                 ; buf
    mov r12, rdx                 ; len
    mov [rbp-48], r8             ; &out (r8 morre; slot dedicado)
    mov qword [rbp-56], 0        ; linebuf=NULL
    mov qword [rbp-64], 0        ; linecap=0
    mov qword [rbp-80], 0        ; calltab=NULL
    mov qword [rbp-88], 0        ; callcap=0
    mov qword [rbp-96], 0        ; calln=0
    mov qword [rbp-104], 0       ; sect_ptr=NULL
    mov qword [rbp-112], 0       ; sect_len=0
    mov dword [rbp-132], 0       ; has_pend=0
    mov dword [rbp-136], -1      ; cur_func=none
    mov dword [rbp-140], -1      ; cur_block=none
    xor r13d, r13d               ; unit=NULL (fail seguro)
    xor r14d, r14d               ; pos=0
    sub rsp, 32
    call dex_ast_unit_new
    add rsp, 32
    test rax, rax
    jz .fail_oom
    mov r13, rax                 ; unit
    ; ---- Pass A: call-targets (streaming) ----
    xor r15d, r15d               ; call_armed=0
.pa_l:
    cmp r14, r12
    jae .pa_done
    mov rcx, rbx
    mov rdx, r12
    mov r8, r14
    lea r9, [rbp-180]            ; tok_tmp
    sub rsp, 32
    call dex_lex_one
    add rsp, 32
    test rax, rax
    jz .pa_done
    add r14, rax
    mov eax, [rbp-180+DexToken.kind]
    cmp eax, LEX_EOL
    je .pa_eol
    cmp eax, LEX_COMMENT
    je .pa_l
    cmp eax, LEX_LABEL
    jne .pa_maybe_call
    xor r15d, r15d               ; label quebra adjacência call-alvo
    jmp .pa_l                    ; (defs de label: Pass C busca na AST)
.pa_maybe_call:
    cmp eax, LEX_IDENT
    jne .pa_clrarm
    test r15d, r15d
    jz .pa_armq
    ; IDENT logo após call (mesma linha): registra alvo
    mov rcx, [rbp-180+DexToken.ptr]
    mov rdx, [rbp-180+DexToken.len]
    sub rsp, 32
    call .call_add
    add rsp, 32
    test eax, eax
    jnz .fail_oom
    xor r15d, r15d
    jmp .pa_l
.pa_armq:
    mov rcx, [rbp-180+DexToken.ptr]
    mov rdx, [rbp-180+DexToken.len]
    lea r8, [rel k_t_call]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    js .pa_l                     ; -1: não é call
    mov r15d, 1
    jmp .pa_l
.pa_clrarm:
    xor r15d, r15d
    jmp .pa_l
.pa_eol:
    xor r15d, r15d
    jmp .pa_l
.pa_done:
    ; ---- Pass B: monta (re-lex do zero) ----
    xor r14d, r14d               ; pos=0
.pb_l:
    sub rsp, 32
    call .lex_line               ; eax = ntoks | -1 OOM (linebuf)
    add rsp, 32
    cmp eax, -1
    je .fail_oom
    test eax, eax
    jz .pb_eolchk                 ; 0 toks: EOF ou linha vazia
    mov r15d, eax                 ; n
    sub rsp, 32
    call .dispatch               ; processa linebuf[0..n)
    add rsp, 32
    test eax, eax
    jnz .fail_oom
    jmp .pb_l
.pb_eolchk:
    cmp r14, r12
    jae .pb_done                 ; EOF de verdade
    jmp .pb_l                    ; linha vazia (EOL consumido): segue
.pb_done:
    ; ---- Pass C: resolve + succs ----
    sub rsp, 32
    call .resolve
    add rsp, 32
    test eax, eax
    jnz .fail_oom
    mov rax, [rbp-48]            ; &out
    mov [rax], r13
    mov rcx, [rbp-56]
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rcx, [rbp-80]
    sub rsp, 32
    call dex_free
    add rsp, 32
    xor eax, eax
    add rsp, 248
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fail_oom:
    mov rcx, [rbp-56]
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rcx, [rbp-80]
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rcx, r13
    sub rsp, 32
    call dex_ast_free_unit       ; null-safe + tolera parcial
    add rsp, 32
    mov rax, [rbp-48]
    mov qword [rax], 0
    mov eax, ERR_OOM
    add rsp, 248
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.err_big:
    mov eax, ERR_OVERFLOW
    ret
.err_args:
    mov eax, ERR_ARGS
    ret

;-----------------------------------------------------------------------------
; .call_add — rcx=ptr, rdx=len -> eax=0 ok | 6 OOM. Acrescenta {ptr,len}
; (16B) à calltab. Preserva rbx,r12-r15 (ptr/len em rbx/r12, salvos).
;-----------------------------------------------------------------------------
.call_add:
    push rbx
    push r12
    mov rbx, rcx                 ; ptr
    mov r12, rdx                 ; len
    mov eax, [rbp-96]            ; n
    cmp eax, [rbp-88]            ; vs cap
    jb .ca_store
    mov ecx, [rbp-88]
    shl rcx, 4                   ; old_bytes
    mov eax, [rbp-96]
    inc rax
    shl rax, 4                   ; min=(n+1)*16
    mov r8, rax
    mov rdx, rcx                 ; old_bytes
    mov rcx, [rbp-80]            ; old
    sub rsp, 40                  ; (2 pushes: alinha p/ call)
    call dex_realloc_grow        ; rax=new, rdx=new_bytes
    add rsp, 40
    test rax, rax
    jz .ca_oom
    mov [rbp-80], rax
    mov rax, rdx                 ; new_cap (bytes; rdx morre no xor!)
    xor edx, edx
    mov ecx, 16
    div rcx                      ; elems = bytes/16 (new>=min: progresso)
    mov [rbp-88], eax
.ca_store:
    mov eax, [rbp-96]
    shl rax, 4
    mov rcx, [rbp-80]
    add rcx, rax                 ; slot
    mov [rcx], rbx
    mov [rcx+8], r12
    inc dword [rbp-96]
    xor eax, eax
    pop r12
    pop rbx
    ret
.ca_oom:
    mov eax, ERR_OOM
    pop r12
    pop rbx
    ret

;-----------------------------------------------------------------------------
; .code_instr — r11d=m (mne idx), rdi=linebuf, r15d=n. Parseia instrução
; p/ instr_tmp, anexa ao bloco atual (abre func/bloco conf. regras), fecha
; em jmp/ret. Ret: eax=0 ok | 6 OOM. (Linha inválida -> o CHAMADOR desvia
; p/ verbatim ANTES: aqui mne já é IDENT; falhas de operando retornam 1
; (->verbatim) via .op_fail interno, não OOM.)
; Efetivo: usa pend slots p/ eff; limpa ao fim. Preserva rbx,r12-r15.
;-----------------------------------------------------------------------------
.code_instr:
    ; template 96B em instr_tmp: zera (12 qwords; tidx=-1 = irresoluto)
    lea rax, [rbp-276]
    xor ecx, ecx
    mov [rax+0], rcx
    mov [rax+8], rcx
    mov [rax+16], rcx
    mov [rax+24], rcx
    mov [rax+32], rcx
    mov [rax+40], rcx
    mov [rax+48], rcx
    mov [rax+56], rcx
    mov [rax+64], rcx
    mov [rax+72], rcx
    mov [rax+80], rcx
    mov [rax+88], rcx
    mov qword [rax+AstInstr.tidx], -1
    ; prefixos lock/rep (r11d=m avança; flags no template)
.ci_prefix:
    cmp r11d, r15d
    jae .dp_code_verbatim        ; linha era só prefixo(s): verbatim
    mov eax, r11d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_IDENT
    jne .ci_mne                  ; não-ident: é o mne (ou inválido; checa)
    mov rcx, [rdi+rax+DexToken.ptr]
    mov rdx, [rdi+rax+DexToken.len]
    lea r8, [rel k_t_lockrep]
    mov r9d, 3
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    js .ci_mne                   ; não é prefixo: é o mne
    cmp eax, 0
    je .ci_lock
    or dword [rbp-276+AstInstr.flags], AST_F_REP
    jmp .ci_prefix_next
.ci_lock:
    or dword [rbp-276+AstInstr.flags], AST_F_LOCK
.ci_prefix_next:
    inc r11d
    jmp .ci_prefix
.ci_mne:
    ; mne = tok[m] deve ser IDENT (senão verbatim: ex `5 ...`, `[..`).
    mov eax, r11d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_IDENT
    jne .dp_code_verbatim
    lea rcx, [rdi+rax]           ; &tok[m]
    mov rdx, [rcx+DexToken.ptr]
    mov [rbp-276+AstInstr.mne_ptr], rdx
    mov rdx, [rcx+DexToken.len]
    mov [rbp-276+AstInstr.mne_len], rdx
    ; flags pelo mne (matcher preserva rcx/rdx: seta 1x, 4 tabelas).
    mov eax, r11d
    imul eax, eax, SIZEOF_TOKEN
    lea rax, [rdi+rax]           ; &tok[m]
    mov rcx, [rax+DexToken.ptr]
    mov rdx, [rax+DexToken.len]
    lea r8, [rel k_t_call]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .ci_fcall
    lea r8, [rel k_t_ret]
    mov r9d, 2
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .ci_fret
    lea r8, [rel k_t_jmp]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .ci_fjmp
    lea r8, [rel k_t_loop]
    mov r9d, 7
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .ci_fbranch
    ; regra-j: inicia com j/J e não é jmp?
    movzx eax, byte [rcx]
    cmp al, 'j'
    je .ci_fbranch
    cmp al, 'J'
    je .ci_fbranch
    jmp .ci_opsplit
.ci_fcall:
    or dword [rbp-276+AstInstr.flags], AST_F_CALL
    jmp .ci_opsplit
.ci_fret:
    or dword [rbp-276+AstInstr.flags], AST_F_RET
    jmp .ci_opsplit
.ci_fjmp:
    or dword [rbp-276+AstInstr.flags], AST_F_JMP
    jmp .ci_opsplit
.ci_fbranch:
    or dword [rbp-276+AstInstr.flags], AST_F_BRANCH
    jmp .ci_opsplit

;-----------------------------------------------------------------------------
; Split + parse de operandos. r11d=m (mne), r15d=n, rdi=linebuf.
; Split puro (sem calls): c1/c2 em r10d/r11d? m morre no split... usa
; r8d=c1, r9d=c2, r10d=depth, r11d=m->i (r11 morre no fim do split ok).
; .parse_op preserva r8-r11 (contrato!) + não-voláteis: c1/c2 sobrevivem.
; .parse_op(rcx=s, rdx=e, r8d=opidx) -> eax=0 ok | 1 fallback.
;-----------------------------------------------------------------------------
.ci_opsplit:
    ; r11d=m (preservado!), r9d=c1(-1), r10d=c2(-1), r8d=i, edx=depth.
    mov r9d, -1
    mov r10d, -1
    lea r8d, [r11d+1]            ; i = m+1
    cmp r8d, r15d
    jae .ci_noops                ; sem operandos (ret/nop/leave)
    xor edx, edx                 ; depth
.ci_sp:
    cmp r8d, r15d
    jae .ci_sp_end
    mov eax, r8d
    imul eax, eax, SIZEOF_TOKEN
    mov eax, [rdi+rax+DexToken.kind]
    cmp eax, LEX_LBR
    je .ci_sp_lb
    cmp eax, LEX_RBR
    je .ci_sp_rb
    cmp eax, LEX_COMMA
    jne .ci_sp_nx
    test edx, edx
    jnz .ci_sp_nx                ; vírgula dentro de []: parte do mem
    cmp r9d, -1
    jne .ci_sp_c2
    mov r9d, r8d                 ; c1
    jmp .ci_sp_nx
.ci_sp_c2:
    cmp r10d, -1
    jne .ci_sp_fail              ; 3ª vírgula: >3 operandos
    mov r10d, r8d                ; c2
    jmp .ci_sp_nx
.ci_sp_lb:
    inc edx
    jmp .ci_sp_nx
.ci_sp_rb:
    dec edx
    js .ci_sp_fail               ; ] sem [: fallback
    jmp .ci_sp_nx
.ci_sp_nx:
    inc r8d
    jmp .ci_sp
.ci_sp_fail:
    jmp .dp_code_verbatim        ; operandos inválidos: verbatim total
.ci_sp_end:
    test edx, edx
    jnz .dp_code_verbatim        ; [] desbalanceado: verbatim
    mov dword [rbp-276+AstInstr.nops], 0
    ; op0 = [m+1, c1||n)
    lea ecx, [r11d+1]            ; s0
    cmp r9d, -1
    jne .ci_op0c
    mov edx, r15d
    jmp .ci_op0go
.ci_op0c:
    mov edx, r9d
.ci_op0go:
    cmp ecx, edx
    jae .dp_code_verbatim        ; operando vazio: verbatim
    xor r8d, r8d                 ; opidx=0
    sub rsp, 32
    call .parse_op
    add rsp, 32
    test eax, eax
    jnz .dp_code_verbatim
    inc dword [rbp-276+AstInstr.nops]
    cmp r9d, -1
    je .ci_memrule
    lea ecx, [r9d+1]             ; s1
    cmp r10d, -1
    jne .ci_op1c
    mov edx, r15d
    jmp .ci_op1go
.ci_op1c:
    mov edx, r10d
.ci_op1go:
    cmp ecx, edx
    jae .dp_code_verbatim
    mov r8d, 1
    sub rsp, 32
    call .parse_op
    add rsp, 32
    test eax, eax
    jnz .dp_code_verbatim
    inc dword [rbp-276+AstInstr.nops]
    cmp r10d, -1
    je .ci_memrule
    lea ecx, [r10d+1]            ; s2
    mov edx, r15d
    cmp ecx, edx
    jae .dp_code_verbatim
    mov r8d, 2
    sub rsp, 32
    call .parse_op
    add rsp, 32
    test eax, eax
    jnz .dp_code_verbatim
    inc dword [rbp-276+AstInstr.nops]
    jmp .ci_memrule
.ci_noops:
    mov dword [rbp-276+AstInstr.nops], 0
    jmp .ci_append
.ci_memrule:
    ; MEM size==0 + REG presente -> herda (primeiro REG, exceto SEG-kind).
    ; (r10d/r11d mortos aqui; rdi/r15 intactos.)
    xor r10d, r10d               ; iop
    xor r11d, r11d               ; regsize (0 = nenhum)
.ci_mr:
    cmp r10d, 3
    jae .ci_mr_apply
    mov eax, r10d
    shl eax, 4                   ; *16 (DexOp)
    cmp dword [rbp-276+AstInstr.op0+rax+DexOp.kind], DEX_OP_REG
    jne .ci_mr_nx
    movzx eax, byte [rbp-276+AstInstr.op0+rax+DexOp.size]
    mov r11d, eax
    jmp .ci_mr_apply2
.ci_mr_nx:
    inc r10d
    jmp .ci_mr
.ci_mr_apply2:
    test r11d, r11d
    jz .ci_append
.ci_mr_apply:
    test r11d, r11d
    jz .ci_append
    xor r10d, r10d
.ci_mr_fill:
    cmp r10d, 3
    jae .ci_append
    mov eax, r10d
    shl eax, 4
    cmp dword [rbp-276+AstInstr.op0+rax+DexOp.kind], DEX_OP_MEM
    jne .ci_mr_fnx
    cmp byte [rbp-276+AstInstr.op0+rax+DexOp.size], 0
    jne .ci_mr_fnx
    mov [rbp-276+AstInstr.op0+rax+DexOp.size], r11b
.ci_mr_fnx:
    inc r10d
    jmp .ci_mr_fill
.ci_append:
    ; anexa template ao bloco atual (fetch fresco: sem stale).
    mov eax, [rbp-136]
    imul eax, eax, SIZEOF_FUNC
    mov rcx, [r13+AstUnit.funcs]
    lea rcx, [rcx+rax]           ; func
    mov edx, [rbp-140]
    imul edx, edx, SIZEOF_BLOCK
    mov rax, [rcx+AstFunc.blocks]
    lea rcx, [rax+rdx]           ; block
    lea rdx, [rbp-276]           ; src96
    sub rsp, 32
    call dex_ast_block_instr
    add rsp, 32
    test eax, eax
    jnz .dp_oom
    ; jmp/ret fecham o bloco.
    mov eax, [rbp-276+AstInstr.flags]
    test eax, AST_F_JMP | AST_F_RET
    jz .dp_ret_ok
    mov dword [rbp-140], -1
    jmp .dp_ret_ok

;-----------------------------------------------------------------------------
; .dispatch — r15d=n (linebuf pronto). Processa UMA linha.
; Ret: eax=0 ok | 6 OOM. Label-pendente em pend_ptr/pend_len/has_pend
; ([rbp-120]/[rbp-128]/[rbp-132]): nonzero = válido; toda linha não-vazia
; o consome (código/bloco/dado) ou descarta (diretiva/verbn/alias).
; Preserva rbx,r12-r15 (rdi=linebuf local, salvo; rsi só pad de alinhamento:
; 7 pushes => rsp%16==0, calls internos com sub32).
;-----------------------------------------------------------------------------
.dispatch:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rdi
    push rsi
    mov rdi, [rbp-56]            ; linebuf (estável: sem growth aqui)
    mov eax, [rdi+DexToken.kind] ; tok0.kind (n>=1 garantido)
    cmp eax, LEX_LABEL
    je .dp_label
    cmp eax, LEX_IDENT
    jne .dp_verbatim              ; NUM/LBR/...: diretiva verbatim
    ; IDENT-first: tok0 decide primeiro — bare db/equ e diretivas valem
    ; com qualquer tok1 (ex `bits 64` com NUM, ou `db 0x90` sem label).
    ; (Nenhum mnemônico x64 se chama db/equ/bits/default/section/global/
    ; extern; labels com ':' saem LEX_LABEL, nunca IDENT — sem conflito.)
    mov rcx, [rdi+DexToken.ptr]
    mov rdx, [rdi+DexToken.len]
    lea r8, [rel k_t_db]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .dp_data_bare_db
    mov rcx, [rdi+DexToken.ptr]
    mov rdx, [rdi+DexToken.len]
    lea r8, [rel k_t_equ]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .dp_data_bare_equ
    mov rcx, [rdi+DexToken.ptr]
    mov rdx, [rdi+DexToken.len]
    lea r8, [rel k_t_dir]
    mov r9d, 5
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .dp_directive
    ; Forma labelada (`label db ...` / `label equ ...`) ou código:
    cmp r15d, 2
    jb .dp_code0                  ; 1 token: código (mne sem operandos)
    cmp dword [rdi+40+DexToken.kind], LEX_IDENT
    jne .dp_code0
    mov rcx, [rdi+40+DexToken.ptr]
    mov rdx, [rdi+40+DexToken.len]
    lea r8, [rel k_t_db]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .dp_data_db
    mov rcx, [rdi+40+DexToken.ptr]
    mov rdx, [rdi+40+DexToken.len]
    lea r8, [rel k_t_equ]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .dp_data_equ
    mov rcx, [rdi+DexToken.ptr]
    mov rdx, [rdi+DexToken.len]
    lea r8, [rel k_t_dir]
    mov r9d, 5
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .dp_directive
.dp_code0:
    ; CODE: mne=tok0 (m=0), efflabel=pending (ou nenhum).
    xor r11d, r11d               ; m=0
    mov [rbp-72], r11d           ; spill m (r11 volátil: morre nos calls de
                                 ; abertura func/bloco; [rbp-72] livre aqui —
                                 ; só .lex_line o usa como n local)
    jmp .dp_code
.dp_code_m1:
    mov r11d, 1                  ; resto após LABEL
    mov [rbp-72], r11d           ; spill m (idem acima)
.dp_ret_ok:
    xor eax, eax
    pop rsi
    pop rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.dp_oom:
    mov eax, ERR_OOM
    pop rsi
    pop rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.dp_code:
    ; mne deve ser IDENT (senão: verbatim total).
    mov eax, r11d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_IDENT
    jne .dp_code_verbatim
    ; ---- func ----
    cmp dword [rbp-136], -1      ; cur_func?
    jne .code_havefunc
.code_newfunc:
    cmp dword [rbp-132], 0       ; eff?
    je .code_newfunc_noname
    mov rdx, [rbp-120]
    mov r8, [rbp-128]
    jmp .code_newfunc_go
.code_newfunc_noname:
    xor edx, edx
    xor r8d, r8d
.code_newfunc_go:
    mov rcx, r13                 ; unit
    mov r9, [rbp-104]            ; sect_ptr
    mov rax, [rbp-112]           ; sect_len -> stack (5º arg)
    sub rsp, 48
    mov [rsp+32], rax
    call dex_ast_unit_func
    add rsp, 48
    cmp eax, -1
    je .dp_oom
    mov [rbp-136], eax           ; cur_func
    mov dword [rbp-140], -1      ; cur_block=closed
    jmp .code_block
.code_havefunc:
    cmp dword [rbp-132], 0       ; eff?
    je .code_block               ; sem eff: segue (abre se fechado)
    ; eff == nome do func atual (recursão)? -> só bloco novo.
    mov eax, [rbp-136]
    imul eax, eax, SIZEOF_FUNC
    mov rdx, [r13+AstUnit.funcs]
    lea rdx, [rdx+rax]           ; func
    mov r8, [rdx+AstFunc.name_ptr]
    test r8, r8
    jz .code_ckcall              ; func anônimo: eff nunca é "seu nome"
    mov r9, [rdx+AstFunc.name_len]
    mov rcx, [rbp-120]           ; eff_ptr
    mov rdx, [rbp-128]           ; eff_len
    sub rsp, 32
    call .name_eq                ; (rcx,rdx,r8,r9) -> eax
    add rsp, 32
    test eax, eax
    jnz .code_block_new          ; recursão: só bloco novo
.code_ckcall:
    ; eff ∈ callset? (linear; nomes exatos case-sensitive)
    mov rcx, [rbp-120]
    mov rdx, [rbp-128]
    sub rsp, 32
    call .in_callset
    add rsp, 32
    test eax, eax
    jz .code_block_new
    ; novo func: fecha atual e reabre
    mov dword [rbp-136], -1
    mov dword [rbp-140], -1
    jmp .code_newfunc
.code_block_new:
    mov dword [rbp-140], -1      ; fecha bloco atual
    jmp .code_block
.code_block:
    cmp dword [rbp-140], 0
    jge .code_hasblock
    ; abre bloco (label=eff ou nenhum)
    cmp dword [rbp-132], 0
    je .code_block_noname
    mov rdx, [rbp-120]
    mov r8, [rbp-128]
    jmp .code_block_go
.code_block_noname:
    xor edx, edx
    xor r8d, r8d
.code_block_go:
    mov eax, [rbp-136]
    imul eax, eax, SIZEOF_FUNC
    mov rcx, [r13+AstUnit.funcs]
    lea rcx, [rcx+rax]           ; func
    sub rsp, 32
    call dex_ast_func_block
    add rsp, 32
    cmp eax, -1
    je .dp_oom
    mov [rbp-140], eax           ; cur_block
.code_hasblock:
    mov dword [rbp-132], 0       ; eff consumido
    mov r11d, [rbp-72]           ; restaura m (spill de .dp_code0/.dp_code_m1)
    jmp .code_instr
.dp_code_verbatim:
    ; Linha-código inválida -> AstData(DIR) verbatim da linha toda.
    mov dword [rbp-132], 0
    mov r10d, AST_DATA_DIR
    xor r8d, r8d
    xor r9d, r9d
    jmp .dp_data_emit
.dp_label:
    ; efflabel = tok0 (inline vence; pending antigo descartado).
    mov rax, [rdi+DexToken.ptr]
    mov [rbp-120], rax
    mov rax, [rdi+DexToken.len]
    mov [rbp-128], rax
    mov dword [rbp-132], 1
    cmp r15d, 1
    je .dp_ok                     ; só label: pendura p/ próxima
    jmp .dp_code_m1               ; resto a partir de tok1
.dp_ok:
    xor eax, eax
    pop rsi
    pop rdi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.dp_verbatim:
    mov dword [rbp-132], 0       ; pending some
    jmp .dp_span_dir
.dp_data_db:
    mov r10d, AST_DATA_DB
    jmp .dp_data_go
.dp_data_equ:
    mov r10d, AST_DATA_EQU
    jmp .dp_data_go
.dp_data_bare_db:
    mov r10d, AST_DATA_DB
    jmp .dp_data_bare
.dp_data_bare_equ:
    mov r10d, AST_DATA_EQU
.dp_data_bare:
    ; Bare db/equ (tok0 é a keyword, ex `db 0x90` do emissor): sem label,
    ; pending descartado (mesma regra das diretivas).
    mov dword [rbp-132], 0
    xor r8d, r8d
    xor r9d, r9d
    jmp .dp_data_emit
.dp_data_go:
    ; AstData(kind=r10d, label=tok0, span=linha, sect=cur). Inline vence.
    mov dword [rbp-132], 0
    jmp .dp_data_mk
.dp_directive:
    mov dword [rbp-132], 0       ; pending some
    jmp .dp_span_dir

;-----------------------------------------------------------------------------
; Corpos de emissão. Entrada: r10d=kind; label em (r8=ptr, r9=len) ou
; (0,0); rdi=linebuf, r15d=n. r14(pos) e rbx/r12/r13/r15 intactos.
; .dp_data_emit monta AstData em instr_tmp (scratch, 96B) e anexa.
; Ret: eax=0 ok | 6 OOM (pops + ret do dispatch).
;-----------------------------------------------------------------------------
.dp_span_dir:
    ; `section X`? atualiza cur_sect (nome=tok1 IDENT ou vazio).
    mov rcx, [rdi+DexToken.ptr]
    mov rdx, [rdi+DexToken.len]
    lea r8, [rel k_t_section]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    js .dp_dir_kind
    cmp r15d, 2
    jb .dp_dir_noname
    cmp dword [rdi+40+DexToken.kind], LEX_IDENT
    jne .dp_dir_noname
    mov rax, [rdi+40+DexToken.ptr]
    mov [rbp-104], rax
    mov rax, [rdi+40+DexToken.len]
    mov [rbp-112], rax
    jmp .dp_dir_kind
.dp_dir_noname:
    mov qword [rbp-104], 0
    mov qword [rbp-112], 0
.dp_dir_kind:
    mov r10d, AST_DATA_DIR
    xor r8d, r8d                 ; sem label
    xor r9d, r9d
    jmp .dp_data_emit
.dp_data_mk:
    ; kind=r10d, label=tok0 (r8/r9 já com tok0? NÃO — recarrega aqui).
    mov r8, [rdi+DexToken.ptr]
    mov r9, [rdi+DexToken.len]
    jmp .dp_data_emit
.dp_data_emit:
    lea rax, [rbp-276]           ; tmp (instr_tmp, 96B; usa 56)
    mov [rax+AstData.kind], r10d
    mov dword [rax+AstData.padk], 0
    mov [rax+AstData.label_ptr], r8
    mov [rax+AstData.label_len], r9
    ; span = [tok0.ptr, tok[n-1].end)
    mov rcx, [rdi+DexToken.ptr]
    mov [rax+AstData.span_ptr], rcx
    mov ecx, r15d
    imul ecx, ecx, SIZEOF_TOKEN
    lea rcx, [rdi+rcx-40]        ; &tok[n-1]
    mov rdx, [rcx+DexToken.ptr]
    add rdx, [rcx+DexToken.len]  ; end
    sub rdx, [rax+AstData.span_ptr]
    mov [rax+AstData.span_len], rdx
    mov rcx, [rbp-104]
    mov [rax+AstData.sect_ptr], rcx
    mov rcx, [rbp-112]
    mov [rax+AstData.sect_len], rcx
    mov rcx, r13                 ; unit
    mov rdx, rax                 ; src56
    sub rsp, 32
    call dex_ast_unit_data
    add rsp, 32
    test eax, eax
    jnz .dp_oom
    jmp .dp_ret_ok

;-----------------------------------------------------------------------------
; .lex_line — lexe UMA linha p/ linebuf. Ret: eax=ntoks (≥0) | -1 OOM.
; Avança r14. Pula COMMENTs (não armazena). Para após EOL (consumido) / EOF.
; Preserva rbx,r12-r15 (usa rax,rcx,rdx,r8-r11 + frame).
;-----------------------------------------------------------------------------
.lex_line:
    push rbx                     ; 1 push: alinha (entry 8 -> 0) p/ calls
    mov dword [rbp-72], 0        ; n=0
.ll_l:
    cmp r14, r12
    jae .ll_e
    mov rcx, rbx
    mov rdx, r12
    mov r8, r14
    lea r9, [rbp-180]            ; tok_tmp
    sub rsp, 32
    call dex_lex_one
    add rsp, 32
    test rax, rax
    jz .ll_e                     ; defensivo (pos<len sempre consome)
    add r14, rax
    mov eax, [rbp-180+DexToken.kind]
    cmp eax, LEX_EOL
    je .ll_eol
    cmp eax, LEX_COMMENT
    je .ll_l                     ; pula comentário
    ; armazena (grow se n==cap)
    mov ecx, [rbp-72]            ; n
    cmp ecx, [rbp-64]            ; vs cap
    jb .ll_store
    mov eax, [rbp-64]
    imul rax, rax, 40            ; old_bytes (cap=0 -> 0)
    mov rdx, rax
    mov ecx, [rbp-72]
    inc rcx
    imul rcx, rcx, 40            ; min=(n+1)*40
    mov r8, rcx
    mov rcx, [rbp-56]            ; old
    sub rsp, 32
    call dex_realloc_grow        ; rax=new, rdx=new_bytes
    add rsp, 32
    test rax, rax
    jz .ll_oom
    mov [rbp-56], rax
    mov rax, rdx                 ; new_cap (bytes)
    xor edx, edx
    mov ecx, 40
    div rcx                      ; elems (new>=min: progresso)
    mov [rbp-64], eax
.ll_store:
    mov eax, [rbp-72]
    imul rax, rax, 40
    mov rdx, [rbp-56]
    lea rdx, [rdx+rax]           ; dst
    mov rax, [rbp-180+0]
    mov [rdx+0], rax
    mov rax, [rbp-180+8]
    mov [rdx+8], rax
    mov rax, [rbp-180+16]
    mov [rdx+16], rax
    mov rax, [rbp-180+24]
    mov [rdx+24], rax
    mov rax, [rbp-180+32]
    mov [rdx+32], rax
    inc dword [rbp-72]
    jmp .ll_l
.ll_eol:
    mov eax, [rbp-72]
    pop rbx
    ret
.ll_e:
    mov eax, [rbp-72]
    pop rbx
    ret
.ll_oom:
    mov eax, -1
    pop rbx
    ret

;-----------------------------------------------------------------------------
; .parse_op — rcx=s, rdx=e (idxs em linebuf), r8d=opidx -> eax=0 ok | 1 fail.
; Preenche DexOp em instr_tmp + tname (first-wins). Preserva rbx,rdi,rsi,
; r8-r15 (push r12,r8-r11; usa-os + rax,rcx,rdx). rdi=linebuf (só leitura).
; .tok(i): lea rax,[rdi+i*40] (inline).
;-----------------------------------------------------------------------------
.parse_op:
    push r12
    push r8
    push r9
    push r10
    push r11
    mov r12d, r8d                ; opidx (salvo; r8 livre adiante)
    mov r10d, ecx                ; s
    mov r11d, edx                ; e
    mov eax, r12d
    shl eax, 4                   ; opidx*16
    lea r8, [rbp-276+AstInstr.op0]
    add r8, rax                  ; r8 = &DexOp destino
    mov eax, r11d
    sub eax, r10d                ; len = e-s
    test eax, eax
    jz .po_fail                  ; vazio
    cmp eax, 1
    jne .po_multi
    ; ---- len==1 ----
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    lea rax, [rdi+rax]           ; tok
    mov ecx, [rax+DexToken.kind]
    cmp ecx, LEX_REG
    je .po_reg
    cmp ecx, LEX_NUM
    je .po_imm1
    cmp ecx, LEX_IDENT
    je .po_rel
    jmp .po_fail
.po_reg:
    mov rcx, [rax+DexToken.val]  ; packed
    test rcx, LEX_REG_SEG
    jnz .po_regseg
    mov byte [r8+DexOp.kind], DEX_OP_REG
    mov edx, ecx
    and edx, 0xFF
    mov [r8+DexOp.reg], dl       ; (hi perde marcador: documentado)
    mov edx, ecx
    shr edx, 8
    and edx, 0xFF
    mov [r8+DexOp.size], dl
    jmp .po_ok
.po_regseg:
    mov byte [r8+DexOp.kind], DEX_OP_SEG
    mov edx, ecx
    and edx, 0xFF
    mov [r8+DexOp.reg], dl
    mov byte [r8+DexOp.size], 2
    jmp .po_ok
.po_imm1:
    mov byte [r8+DexOp.kind], DEX_OP_IMM
    mov rcx, [rax+DexToken.val]
    mov [r8+DexOp.val], rcx
    cmp rcx, 0xFF
    jbe .po_im1
    cmp rcx, 0xFFFF
    jbe .po_im2
    mov rax, rcx
    shr rax, 32                  ; alto !=0? precisa 8 bytes
    jnz .po_im8b
    mov byte [r8+DexOp.size], 4
    jmp .po_ok
.po_im8b:
    mov byte [r8+DexOp.size], 8
    jmp .po_ok
.po_im1:
    mov byte [r8+DexOp.size], 1
    jmp .po_ok
.po_im2:
    mov byte [r8+DexOp.size], 2
    jmp .po_ok
.po_rel:
    mov byte [r8+DexOp.kind], DEX_OP_REL
    mov qword [r8+DexOp.val], 0   ; alvo via tname (Pass C resolve)
    cmp qword [rbp-276+AstInstr.tname_ptr], 0
    jne .po_ok                   ; first-wins (já tem)
    mov rcx, [rax+DexToken.ptr]
    mov [rbp-276+AstInstr.tname_ptr], rcx
    mov rcx, [rax+DexToken.len]
    mov [rbp-276+AstInstr.tname_len], rcx
    jmp .po_ok
.po_multi:
    jmp .po_multi_real
.po_ok:
    xor eax, eax
    pop r11
    pop r10
    pop r9
    pop r8
    pop r12
    ret
.po_fail:
    mov eax, 1
    pop r11
    pop r10
    pop r9
    pop r8
    pop r12
    ret

;-----------------------------------------------------------------------------
; .po_multi_real — r10d=s, r11d=e (idxs, pushed: sobrevivem a matcher).
; r12=&op (estável: matcher não toca r12). rdi=linebuf (só leitura).
; ecx=memsize (matcher preserva ecx: só o lê como... NÃO — matcher USA
; ecx como ptr param! memsize vive no TEMPLATE ([op+size], escrito ao
; achar; fail descarta). Zero no template (zerado no início) = nenhum.
; Demais: rax,rdx,r8,r9 scratch (r8/r9 pushed: restaurar? pops no fim
; restauram p/ chamador; uso livre aqui dentro).
; Fluxo: strip sizes -> [LBR..RBR]? MEM : imm-com-marcadores.
;-----------------------------------------------------------------------------
.po_multi_real:
    ; r12 = &op (recalcula; r12d=opidx ainda válido aqui? r12d foi opidx
    ; no prólogo e NADA o escreveu desde (só leitura? `mov r12d, r8d` no
    ; prólogo; depois só `lea r8`... r12 INTACTO desde o prólogo ✓).
    mov eax, r12d
    shl eax, 4
    lea r12, [rbp-276+AstInstr.op0+rax] ; r12=&op (estável daqui em diante)
    mov eax, r10d                ; i=s
.pm_strip:
    cmp eax, r11d
    jae .pm_stripped
    push rax                     ; spill i (matcher usa rax de retorno!)
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_IDENT
    jne .pm_strip_no
    ; matcher t_size no tok[i] (i no topo da pilha; params fresh)
    pop rax                      ; i (descarta kind check feito)
    push rax
    imul eax, eax, SIZEOF_TOKEN
    lea rax, [rdi+rax]
    mov rcx, [rax+DexToken.ptr]
    mov rdx, [rax+DexToken.len]
    lea r8, [rel k_t_size]
    mov r9d, 4
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    js .pm_strip_popno           ; sem match: fim do strip
    mov ecx, eax
    mov eax, 1
    shl eax, cl                   ; size = 1<<idx
    mov [r12+DexOp.size], al      ; (último vale: sobrescreve)
    pop rax
    inc eax                       ; consome o marcador
    mov r10d, eax                 ; s avança (strip!)
    jmp .pm_strip
.pm_strip_no:
    pop rax
.pm_stripped:
    mov r10d, eax                ; s' (pós-strip)
    cmp r10d, r11d
    jae .po_fail                  ; só marcadores, sem operando
    ; bracket? tok[s]==LBR && tok[e-1]==RBR?
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_LBR
    jne .pm_imm
    mov eax, r11d
    dec eax
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_RBR
    jne .pm_imm
    jmp .pm_mem
.pm_strip_popno:
    pop rax
    jmp .pm_stripped              ; (s não avançou: r10d intacto)
    ; (fim do strip; r10d=s' pós-strip, r11d=e; [op+size]=marcador|0)

;-----------------------------------------------------------------------------
; .pm_imm — [s,e) sem brackets: [strict|size]* [+-]?NUM (exatamente 1 NUM).
; r10d=s, r11d=e, r12=&op. Pass 1 (sem calls): valida kinds + acha NUM.
; Pass 2: strict pula, size atualiza [op+size], sinal prefixado ao NUM faz
; fold (MINUS nega o val; PLUS nada). Usa rax,rcx,rdx,r8,r9
; (r8/r9 pushed: restaura!). r10d/r11d/r12 intactos (matcher os preserva).
;-----------------------------------------------------------------------------
.pm_imm:
    xor r8d, r8d                 ; nnums
    xor r9d, r9d                 ; nidx (-1 = nenhum; usa r9d com -1 sentinel)
    dec r9d
    mov eax, r10d                ; i
.pm_ip1:
    cmp eax, r11d
    jae .pm_ip1e
    push rax
    imul eax, eax, SIZEOF_TOKEN
    mov ecx, [rdi+rax+DexToken.kind]
    pop rax
    cmp ecx, LEX_NUM
    je .pm_ip1n
    cmp ecx, LEX_IDENT
    je .pm_ip1nx
    cmp ecx, LEX_PLUS
    je .pm_ip1nx                  ; sinal: posição validada no pass 2
    cmp ecx, LEX_MINUS
    je .pm_ip1nx
    jmp .po_fail
.pm_ip1nx:
    inc eax
    jmp .pm_ip1
.pm_ip1n:
    inc r8d
    cmp r8d, 1
    ja .po_fail                  ; 2 NUMs
    mov r9d, eax                 ; nidx
    inc eax
    jmp .pm_ip1
.pm_ip1e:
    cmp r8d, 1
    jne .po_fail                  ; 0 NUMs (só marcadores)
    ; immval = tok[nidx].val
    mov eax, r9d
    imul eax, eax, SIZEOF_TOKEN
    mov rdx, [rdi+rax+DexToken.val]
    mov [r12+DexOp.val], rdx
    mov byte [r12+DexOp.kind], DEX_OP_IMM
    ; pass 2: valida IDENTs (strict|size); size atualiza [op+size].
    mov eax, r10d
.pm_ip2:
    cmp eax, r11d
    jae .pm_idone
    push rax
    imul eax, eax, SIZEOF_TOKEN
    mov ecx, [rdi+rax+DexToken.kind]
    pop rax
    cmp ecx, LEX_NUM
    je .pm_ip2nx                  ; o NUM: ok
    cmp ecx, LEX_MINUS
    je .pm_isign
    cmp ecx, LEX_PLUS
    je .pm_isign
    ; IDENT: strict? size? (um spill p/ saídas; matcher preserva a pilha)
    push rax                     ; spill i
    imul eax, eax, SIZEOF_TOKEN
    lea rax, [rdi+rax]
    mov rcx, [rax+DexToken.ptr]
    mov rdx, [rax+DexToken.len]
    lea r8, [rel k_t_strict]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .pm_is_ok                 ; strict: pula
    mov eax, [rsp]               ; i (sem pop!)
    imul eax, eax, SIZEOF_TOKEN
    lea rax, [rdi+rax]
    mov rcx, [rax+DexToken.ptr]
    mov rdx, [rax+DexToken.len]
    lea r8, [rel k_t_size]
    mov r9d, 4
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    js .pm_ip2_notsize           ; nem strict nem size
    mov ecx, eax                 ; idx
    mov eax, 1
    shl eax, cl                   ; size = 1<<idx
    mov [r12+DexOp.size], al      ; (último vale)
    pop rax                      ; i
    inc eax
    jmp .pm_ip2
.pm_ip2_notsize:
    pop rax                      ; i (descarta; pilha limpa p/ .po_fail)
    jmp .po_fail
.pm_isign:
    ; Sinal (ecx=MINUS/PLUS, eax=i): exige tok[i+1]==NUM (prefixa o único
    ; NUM; `--5`/`- x` caem aqui e falham: o 1º não precede NUM). MINUS faz
    ; fold imediato no val (já carregado no ip1e); dimensionamento em
    ; .pm_idone usa a magnitude.
    push rcx                     ; kind (MINUS? nega)
    lea ecx, [eax+1]
    cmp ecx, r11d
    jae .pm_isign_fail
    imul ecx, ecx, SIZEOF_TOKEN
    cmp dword [rdi+rcx+DexToken.kind], LEX_NUM
    jne .pm_isign_fail
    pop rcx
    cmp ecx, LEX_MINUS
    jne .pm_ip2nx                 ; PLUS: só valida
    neg qword [r12+DexOp.val]
    jmp .pm_ip2nx
.pm_isign_fail:
    pop rcx
    jmp .po_fail
.pm_is_ok:
    pop rax                      ; i
.pm_ip2nx:
    inc eax
    jmp .pm_ip2
.pm_idone:
    cmp byte [r12+DexOp.size], 0
    jne .po_ok
    mov rdx, [r12+DexOp.val]
    test rdx, rdx
    jns .pm_isz
    neg rdx                      ; negativo: dimensiona pela magnitude
.pm_isz:
    cmp rdx, 0xFF
    jbe .pm_isz1
    cmp rdx, 0xFFFF
    jbe .pm_isz2
    mov rax, rdx
    shr rax, 32
    jnz .pm_isz8
    mov byte [r12+DexOp.size], 4
    jmp .po_ok
.pm_isz1:
    mov byte [r12+DexOp.size], 1
    jmp .po_ok
.pm_isz2:
    mov byte [r12+DexOp.size], 2
    jmp .po_ok
.pm_isz8:
    mov byte [r12+DexOp.size], 8
    jmp .po_ok

;-----------------------------------------------------------------------------
; .pm_mem — operando [s,e) com brackets (LBR..RBR já validados).
; r10d=s, r11d=e, r12=&op. Formas: [rel NOME], [abs NUM], ou
; [seg:base+idx*esc±disp]. Usa rax,rcx,rdx,r8,r9 (pushed: restaura!).
; Sem calls no loop geral (seg via flag do token); rel/abs usam matcher.
;-----------------------------------------------------------------------------
.pm_mem:
    ; inner: a=r10d=s+1, b=r11d=e-1 (r10d/r11d pushed: sobrevivem a matcher;
    ; r8/r9 = scratch por call). r12=&op (matcher não toca r12).
    mov eax, r10d
    inc eax
    mov edx, r11d
    dec edx
    mov r10d, eax                  ; a
    mov r11d, edx                  ; b
    cmp r10d, r11d
    jae .po_fail                   ; `[]`
    ; tok[a]==IDENT? (rel|abs ou fail no geral)
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_IDENT
    jne .pm_mgen
    lea rax, [rdi+rax]
    mov rcx, [rax+DexToken.ptr]
    mov rdx, [rax+DexToken.len]
    lea r8, [rel k_t_rel]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .pm_mrel
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    lea rax, [rdi+rax]
    mov rcx, [rax+DexToken.ptr]
    mov rdx, [rax+DexToken.len]
    lea r8, [rel k_t_abs]
    mov r9d, 1
    sub rsp, 32
    call dex_lex_match
    add rsp, 32
    test rax, rax
    jns .pm_mabs
    jmp .pm_mgen                   ; IDENT comum: geral falha (total)
.pm_mrel:
    ; exige [rel, NOME] exato: b==a+2 e IDENT.
    mov eax, r10d
    add eax, 2
    cmp eax, r11d
    jne .po_fail
    mov eax, r10d
    inc eax
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_IDENT
    jne .po_fail
    mov byte [r12+DexOp.kind], DEX_OP_MEM
    mov byte [r12+DexOp.base], DEX_NOBASE
    mov byte [r12+DexOp.index], DEX_NOINDEX
    mov byte [r12+DexOp.scale], 1
    mov qword [r12+DexOp.val], 0   ; alvo via tname
    cmp qword [rbp-276+AstInstr.tname_ptr], 0
    jne .po_ok                     ; first-wins
    mov eax, r10d
    inc eax
    imul eax, eax, SIZEOF_TOKEN
    lea rax, [rdi+rax]
    mov rcx, [rax+DexToken.ptr]
    mov [rbp-276+AstInstr.tname_ptr], rcx
    mov rcx, [rax+DexToken.len]
    mov [rbp-276+AstInstr.tname_len], rcx
    jmp .po_ok
.pm_mabs:
    ; exige [abs, NUM] exato.
    mov eax, r10d
    add eax, 2
    cmp eax, r11d
    jne .po_fail
    mov eax, r10d
    inc eax
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_NUM
    jne .po_fail
    mov rcx, [rdi+rax+DexToken.val]
    mov byte [r12+DexOp.kind], DEX_OP_MEM
    mov byte [r12+DexOp.base], DEX_NOBASE
    mov byte [r12+DexOp.index], DEX_NOINDEX
    mov byte [r12+DexOp.scale], 1
    mov [r12+DexOp.val], rcx       ; disp absoluto (low32 na emissão)
    jmp .po_ok
.pm_mgen:
    ; geral: [seg:] base [[+|-] termo]* (termo = REG[idx[*esc]] | NUM[disp]).
    ; r10d=a, r11d=b. Stores DIRETOS no template (fail descarta):
    ; kind=MEM já aqui; base/index/scale/seg/val conforme parseia.
    ; dh=dispset (0/1). Sem calls: regs livres.
    mov byte [r12+DexOp.kind], DEX_OP_MEM
    mov byte [r12+DexOp.index], DEX_NOINDEX
    mov byte [r12+DexOp.scale], 1
    xor edx, edx                   ; dh=dispset 0 (dl=base adiante)
    ; seg? REG+SEG seguido de COLON.
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_REG
    jne .pm_mbase
    mov rax, [rdi+rax+DexToken.val]
    test rax, LEX_REG_SEG
    jz .pm_mbase
    and eax, 0xFF
    mov [r12+DexOp.seg], al
    inc r10d
    cmp r10d, r11d
    jae .po_fail                   ; seg sem resto
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_COLON
    jne .po_fail
    inc r10d
.pm_mbase:
    cmp r10d, r11d
    jae .po_fail
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_REG
    jne .po_fail
    mov rax, [rdi+rax+DexToken.val]
    test rax, LEX_REG_SEG
    jnz .po_fail                   ; seg como base
    and eax, 0xFF
    mov [r12+DexOp.base], al
    inc r10d
.pm_mloop:
    cmp r10d, r11d
    jae .po_ok                     ; fim: MEM pronto
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    mov eax, [rdi+rax+DexToken.kind]
    cmp eax, LEX_PLUS
    je .pm_mplus
    cmp eax, LEX_MINUS
    jne .po_fail
    mov dl, 1                      ; sign=- (dl livre: base já no template)
    jmp .pm_mterm
.pm_mplus:
    mov dl, 0                      ; sign=+
.pm_mterm:
    inc r10d
    cmp r10d, r11d
    jae .po_fail                   ; sinal sem termo
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    lea rax, [rdi+rax]             ; tok
    mov ecx, [rax+DexToken.kind]
    cmp ecx, LEX_REG
    je .pm_mreg
    cmp ecx, LEX_NUM
    je .pm_mnum
    jmp .po_fail
.pm_mreg:
    mov rcx, [rax+DexToken.val]
    test rcx, LEX_REG_SEG
    jnz .po_fail                   ; seg como índice
    cmp byte [r12+DexOp.index], DEX_NOINDEX
    jne .po_fail                   ; 2º índice
    and ecx, 0xFF
    mov [r12+DexOp.index], cl
    inc r10d
    cmp r10d, r11d
    jae .pm_mloop_end              ; sem escala: scale=1 (default)
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_STAR
    jne .pm_mloop
    inc r10d
    cmp r10d, r11d
    jae .po_fail                   ; `*` sem fator
    mov eax, r10d
    imul eax, eax, SIZEOF_TOKEN
    cmp dword [rdi+rax+DexToken.kind], LEX_NUM
    jne .po_fail
    mov rax, [rdi+rax+DexToken.val]
    cmp rax, 1
    je .pm_msc
    cmp rax, 2
    je .pm_msc
    cmp rax, 4
    je .pm_msc
    cmp rax, 8
    jne .po_fail
.pm_msc:
    mov [r12+DexOp.scale], al
    inc r10d
    jmp .pm_mloop
.pm_mloop_end:
    mov byte [r12+DexOp.scale], 1
    jmp .pm_mloop
.pm_mnum:
    cmp dh, 0                      ; dispset? (init 0 na entrada geral)
    jne .po_fail                   ; 2º disp
    mov rax, [rax+DexToken.val]    ; (rax=&tok aqui!)
    test dl, dl                    ; sign (0=+, 1=-)
    jz .pm_mpos
    neg rax
.pm_mpos:
    mov [r12+DexOp.val], rax
    mov dh, 1
    inc r10d
    jmp .pm_mloop

;-----------------------------------------------------------------------------
; .name_eq — rcx=aptr, rdx=alen, r8=bptr, r9=blen -> eax=1 iguais | 0.
; Exato (labels: case-sensitive). Preserva tudo exceto rax (sub rsp,40).
;-----------------------------------------------------------------------------
.name_eq:
    cmp rdx, r9
    jne .ne_no
    xchg rdx, r8                 ; rdx=bptr, r8=alen
    sub rsp, 40
    call dex_memcmp
    add rsp, 40
    test eax, eax
    jnz .ne_no
    mov eax, 1
    ret
.ne_no:
    xor eax, eax
    ret

;-----------------------------------------------------------------------------
; .in_callset — rcx=ptr, rdx=len -> eax=1 se está na calltab | 0.
; Preserva rbx,r12-r15 (push r10,rbx,rsi).
;-----------------------------------------------------------------------------
.in_callset:
    push r10
    push rbx
    push rsi
    mov rbx, rcx                 ; query ptr (preservado: só leitura adiante)
    mov rsi, rdx                 ; query len
    xor r10d, r10d               ; i
.ics_l:
    cmp r10d, [rbp-96]           ; calln
    jae .ics_no
    mov eax, r10d
    shl rax, 4                   ; *16
    mov rdx, [rbp-80]            ; calltab
    lea rdx, [rdx+rax]           ; entry
    mov r8, [rdx]                ; eptr
    mov r9, [rdx+8]              ; elen
    mov rcx, rbx
    mov rdx, rsi
    sub rsp, 32
    call .name_eq
    add rsp, 32
    test eax, eax
    jnz .ics_yes
    inc r10d
    jmp .ics_l
.ics_yes:
    mov eax, 1
    pop rsi
    pop rbx
    pop r10
    ret
.ics_no:
    xor eax, eax
    pop rsi
    pop rbx
    pop r10
    ret

;-----------------------------------------------------------------------------
; .find_block — rcx=name_ptr, rdx=name_len -> rax=(f<<32)|b | -1.
; Busca global (funcs em ordem, blocos em ordem; exato case-sensitive).
; Preserva rbx,r12-r15 (push r10,r11,rbx,rsi,rdi; query em rbx/rsi).
; 5 pushes => calls internos com sub32.
;-----------------------------------------------------------------------------
.find_block:
    push r10
    push r11
    push rbx
    push rsi
    push rdi                     ; pad de alinhamento (não usado)
    mov rbx, rcx                 ; query ptr (pushed: sobrevive)
    mov rsi, rdx                 ; query len
    xor r10d, r10d               ; fi
.fb_f:
    cmp r10d, [r13+AstUnit.nfuncs]
    jae .fb_no
    xor r11d, r11d               ; bi
.fb_b:
    mov eax, r10d
    imul eax, eax, SIZEOF_FUNC
    mov rdx, [r13+AstUnit.funcs]
    lea rdx, [rdx+rax]           ; func
    cmp r11d, [rdx+AstFunc.nblocks]
    jae .fb_fnext
    mov eax, r11d
    imul eax, eax, SIZEOF_BLOCK
    mov rcx, [rdx+AstFunc.blocks]
    lea rax, [rcx+rax]           ; block
    mov rcx, [rax+AstBlock.label_ptr]
    test rcx, rcx
    jz .fb_bnext                 ; sem label: nunca casa
    mov rdx, [rax+AstBlock.label_len]
    mov r8, rcx                  ; (cand vai p/ r8/r9 abaixo; query p/ rcx/rdx)
    mov r9, rdx
    mov rcx, rbx
    mov rdx, rsi
    sub rsp, 40
    call .name_eq
    add rsp, 40
    test eax, eax
    jz .fb_bnext
    mov eax, r10d
    shl rax, 32
    or rax, r11
    pop rdi
    pop rsi
    pop rbx
    pop r11
    pop r10
    ret
.fb_bnext:
    inc r11d
    jmp .fb_b
.fb_fnext:
    inc r10d
    jmp .fb_f
.fb_no:
    mov rax, -1
    pop rdi
    pop rsi
    pop rbx
    pop r11
    pop r10
    ret

;-----------------------------------------------------------------------------
; .resolve — Pass C: tidx por tname + succs por bloco. Preserva
; rbx,r13 (r13=unit, nunca escrito; rbx intocado). Usa r12d=fi,
; r14d=bi, r15d=ii (pushed) + rax,rcx,rdx,r8-r11 (r10/r11 morrem em
; realloc — só como scratch sem calls... block_succ CHAMA (realloc!):
; idxs ficam em r12d/r14d/r15d (não-voláteis, salvos) ✓; ptrs SEMPRE
; recalculados (arrays podem mover).
; Ret: eax=0 ok | 6 OOM.
;-----------------------------------------------------------------------------
.resolve:
    push rbx
    push r12
    push r14
    push r15
    push rdi                     ; 5 pushes (pad: calls internos sub32)
    xor r12d, r12d               ; fi
.rs_f:
    cmp r12d, [r13+AstUnit.nfuncs]
    jae .rs_ok
    xor r14d, r14d               ; bi
.rs_b:
    mov eax, r12d
    imul eax, eax, SIZEOF_FUNC
    mov rdx, [r13+AstUnit.funcs]
    lea rdx, [rdx+rax]           ; func
    cmp r14d, [rdx+AstFunc.nblocks]
    jae .rs_fnext
    ; -- instrs: resolve tname->tidx; emite succs de controle --
    xor r15d, r15d               ; ii
.rs_i:
    mov eax, r12d
    imul eax, eax, SIZEOF_FUNC
    mov rdx, [r13+AstUnit.funcs]
    lea rdx, [rdx+rax]           ; func
    mov eax, r14d
    imul eax, eax, SIZEOF_BLOCK
    mov rcx, [rdx+AstFunc.blocks]
    lea rcx, [rcx+rax]           ; block
    cmp r15d, [rcx+AstBlock.ninstrs]
    jae .rs_fall
    mov eax, r15d
    imul eax, eax, SIZEOF_INSTR
    mov rdx, [rcx+AstBlock.instrs]
    lea rdx, [rdx+rax]           ; instr (rdx scratch? rdx morto aqui? SIM:
    mov rbx, rdx                 ;  instr em rbx (pushed! sobrevive calls))
    cmp qword [rbx+AstInstr.tname_ptr], 0
    je .rs_succ
    mov rcx, [rbx+AstInstr.tname_ptr]
    mov rdx, [rbx+AstInstr.tname_len]
    sub rsp, 32
    call .find_block
    add rsp, 32
    mov [rbx+AstInstr.tidx], rax  ; (-1 se externo/irresoluto)
    ; (rbx sobreviveu? find_block preserva rbx (pushed lá) ✓)
.rs_succ:
    mov eax, [rbx+AstInstr.flags]
    test eax, AST_F_CALL | AST_F_BRANCH | AST_F_JMP
    jz .rs_inext
    test eax, AST_F_CALL
    jz .rs_ncall
    mov r10d, AST_SUCC_CALL
    jmp .rs_skind
.rs_ncall:
    test eax, AST_F_BRANCH
    jz .rs_nbranch
    mov r10d, AST_SUCC_BRANCH
    jmp .rs_skind
.rs_nbranch:
    mov r10d, AST_SUCC_JMP
.rs_skind:
    ; block* fresco (instrs[]/blocks[] estáveis aqui? succ-add move só
    ; succs[] — mas refetch barato e imune: refaz tudo).
    mov eax, r12d
    imul eax, eax, SIZEOF_FUNC
    mov rcx, [r13+AstUnit.funcs]
    lea rcx, [rcx+rax]           ; func
    mov eax, r14d
    imul eax, eax, SIZEOF_BLOCK
    mov rdx, [rcx+AstFunc.blocks]
    lea rcx, [rdx+rax]           ; block
    mov edx, r10d                ; kind (mov r64,r32 não existe: r32 zera)
    mov r8, [rbx+AstInstr.tidx]
    mov r9, [rbx+AstInstr.tname_ptr]
    mov rax, [rbx+AstInstr.tname_len]
    sub rsp, 48
    mov [rsp+32], rax            ; 5º arg
    call dex_ast_block_succ
    add rsp, 48
    test eax, eax
    jnz .rs_oom
.rs_inext:
    inc r15d
    jmp .rs_i
.rs_fall:
    ; FALL se último não é jmp/ret e há próximo bloco.
    ; r11d=nblocks (scratch local; sem calls até o succ call).
    mov eax, r12d
    imul eax, eax, SIZEOF_FUNC
    mov rdx, [r13+AstUnit.funcs]
    lea rdx, [rdx+rax]           ; func
    mov r11d, [rdx+AstFunc.nblocks]
    mov eax, r14d
    imul eax, eax, SIZEOF_BLOCK
    mov rcx, [rdx+AstFunc.blocks]
    lea rcx, [rcx+rax]           ; block
    mov edx, [rcx+AstBlock.ninstrs]
    test edx, edx
    jz .rs_fallemit              ; vazio: transparente p/ próximo
    dec edx
    imul edx, edx, SIZEOF_INSTR
    mov rax, [rcx+AstBlock.instrs]
    mov eax, [rax+rdx+AstInstr.flags]
    test eax, AST_F_JMP | AST_F_RET
    jnz .rs_bnext
.rs_fallemit:
    mov eax, r14d
    inc eax                      ; bi+1
    cmp eax, r11d
    jae .rs_bnext
    mov edx, r12d
    shl rdx, 32                  ; fi<<32
    or rdx, rax                  ; |(bi+1): tidx
    mov r8, rdx                  ; tidx
    xor edx, edx                 ; kind=FALL
    xor r9d, r9d                 ; name=NULL
    jmp .rs_fallsucc
.rs_bnext:
    inc r14d
    jmp .rs_b
.rs_fnext:
    inc r12d
    jmp .rs_f
.rs_fallsucc:
    ; Entrada: r8=tidx, edx=0 (kind FALL), r9d=0 (name NULL).
    ; Refetch block (r12d=fi, r14d=bi intactos; resto scratch).
    mov eax, r12d
    imul eax, eax, SIZEOF_FUNC
    mov rcx, [r13+AstUnit.funcs]
    lea rcx, [rcx+rax]           ; func
    mov eax, r14d
    imul eax, eax, SIZEOF_BLOCK
    mov rdx, [rcx+AstFunc.blocks]
    lea rcx, [rdx+rax]           ; block
    xor edx, edx                 ; kind=FALL (reconfirma)
    sub rsp, 48
    mov qword [rsp+32], 0        ; name_len=0
    call dex_ast_block_succ
    add rsp, 48
    test eax, eax
    jnz .rs_oom
    jmp .rs_bnext
.rs_ok:
    xor eax, eax
    pop rdi
    pop r15
    pop r14
    pop r12
    pop rbx
    ret
.rs_oom:
    mov eax, ERR_OOM
    pop rdi
    pop r15
    pop r14
    pop r12
    pop rbx
    ret

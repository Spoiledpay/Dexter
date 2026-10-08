;=============================================================================
; Dexter/src/front/ast.asm
; Nós da AST textual (R-6.3): construtores com growth + free recursivo.
;
; O quê: AstUnit/Func/Block/Instr/Succ/Data em heap (ver dexter.inc).
; Por quê: o parser (parser.asm) monta a AST; o lift (R-6.4) consome.
; Contrato:
;   Nomes/verbatim EMPRESTAM o fonte (ptr/len, sem cópia).
;   Índices (não ponteiros) sobrevivem a regrowth: re-fetch após cada
;   crescimento no mesmo nível ou acima (documentado por função).
;   dex_ast_unit_new() -> rax=unit* | 0 (OOM).
;   dex_ast_unit_func(unit,name_ptr,name_len,sect_ptr,[sect_len]) ->
;     eax=func_idx | -1 (OOM). sect_len = 5º arg em [rsp+40].
;   dex_ast_func_block(func,label_ptr,label_len) -> eax=idx | -1.
;   dex_ast_block_instr(block,src96) -> eax=0 ok | 6 (OOM). Copia 96 B.
;   dex_ast_block_succ(block,kind,tidx,name_ptr,[name_len]) ->
;     eax=0 ok | 6. name_len = 5º arg em [rsp+40].
;   dex_ast_unit_data(unit,src56) -> eax=0 ok | 6. Copia 56 B.
;   dex_ast_free_unit(unit) — null-safe; libera arrays+nós (nunca o fonte);
;     tolera unidades PARCIAIS (counts dirigem; ptrs NULL ok).
;   Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: tests\ast_check.asm (golden Func/Blocks/CFG).
;
; Requisitos atendidos: R-6.3 (nós Func/Block/Instr/Op + ownership)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_ast_unit_new
global dex_ast_unit_func
global dex_ast_func_block
global dex_ast_block_instr
global dex_ast_block_succ
global dex_ast_unit_data
global dex_ast_free_unit
global dex_ast_dump

extern dex_malloc
extern dex_free
extern dex_realloc_grow
extern dex_memcpy
extern dex_console_print_cstr
extern dex_console_print_u64dec
extern dex_console_newline

section .rodata
s_ad_f:      db "AST funcs=", 0
s_ad_b:      db " blocks=", 0
s_ad_i:      db " instrs=", 0
s_ad_s:      db " succs=", 0
s_ad_d:      db " db=", 0
s_ad_e:      db " equ=", 0
s_ad_r:      db " dir=", 0

section .text

;-----------------------------------------------------------------------------
; dex_ast_unit_new — -> rax=unit* (zerada) ou 0.
;-----------------------------------------------------------------------------
dex_ast_unit_new:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov ecx, SIZEOF_UNIT
    call dex_malloc
    add rsp, 32
    pop rbp
    ret

;-----------------------------------------------------------------------------
; ast_grow_arr — interno (escopo de arquivo; chamado de vários dex_ast_*).
; Garante (count+1) elems.
; Args: rcx=arr_ptr, rdx=cap_elems, r8=count, r9=elemsz,
;       r10=&store_ptr, r11=&store_cap.
; Ret: rax=0 ok (store atualizado) | 6 OOM. Clobber: rax,rcx,rdx,r8-r11.
;-----------------------------------------------------------------------------
ast_grow_arr:
    cmp r8d, edx
    jb .ga_ok
    ; min_bytes = (count+1)*elemsz
    mov eax, r8d
    inc rax
    imul rax, r9
    mov r8, rax                  ; min
    ; old_bytes = cap*elemsz
    mov eax, edx
    imul rax, r9                 ; old_bytes (cap=0 -> 0, ok)
    mov rdx, rax                 ; old_bytes p/ realloc
    mov rcx, [r10]               ; old_ptr (pode ser 0)
    ; r9 (elemsz) morre no call abaixo (r8-r11 voláteis!): spill junto.
    ; 3 pushes + sub 32 = 56 (mesmo alinhamento do padrão 2 pushes + 40).
    push r9
    push r10                     ; 3 pushes: rsp%16 segue o padrão do projeto
    push r11
    sub rsp, 32
    call dex_realloc_grow        ; rax=new, rdx=new_cap(bytes)
    add rsp, 32
    pop r11
    pop r10
    pop r9                       ; elemsz restaurado (divisor seguro)
    test rax, rax
    jz .ga_oom
    test r9, r9                  ; defesa: elemsz 0 (bug do caller) nunca divide
    jz .ga_oom
    mov [r10], rax
    mov rax, rdx                 ; new_cap (bytes; rdx morre no xor!)
    xor edx, edx
    div r9                       ; rax=new_cap(bytes)/elemsz (exato p/ cima:
                                 ; new>=min=(count+1)*sz; resto em rdx)
    mov [r11], eax
    xor eax, eax
    ret
.ga_ok:
    xor eax, eax
    ret
.ga_oom:
    mov eax, ERR_OOM
    ret

;-----------------------------------------------------------------------------
; dex_ast_unit_func — rcx=unit, rdx=name_ptr, r8=name_len, r9=sect_ptr,
; [rsp+40]=sect_len -> eax=func_idx | -1.
;-----------------------------------------------------------------------------
dex_ast_unit_func:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    mov rbx, rcx                 ; unit
    mov r12, rdx                 ; name_ptr
    mov r13, r8                  ; name_len
    mov r14, r9                  ; sect_ptr
    mov rax, [rbp+48]            ; sect_len (5º arg: home [rsp_orig+32]+8)
    mov [rbp-72], rax
    mov ecx, [rbx+AstUnit.nfuncs]
    mov edx, [rbx+AstUnit.capfuncs]
    lea r10, [rbx+AstUnit.funcs]
    lea r11, [rbx+AstUnit.capfuncs]
    mov r8d, ecx
    mov r9d, SIZEOF_FUNC
    sub rsp, 32
    call ast_grow_arr
    add rsp, 32
    test eax, eax
    jnz .uf_fail
    mov ecx, [rbx+AstUnit.nfuncs]
    mov eax, ecx
    imul eax, SIZEOF_FUNC
    mov rdx, [rbx+AstUnit.funcs]
    lea rdx, [rdx+rax]           ; node
    mov [rdx+AstFunc.name_ptr], r12
    mov [rdx+AstFunc.name_len], r13
    mov [rdx+AstFunc.sect_ptr], r14
    mov rax, [rbp-72]
    mov [rdx+AstFunc.sect_len], rax
    mov dword [rdx+AstFunc.nblocks], 0
    mov dword [rdx+AstFunc.capblocks], 0
    mov qword [rdx+AstFunc.blocks], 0
    mov eax, ecx
    inc dword [rbx+AstUnit.nfuncs]
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.uf_fail:
    mov eax, -1
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_ast_func_block — rcx=func, rdx=label_ptr, r8=label_len
; -> eax=block_idx | -1.
;-----------------------------------------------------------------------------
dex_ast_func_block:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov rbx, rcx                 ; func
    mov r12, rdx                 ; label_ptr
    mov r13, r8                  ; label_len
    mov ecx, [rbx+AstFunc.nblocks]
    mov edx, [rbx+AstFunc.capblocks]
    lea r10, [rbx+AstFunc.blocks]
    lea r11, [rbx+AstFunc.capblocks]
    mov r8d, ecx
    mov r9d, SIZEOF_BLOCK
    sub rsp, 32
    call ast_grow_arr
    add rsp, 32
    test eax, eax
    jnz .fb_fail
    mov ecx, [rbx+AstFunc.nblocks]
    mov eax, ecx
    imul eax, SIZEOF_BLOCK
    mov rdx, [rbx+AstFunc.blocks]
    lea rdx, [rdx+rax]           ; node
    mov [rdx+AstBlock.label_ptr], r12
    mov [rdx+AstBlock.label_len], r13
    mov dword [rdx+AstBlock.ninstrs], 0
    mov dword [rdx+AstBlock.capinstrs], 0
    mov qword [rdx+AstBlock.instrs], 0
    mov dword [rdx+AstBlock.nsucc], 0
    mov dword [rdx+AstBlock.capsucc], 0
    mov qword [rdx+AstBlock.succs], 0
    mov eax, ecx
    inc dword [rbx+AstFunc.nblocks]
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fb_fail:
    mov eax, -1
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_ast_block_instr — rcx=block, rdx=src96 -> eax=0 ok | 6 OOM.
;-----------------------------------------------------------------------------
dex_ast_block_instr:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 40
    mov rbx, rcx                 ; block
    mov r12, rdx                 ; src
    mov ecx, [rbx+AstBlock.ninstrs]
    mov edx, [rbx+AstBlock.capinstrs]
    lea r10, [rbx+AstBlock.instrs]
    lea r11, [rbx+AstBlock.capinstrs]
    mov r8d, ecx
    mov r9d, SIZEOF_INSTR
    sub rsp, 32
    call ast_grow_arr
    add rsp, 32
    test eax, eax
    jnz .bi_fail
    mov ecx, [rbx+AstBlock.ninstrs]
    mov eax, ecx
    imul eax, SIZEOF_INSTR
    mov rdx, [rbx+AstBlock.instrs]
    lea rcx, [rdx+rax]           ; dst
    mov rdx, r12                 ; src
    mov r8d, SIZEOF_INSTR
    sub rsp, 32
    call dex_memcpy
    add rsp, 32
    inc dword [rbx+AstBlock.ninstrs]
    xor eax, eax
    add rsp, 40
    pop r12
    pop rbx
    pop rbp
    ret
.bi_fail:
    mov eax, ERR_OOM
    add rsp, 40
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_ast_block_succ — rcx=block, rdx=kind, r8=tidx, r9=name_ptr,
; [rsp+40]=name_len -> eax=0 ok | 6 OOM.
;-----------------------------------------------------------------------------
dex_ast_block_succ:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 48
    mov rbx, rcx                 ; block
    mov r12d, edx                ; kind
    mov r13, r8                  ; tidx
    mov r14, r9                  ; name_ptr
    mov rax, [rbp+48]            ; name_len (5º arg: home [rsp_orig+32]+8)
    mov [rbp-80], rax
    mov ecx, [rbx+AstBlock.nsucc]
    mov edx, [rbx+AstBlock.capsucc]
    lea r10, [rbx+AstBlock.succs]
    lea r11, [rbx+AstBlock.capsucc]
    mov r8d, ecx
    mov r9d, SIZEOF_SUCC
    sub rsp, 32
    call ast_grow_arr
    add rsp, 32
    test eax, eax
    jnz .bs_fail
    mov ecx, [rbx+AstBlock.nsucc]
    mov eax, ecx
    imul eax, SIZEOF_SUCC
    mov rdx, [rbx+AstBlock.succs]
    lea rdx, [rdx+rax]           ; node
    mov [rdx+AstSucc.kind], r12d
    mov dword [rdx+AstSucc.padk], 0
    mov [rdx+AstSucc.tidx], r13
    mov [rdx+AstSucc.name_ptr], r14
    mov rax, [rbp-80]
    mov [rdx+AstSucc.name_len], rax
    inc dword [rbx+AstBlock.nsucc]
    xor eax, eax
    add rsp, 48
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.bs_fail:
    mov eax, ERR_OOM
    add rsp, 48
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_ast_unit_data — rcx=unit, rdx=src56 -> eax=0 ok | 6 OOM.
;-----------------------------------------------------------------------------
dex_ast_unit_data:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 40
    mov rbx, rcx                 ; unit
    mov r12, rdx                 ; src
    mov ecx, [rbx+AstUnit.ndata]
    mov edx, [rbx+AstUnit.capdata]
    lea r10, [rbx+AstUnit.datas]
    lea r11, [rbx+AstUnit.capdata]
    mov r8d, ecx
    mov r9d, SIZEOF_DATA
    sub rsp, 32
    call ast_grow_arr
    add rsp, 32
    test eax, eax
    jnz .ud_fail
    mov ecx, [rbx+AstUnit.ndata]
    mov eax, ecx
    imul eax, SIZEOF_DATA
    mov rdx, [rbx+AstUnit.datas]
    lea rcx, [rdx+rax]           ; dst
    mov rdx, r12                 ; src
    mov r8d, SIZEOF_DATA
    sub rsp, 32
    call dex_memcpy
    add rsp, 32
    inc dword [rbx+AstUnit.ndata]
    xor eax, eax
    add rsp, 40
    pop r12
    pop rbx
    pop rbp
    ret
.ud_fail:
    mov eax, ERR_OOM
    add rsp, 40
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_ast_free_unit — rcx=unit (NULL ok; tolera parciais).
;-----------------------------------------------------------------------------
dex_ast_free_unit:
    test rcx, rcx
    jz .fu_done
    push rbp
    mov rbp, rsp
    push rbx
    push rdi                     ; bi vive em edi (não-volátil; dex_free o preserva)
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32                  ; 7 pushes (56B) + 32 = 88 ≡ 8: calls ok
    mov rbx, rcx                 ; unit
    mov r12d, [rbx+AstUnit.nfuncs]
    mov r13, [rbx+AstUnit.funcs]
    xor r14d, r14d               ; fi
.fu_f:
    cmp r14d, r12d
    jae .fu_datas
    mov eax, r14d
    imul eax, SIZEOF_FUNC
    lea rax, [r13+rax]           ; func
    mov r15, rax
    mov ecx, [r15+AstFunc.nblocks]
    mov rdx, [r15+AstFunc.blocks]
    test ecx, ecx
    jz .fu_fblocks_done
    test rdx, rdx
    jz .fu_fblocks_done
    xor edi, edi                 ; bi (edi: não-volátil, sobrevive aos calls)
.fu_b:
    mov ecx, [r15+AstFunc.nblocks]
    cmp edi, ecx
    jae .fu_fblocks_done
    mov eax, edi
    imul eax, SIZEOF_BLOCK
    mov rdx, [r15+AstFunc.blocks]
    lea r11, [rdx+rax]           ; block (recalculado; free pode... não move
                                 ; outros arrays — só libera. seguro.)
    mov rcx, [r11+AstBlock.instrs]
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rdx, [r15+AstFunc.blocks]
    mov eax, edi
    imul eax, SIZEOF_BLOCK
    lea r11, [rdx+rax]
    mov rcx, [r11+AstBlock.succs]
    sub rsp, 32
    call dex_free
    add rsp, 32
    inc edi
    jmp .fu_b
.fu_fblocks_done:
    mov rcx, [r15+AstFunc.blocks]
    sub rsp, 32
    call dex_free
    add rsp, 32
    inc r14d
    jmp .fu_f
.fu_datas:
    mov rcx, [rbx+AstUnit.datas]
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rcx, [rbx+AstUnit.funcs]
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_free
    add rsp, 32
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rbx
    pop rbp
.fu_done:
    ret

;-----------------------------------------------------------------------------
; dex_ast_dump — rcx=unit -> eax=0 ok | 8 args (NULL).
; Imprime em stdout a linha-resumo (mesmo formato do golden de
; tests\ast_check.asm): `AST funcs=F blocks=B instrs=I succs=S db=D
; equ=E dir=R` + CRLF. Só leitura (sem heap); tolera unidade parcial
; (counts dirigem; bases NULL ok). Preserva: rbx, rbp, rdi, rsi, r12-r15.
; Como testar: `-ast-dump` ([10] em tests\run_tests.bat).
;-----------------------------------------------------------------------------
dex_ast_dump:
    test rcx, rcx
    jz .ad_args
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15                     ; 8 pushes (64B) + sub 40 = 104 ≡ 8:
                                 ; antes de call, rsp%16==0
    sub rsp, 40
    mov rbx, rcx                 ; unit
    ; ---- contagem (só leitura, sem calls; voláteis livres) ----
    xor r8d, r8d                 ; blocks
    xor r9d, r9d                 ; instrs
    xor r10d, r10d               ; succs
    xor r11d, r11d               ; db
    xor edi, edi                 ; equ
    xor esi, esi                 ; dir
    mov edx, [rbx+AstUnit.nfuncs]
    test edx, edx
    jz .ad_datas
    mov r14, [rbx+AstUnit.funcs]
    xor r13d, r13d               ; fi
.ad_f:
    cmp r13d, edx
    jae .ad_datas
    mov eax, r13d
    imul eax, SIZEOF_FUNC
    lea r12, [r14+rax]           ; func
    mov eax, [r12+AstFunc.nblocks]
    add r8d, eax
    mov r12, [r12+AstFunc.blocks] ; base (func não mais necessária)
    test eax, eax
    jz .ad_fnext
    test r12, r12
    jz .ad_fnext
    xor ecx, ecx                 ; bi
.ad_b:
    cmp ecx, eax
    jae .ad_fnext
    push rax                     ; nblocks (imul usa eax)
    mov eax, ecx
    imul eax, SIZEOF_BLOCK
    add rax, r12                 ; &block
    add r9d, [rax+AstBlock.ninstrs]
    add r10d, [rax+AstBlock.nsucc]
    pop rax
    inc ecx
    jmp .ad_b
.ad_fnext:
    inc r13d
    jmp .ad_f
.ad_datas:
    mov eax, [rbx+AstUnit.ndata]
    test eax, eax
    jz .ad_collect
    mov r12, [rbx+AstUnit.datas]
    test r12, r12
    jz .ad_collect
    xor ecx, ecx                 ; di
.ad_d:
    cmp ecx, eax
    jae .ad_collect
    push rax                     ; ndata (edx é scratch aqui)
    mov eax, ecx
    imul eax, SIZEOF_DATA
    add rax, r12                 ; &data
    mov edx, [rax+AstData.kind]
    cmp edx, AST_DATA_DB
    je .ad_isdb
    cmp edx, AST_DATA_EQU
    je .ad_isequ
    inc esi
    jmp .ad_dnx
.ad_isdb:
    inc r11d
    jmp .ad_dnx
.ad_isequ:
    inc edi
.ad_dnx:
    pop rax
    inc ecx
    jmp .ad_d
.ad_collect:
    ; ---- move p/ não-voláteis (calls abaixo matam r8-r11) ----
    mov r13d, r8d                ; blocks
    mov r14d, r9d                ; instrs
    mov r12d, r10d               ; succs
    mov r15d, r11d               ; db (equ/dir já em edi/esi)
    ; ---- impressão (stdout; calls só com shadow) ----
    lea rcx, [rel s_ad_f]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, [rbx+AstUnit.nfuncs]
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_ad_b]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, r13d
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_ad_i]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, r14d
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_ad_s]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, r12d
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_ad_d]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, r15d
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_ad_e]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, edi
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    lea rcx, [rel s_ad_r]
    sub rsp, 32
    call dex_console_print_cstr
    add rsp, 32
    mov ecx, esi
    sub rsp, 32
    call dex_console_print_u64dec
    add rsp, 32
    sub rsp, 32
    call dex_console_newline
    add rsp, 32
    xor eax, eax
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.ad_args:
    mov eax, ERR_ARGS
    ret

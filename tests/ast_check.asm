;=============================================================================
; Dexter/tests/ast_check.asm
; Driver de teste do parser/AST (R-6.3): parseia tests\hello.asm (golden)
; via dex_parse_asm e imprime resumo + dump estrutural.
;
; Uso (via tests\run_tests.bat [9]): ast_check.exe [input.asm]
; (default: tests\hello.asm; golden extra: tests\loop.asm).
; Saída stdout, 1ª linha = resumo golden:
;   AST funcs=<F> blocks=<B> instrs=<I> succs=<S> db=<D> equ=<E> dir=<R>
; Depois: `F name=<..> sect=<..> blocks=<n>`, `B label=<..> instrs=<n>
; succs=<n>`, `I mne=<..> flags=<f> nops=<n> ok0=<k> ok1=<k> ok2=<k>
; [tname=<..>]`, `S kind=<k> tidx=<hex> [name=<..>]`, `D kind=<k>
; [label=<..>]`. Nomes/texto via ptr/len (fonte ainda mapeada).
; Retorno: 0 se parse OK, 2 em erro de I/O ou parse.
; Sem dependências do Dexter (só kernel32 + front/parser/ast).
;
; Requisitos atendidos: R-6.3 (teste golden Func/Blocks/CFG)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global main

extern GetStdHandle
extern GetCommandLineA
extern CreateFileA
extern ReadFile
extern CloseHandle
extern WriteFile
extern ExitProcess
extern dex_parse_asm
extern dex_ast_free_unit

section .rodata
s_path   db "tests\hello.asm", 0
s_sum0   db "AST funcs=", 0
s_blocks db " blocks=", 0
s_instrs db " instrs=", 0
s_succs  db " succs=", 0
s_db     db " db=", 0
s_equ    db " equ=", 0
s_dir    db " dir=", 0
s_crlf   db 13, 10, 0
s_fpre   db "F name=", 0
s_sect   db " sect=", 0
s_nblk   db " blocks=", 0
s_bpre   db "B label=", 0
s_ni     db " instrs=", 0
s_ns     db " succs=", 0
s_ipre   db "I mne=", 0
s_fl     db " flags=", 0
s_nops   db " nops=", 0
s_ok0    db " ok0=", 0
s_ok1    db " ok1=", 0
s_ok2    db " ok2=", 0
s_tn     db " tname=", 0
s_spre   db "S kind=", 0
s_tidx   db " tidx=0x", 0
s_nm     db " name=", 0
s_dpre   db "D kind=", 0
s_lab    db " label=", 0
s_sp     db " ", 0
s_q      db "'", 0
s_noname db "-", 0
s_err_io db "ast_check: cannot read input file", 13, 10, 0
s_err_ps db "ast_check: parse failed", 13, 10, 0

section .bss
align 8
g_inbuf:  resb 1048576              ; 1 MB (golden tem 898 B)

section .text

;-----------------------------------------------------------------------------
; main — sem args. Frame como lex_check (8 pushes + sub 104; locais livres
; [rbp-160,rbp-64); salvos [rbp-56,rbp) intocados; shadow abaixo de -160).
; Locais: hOut[-112,-104) hFile[-120,-112) lidos[-128,-120) unit[-136,-128)
; dec-tmp(24B)[-160,-136) contadores(6x8B: blocks/instrs/succs/db/equ/dir)
; [-208,-160). Frame: 8 pushes + sub rsp,152.
;-----------------------------------------------------------------------------
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
    sub rsp, 152
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-112], rax             ; hOut
    ; argv[1] (caminho do .asm; default: s_path). Pula argv[0] com aspas.
    lea rcx, [rel s_path]          ; default
    sub rsp, 32
    call GetCommandLineA
    add rsp, 32
    mov rsi, rax                   ; cursor na cmdline
.av0:
    movzx eax, byte [rsi]
    test al, al
    jz .av_use                     ; linha vazia: default
    cmp al, ' '
    je .av_sp
    cmp al, 9
    je .av_sp
    cmp al, '"'
    je .av_q0
    jmp .av_plain
.av_sp:
    inc rsi
    jmp .av0
.av_q0:
    inc rsi
.av_q0l:
    movzx eax, byte [rsi]
    test al, al
    jz .av_use
    cmp al, '"'
    je .av_q0e
    inc rsi
    jmp .av_q0l
.av_q0e:
    inc rsi
    jmp .av1
.av_plain:
    inc rsi
    movzx eax, byte [rsi]
    test al, al
    jz .av_use
    cmp al, ' '
    je .av1s
    cmp al, 9
    je .av1s
    jmp .av_plain
.av1s:
    inc rsi
.av1:
    movzx eax, byte [rsi]          ; pula espaços até argv[1]
    test al, al
    jz .av_use
    cmp al, ' '
    je .av1s
    cmp al, 9
    je .av1s
    cmp al, '"'
    je .av_q1
    mov rcx, rsi                   ; argv[1] sem aspas: termina em espaço/NUL
.av_p1l:
    movzx eax, byte [rsi]
    test al, al
    jz .av_p1e
    cmp al, ' '
    je .av_p1e
    cmp al, 9
    je .av_p1e
    inc rsi
    jmp .av_p1l
.av_p1e:
    mov byte [rsi], 0              ; termina (buffer da cmdline é gravável)
    jmp .av_open
.av_q1:
    inc rsi
    mov rcx, rsi
.av_q1l:
    movzx eax, byte [rsi]
    test al, al
    jz .av_open
    cmp al, '"'
    je .av_q1e
    inc rsi
    jmp .av_q1l
.av_q1e:
    mov byte [rsi], 0
    jmp .av_open
.av_use:
    lea rcx, [rel s_path]          ; default (já estava)
.av_open:
    mov edx, 0x80000000
    mov r8d, 1
    xor r9d, r9d
    sub rsp, 48
    mov qword [rsp+32], 3
    xor eax, eax
    mov [rsp+40], rax
    mov [rsp+48], rax
    call CreateFileA
    add rsp, 48
    cmp rax, -1
    je .io_err
    mov [rbp-120], rax             ; hFile
    lea r14, [rel g_inbuf]
    xor r15d, r15d                 ; total
.rd:
    cmp r15, 1048576
    jae .rd_done
    mov rcx, [rbp-120]
    lea rdx, [r14+r15]
    mov r8d, 1048576
    sub r8, r15
    cmp r8, 2147483647
    jbe .rd_ncap
    mov r8d, 2147483647
.rd_ncap:
    lea r9, [rbp-128]
    mov qword [rbp-128], 0
    sub rsp, 32
    mov qword [rsp+32], 0
    call ReadFile
    add rsp, 32
    test eax, eax
    jz .rd_done
    mov rax, [rbp-128]
    test rax, rax
    jz .rd_done
    add r15, rax
    jmp .rd
.rd_done:
    mov rcx, [rbp-120]
    sub rsp, 32
    call CloseHandle
    add rsp, 32
    ; parse (vazio = unidade vazia, exit 0 — mesmo contrato total do lex)
    mov rcx, r14
    mov rdx, r15
    lea r8, [rbp-136]              ; &unit (slot; preenchido pelo parse)
    mov qword [rbp-136], 0
    sub rsp, 32
    call dex_parse_asm
    add rsp, 32
    test eax, eax
    jnz .parse_err
    mov rbx, [rbp-136]             ; unit (buf/len mortos daqui em diante;
                                   ; nomes emprestam o .bss, que segue vivo)
    test rbx, rbx
    jz .parse_err
    ; zera contadores na pilha (6x8B)
    xor eax, eax
    mov [rbp-208], rax
    mov [rbp-200], rax
    mov [rbp-192], rax
    mov [rbp-184], rax
    mov [rbp-176], rax
    mov [rbp-168], rax
    ; conta funcs->blocks->instrs/succs (sem calls; só leitura)
    mov r8d, [rbx+AstUnit.nfuncs]
    test r8d, r8d
    jz .cnt_data
    mov r9, [rbx+AstUnit.funcs]
    xor r10d, r10d                 ; fi
.cnt_f:
    cmp r10d, r8d
    jae .cnt_data
    mov eax, r10d
    imul eax, SIZEOF_FUNC
    lea rax, [r9+rax]              ; func
    mov ecx, [rax+AstFunc.nblocks]
    add [rbp-208], rcx             ; blocks += nblocks
    mov rcx, [rax+AstFunc.blocks]
    jrcxz .cnt_fnext
    xor r11d, r11d                 ; bi
.cnt_b:
    cmp r11d, [rax+AstFunc.nblocks]
    jae .cnt_fnext
    mov edx, r11d
    imul edx, SIZEOF_BLOCK
    lea rdx, [rcx+rdx]             ; block
    mov esi, [rdx+AstBlock.ninstrs]
    add [rbp-200], rsi             ; instrs += ninstrs
    mov esi, [rdx+AstBlock.nsucc]
    add [rbp-192], rsi             ; succs += nsucc
    inc r11d
    jmp .cnt_b
.cnt_fnext:
    inc r10d
    jmp .cnt_f
.cnt_data:
    mov r8d, [rbx+AstUnit.ndata]
    test r8d, r8d
    jz .sum
    mov r9, [rbx+AstUnit.datas]
    xor r10d, r10d                 ; di
.cnt_d:
    cmp r10d, r8d
    jae .sum
    mov eax, r10d
    imul eax, SIZEOF_DATA
    lea rax, [r9+rax]              ; data
    mov ecx, [rax+AstData.kind]
    cmp ecx, AST_DATA_DB
    jne .cnt_d2
    inc qword [rbp-184]            ; db++
    jmp .cnt_dnext
.cnt_d2:
    cmp ecx, AST_DATA_EQU
    jne .cnt_d3
    inc qword [rbp-176]            ; equ++
    jmp .cnt_dnext
.cnt_d3:
    inc qword [rbp-168]            ; dir++ (tudo que não é db/equ)
.cnt_dnext:
    inc r10d
    jmp .cnt_d
.sum:
    ; resumo (1ª linha = golden p/ findstr)
    lea rcx, [rel s_sum0]
    call .print_cstr
    mov ecx, [rbx+AstUnit.nfuncs]
    call .print_dec
    lea rcx, [rel s_blocks]
    call .print_cstr
    mov rcx, [rbp-208]
    call .print_dec
    lea rcx, [rel s_instrs]
    call .print_cstr
    mov rcx, [rbp-200]
    call .print_dec
    lea rcx, [rel s_succs]
    call .print_cstr
    mov rcx, [rbp-192]
    call .print_dec
    lea rcx, [rel s_db]
    call .print_cstr
    mov rcx, [rbp-184]
    call .print_dec
    lea rcx, [rel s_equ]
    call .print_cstr
    mov rcx, [rbp-176]
    call .print_dec
    lea rcx, [rel s_dir]
    call .print_cstr
    mov rcx, [rbp-168]
    call .print_dec
    lea rcx, [rel s_crlf]
    call .print_cstr
    ; dump: funcs -> blocks -> instrs/succs, depois datas.
    ; idxs em r12d(fi)/r13d(bi)/r14d(ii)/r15d(si,di); ptrs recalculados
    ; a cada passo (sem stalePerseguindo realloc — só leitura aqui).
    mov r12d, [rbx+AstUnit.nfuncs]
    test r12d, r12d
    jz .dump_data
    mov r13, [rbx+AstUnit.funcs]
    xor r12d, r12d                 ; fi
.dump_f:
    cmp r12d, [rbx+AstUnit.nfuncs]
    jae .dump_data
    mov eax, r12d
    imul eax, SIZEOF_FUNC
    add rax, r13                   ; func (r13=base recarregado abaixo!)
    mov r13, [rbx+AstUnit.funcs]   ; (print_* clobbera voláteis; r13 é
    mov eax, r12d                  ;  não-volátil e sobrevive — mas base
    imul eax, SIZEOF_FUNC          ;  pode... não muda (sem alloc). ok.)
    lea rcx, [rel s_fpre]
    call .print_cstr
    mov rax, [rbx+AstUnit.funcs]
    mov ecx, r12d
    imul ecx, SIZEOF_FUNC
    lea rax, [rax+rcx]             ; func
    mov [rbp-96], rax             ; spill func (calls abaixo!)
    mov rcx, [rax+AstFunc.name_ptr]
    mov r8, [rax+AstFunc.name_len]
    test rcx, rcx
    jz .dump_fname
    test r8, r8
    jz .dump_fname
    call .print_mem
    jmp .dump_fsect
.dump_fname:
    lea rcx, [rel s_noname]
    call .print_cstr
.dump_fsect:
    lea rcx, [rel s_sect]
    call .print_cstr
    mov rax, [rbp-96]
    mov rcx, [rax+AstFunc.sect_ptr]
    mov r8, [rax+AstFunc.sect_len]
    test rcx, rcx
    jz .dump_fsect0
    test r8, r8
    jz .dump_fsect0
    call .print_mem
    jmp .dump_fblk
.dump_fsect0:
    lea rcx, [rel s_noname]
    call .print_cstr
.dump_fblk:
    lea rcx, [rel s_nblk]
    call .print_cstr
    mov rax, [rbp-96]
    mov ecx, [rax+AstFunc.nblocks]
    call .print_dec
    lea rcx, [rel s_crlf]
    call .print_cstr
    ; blocos da func
    mov rax, [rbp-96]
    mov r14, [rax+AstFunc.blocks]
    xor r13d, r13d                 ; bi
.dump_b:
    mov rax, [rbp-96]
    cmp r13d, [rax+AstFunc.nblocks]
    jae .dump_fnext
    mov eax, r13d
    imul eax, SIZEOF_BLOCK
    lea rax, [r14+rax]             ; block (r14=base; sem alloc: estável)
    mov [rbp-88], rax             ; spill block
    lea rcx, [rel s_bpre]
    call .print_cstr
    mov rax, [rbp-88]
    mov rcx, [rax+AstBlock.label_ptr]
    mov r8, [rax+AstBlock.label_len]
    test rcx, rcx
    jz .dump_bnoname
    test r8, r8
    jz .dump_bnoname
    call .print_mem
    jmp .dump_bni
.dump_bnoname:
    lea rcx, [rel s_noname]
    call .print_cstr
.dump_bni:
    lea rcx, [rel s_ni]
    call .print_cstr
    mov rax, [rbp-88]
    mov ecx, [rax+AstBlock.ninstrs]
    call .print_dec
    lea rcx, [rel s_ns]
    call .print_cstr
    mov rax, [rbp-88]
    mov ecx, [rax+AstBlock.nsucc]
    call .print_dec
    lea rcx, [rel s_crlf]
    call .print_cstr
    ; instruções do bloco
    mov rax, [rbp-88]
    mov r15, [rax+AstBlock.instrs]
    xor r14d, r14d                 ; ii (reuso r14: buf morto aqui)
.dump_i:
    mov rax, [rbp-88]
    cmp r14d, [rax+AstBlock.ninstrs]
    jae .dump_s
    mov eax, r14d
    imul eax, SIZEOF_INSTR
    lea rax, [r15+rax]             ; instr
    mov [rbp-80], rax             ; spill instr
    lea rcx, [rel s_ipre]
    call .print_cstr
    mov rax, [rbp-80]
    mov rcx, [rax+AstInstr.mne_ptr]
    mov r8, [rax+AstInstr.mne_len]
    call .print_mem
    lea rcx, [rel s_fl]
    call .print_cstr
    mov rax, [rbp-80]
    mov ecx, [rax+AstInstr.flags]
    call .print_dec
    lea rcx, [rel s_nops]
    call .print_cstr
    mov rax, [rbp-80]
    mov ecx, [rax+AstInstr.nops]
    call .print_dec
    lea rcx, [rel s_ok0]
    call .print_cstr
    mov rax, [rbp-80]
    movzx ecx, byte [rax+AstInstr.op0+DexOp.kind]
    call .print_dec
    lea rcx, [rel s_ok1]
    call .print_cstr
    mov rax, [rbp-80]
    movzx ecx, byte [rax+AstInstr.op1+DexOp.kind]
    call .print_dec
    lea rcx, [rel s_ok2]
    call .print_cstr
    mov rax, [rbp-80]
    movzx ecx, byte [rax+AstInstr.op2+DexOp.kind]
    call .print_dec
    mov rax, [rbp-80]
    cmp qword [rax+AstInstr.tname_ptr], 0
    je .dump_ieol
    lea rcx, [rel s_tn]
    call .print_cstr
    mov rax, [rbp-80]
    mov rcx, [rax+AstInstr.tname_ptr]
    mov r8, [rax+AstInstr.tname_len]
    call .print_mem
.dump_ieol:
    lea rcx, [rel s_crlf]
    call .print_cstr
    ; recarrega base de instrs (print_* não aloca; paranóia barata)
    mov rax, [rbp-88]
    mov r15, [rax+AstBlock.instrs]
    inc r14d
    jmp .dump_i
.dump_s:
    mov rax, [rbp-88]
    mov r15, [rax+AstBlock.succs]
    xor r14d, r14d                 ; si
.dump_sl:
    mov rax, [rbp-88]
    cmp r14d, [rax+AstBlock.nsucc]
    jae .dump_bnext
    mov eax, r14d
    imul eax, SIZEOF_SUCC
    lea rax, [r15+rax]             ; succ
    mov [rbp-72], rax             ; spill succ
    lea rcx, [rel s_spre]
    call .print_cstr
    mov rax, [rbp-72]
    mov ecx, [rax+AstSucc.kind]
    call .print_dec
    lea rcx, [rel s_tidx]
    call .print_cstr
    mov rax, [rbp-72]
    mov rcx, [rax+AstSucc.tidx]
    call .print_hex
    mov rax, [rbp-72]
    cmp qword [rax+AstSucc.name_ptr], 0
    je .dump_seol
    lea rcx, [rel s_nm]
    call .print_cstr
    mov rax, [rbp-72]
    mov rcx, [rax+AstSucc.name_ptr]
    mov r8, [rax+AstSucc.name_len]
    call .print_mem
.dump_seol:
    lea rcx, [rel s_crlf]
    call .print_cstr
    mov rax, [rbp-88]
    mov r15, [rax+AstBlock.succs]
    inc r14d
    jmp .dump_sl
.dump_bnext:
    mov rax, [rbp-96]
    mov r14, [rax+AstFunc.blocks]
    inc r13d
    jmp .dump_b
.dump_fnext:
    inc r12d
    jmp .dump_f
.dump_data:
    mov r14d, [rbx+AstUnit.ndata]
    test r14d, r14d
    jz .dump_done
    mov r15, [rbx+AstUnit.datas]
    xor r13d, r13d                 ; di
.dump_d:
    cmp r13d, r14d
    jae .dump_done
    mov eax, r13d
    imul eax, SIZEOF_DATA
    lea rax, [r15+rax]             ; data
    mov [rbp-64], rax             ; spill data
    lea rcx, [rel s_dpre]
    call .print_cstr
    mov rax, [rbp-64]
    mov ecx, [rax+AstData.kind]
    call .print_dec
    mov rax, [rbp-64]
    cmp qword [rax+AstData.label_ptr], 0
    je .dump_deol
    lea rcx, [rel s_lab]
    call .print_cstr
    mov rax, [rbp-64]
    mov rcx, [rax+AstData.label_ptr]
    mov r8, [rax+AstData.label_len]
    call .print_mem
.dump_deol:
    lea rcx, [rel s_crlf]
    call .print_cstr
    mov r15, [rbx+AstUnit.datas]
    inc r13d
    jmp .dump_d
.dump_done:
    mov rcx, rbx
    sub rsp, 32
    call dex_ast_free_unit
    add rsp, 32
    xor ecx, ecx
    call ExitProcess
.parse_err:
    lea rcx, [rel s_err_ps]
    call .print_cstr
    mov ecx, 2
    call ExitProcess
.io_err:
    cmp qword [rbp-112], 0
    je .io_exit
    lea rcx, [rel s_err_io]
    call .print_cstr
.io_exit:
    mov ecx, 2
    call ExitProcess

;-----------------------------------------------------------------------------
; Helpers de saída (iguais aos do lex_check; hOut em [rbp-112]).
;-----------------------------------------------------------------------------
.print_cstr:
    push rbx
    mov rbx, rcx
    mov rcx, rbx
    call .strlen_loc
    mov r8, rax
    mov rdx, rbx
    mov rcx, [rbp-112]
    sub rsp, 48
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 48
    pop rbx
    ret
.print_dec:
    push rbx
    mov rax, rcx
    lea rbx, [rbp-160]
    test rax, rax
    jnz .pd_conv
    mov byte [rbx], '0'
    mov r8, 1
    jmp .pd_wr
.pd_conv:
    sub rsp, 40
    mov rcx, rsp
    xor r8d, r8d
.pd_l:
    xor edx, edx
    mov r9d, 10
    div r9
    add dl, '0'
    mov [rsp+r8], dl
    inc r8d
    test rax, rax
    jnz .pd_l
    mov rcx, r8
    xor r9d, r9d
.pd_r:
    dec r8
    mov dl, [rsp+r8]
    mov [rbx+r9], dl
    inc r9d
    test r8, r8
    jnz .pd_r
    mov r8, rcx
    add rsp, 40
.pd_wr:
    mov rdx, rbx
    mov rcx, [rbp-112]
    sub rsp, 48
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 48
    pop rbx
    ret
.print_mem:
    test r8, r8
    jz .pm_done
    push rbx
    mov rbx, rcx
    mov rdx, rbx
    mov rcx, [rbp-112]
    sub rsp, 48
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 48
    pop rbx
.pm_done:
    ret
.print_hex:
    push rbx
    mov rax, rcx
    lea rbx, [rbp-160]
    test rax, rax
    jnz .ph_conv
    mov byte [rbx], '0'
    mov r8, 1
    jmp .ph_wr
.ph_conv:
    sub rsp, 40
    xor r8d, r8d
.ph_l:
    mov r9, rax
    and r9d, 15
    shr rax, 4
    cmp r9d, 9
    jbe .ph_d
    add r9d, 55
    jmp .ph_s
.ph_d:
    add r9d, 48
.ph_s:
    mov [rsp+r8], r9b
    inc r8d
    test rax, rax
    jnz .ph_l
    mov rcx, r8
    xor r9d, r9d
.ph_r:
    dec r8
    mov dl, [rsp+r8]
    mov [rbx+r9], dl
    inc r9d
    test r8, r8
    jnz .ph_r
    mov r8, rcx
    add rsp, 40
.ph_wr:
    mov rdx, rbx
    mov rcx, [rbp-112]
    sub rsp, 48
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 48
    pop rbx
    ret
.strlen_loc:
    xor eax, eax
.sl_l:
    cmp byte [rcx+rax], 0
    je .sl_d
    inc rax
    jmp .sl_l
.sl_d:
    ret

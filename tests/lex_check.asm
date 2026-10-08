;=============================================================================
; Dexter/tests/lex_check.asm
; Driver de teste do lexer NASM (R-6.2): tokeniza tests\hello.asm (golden)
; via dex_lex_one e imprime resumo + dump completo dos tokens.
;
; Uso (via tests\run_tests.bat [8]): lex_check.exe (sem args; input fixo).
; Saída stdout, 1ª linha = resumo golden:
;   LEX total=<T> eol=<E> label=<L> ident=<I> reg=<R> num=<N> str=<S>
;       lbr=<[> rbr=<]> comma=<C> plus=<+> minus= <-> colon=<:> star=<*>
;       slash=</> comment=<M> unknowns=<U>
; Linhas seguintes: dump `T <kind> <line>:<col> +<pos> '<texto>'` (EOL vira
; só `T 1 <line>:<col>` sem texto). Retorno: 0 se unknowns==0,
; 2 em erro de I/O ou unknowns>0.
; Sem dependências do Dexter (só kernel32 + dex_lex_one do lexer.obj).
;
; Frame (8 pushes + sub rsp,104; locais [rbp-168,rbp-64), fora da shadow
; de calls aninhados [..,rbp-168); salvos em [rbp-56,rbp) intocados):
;   tok DexToken(40B) [rbp-104,rbp-64) | hOut [rbp-112,rbp-104)
;   hFile [rbp-120,rbp-112) | lidos [rbp-128,rbp-120)
;   consumidos [rbp-136,rbp-128) | dec-tmp (24B) [rbp-160,rbp-136)
;
; Requisitos atendidos: R-6.2 (teste unitário de tokens, golden hello.asm)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global main

extern GetStdHandle
extern CreateFileA
extern ReadFile
extern CloseHandle
extern WriteFile
extern ExitProcess
extern dex_lex_one

section .rodata
s_path   db "tests\hello.asm", 0
s_lex    db "LEX total=", 0
s_eol    db " eol=", 0
s_label  db " label=", 0
s_ident  db " ident=", 0
s_reg    db " reg=", 0
s_num    db " num=", 0
s_str    db " str=", 0
s_lbr    db " lbr=", 0
s_rbr    db " rbr=", 0
s_comma  db " comma=", 0
s_plus   db " plus=", 0
s_minus  db " minus=", 0
s_colon  db " colon=", 0
s_star   db " star=", 0
s_slash  db " slash=", 0
s_comm   db " comment=", 0
s_unk    db " unknowns=", 0
s_crlf   db 13, 10, 0
s_tpre   db "T ", 0
s_sp     db " ", 0
s_at     db ":", 0
s_plusat db "+", 0
s_q      db "'", 0
s_eq0x   db "=0x", 0
s_err_io db "lex_check: cannot read tests\hello.asm", 13, 10, 0
s_err_tok db "LEX-ERROR", 13, 10, 0

section .bss
align 8
g_inbuf:  resb 1048576              ; 1 MB (hello.asm tem 898 B)
g_counts: resq 17                   ; histograma por kind (0..16)

section .text

;-----------------------------------------------------------------------------
; main — sem args. rcx do CRT ignorado (ENTRY:main recebe nada útil).
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
    sub rsp, 104                   ; 8 pushes -> rsp%16==8; 104%16==8 => ok
    ; stdout
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-112], rax             ; hOut
    ; abrir input
    lea rcx, [rel s_path]
    mov edx, 0x80000000            ; GENERIC_READ
    mov r8d, 1                     ; FILE_SHARE_READ
    xor r9d, r9d
    sub rsp, 48
    mov qword [rsp+32], 3          ; OPEN_EXISTING
    xor eax, eax
    mov [rsp+40], rax              ; attrs 0
    mov [rsp+48], rax              ; template 0
    call CreateFileA
    add rsp, 48
    cmp rax, -1
    je .io_err
    mov [rbp-120], rax             ; hFile
    ; ler tudo (loop até EOF ou 1 MB)
    lea r14, [rel g_inbuf]
    xor r15d, r15d                 ; total lido
.rd:
    cmp r15, 1048576
    jae .rd_done
    mov rcx, [rbp-120]
    lea rdx, [r14+r15]
    mov r8d, 1048576
    sub r8, r15                    ; restante (64 bits)
    cmp r8, 2147483647
    jbe .rd_ncap
    mov r8d, 2147483647
.rd_ncap:
    lea r9, [rbp-128]              ; &lidos (4º arg do ReadFile; válido)
    mov qword [rbp-128], 0
    sub rsp, 32
    mov qword [rsp+32], 0          ; overlapped NULL
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
    ; Arquivo vazio = stream vazio (0 tokens, exit 0); só abertura
    ; inexistente é erro (exit 2 acima). Função total sobre o conteúdo.
    ; g_counts está em .bss (zero em processo novo): sem loop de init.
    ; loop de lex: rbx=pos, r12=len, r13=total
    xor ebx, ebx                   ; pos
    mov r12, r15                   ; len
    xor r13d, r13d                 ; total
    lea r15, [rel g_counts]
.lex:
    cmp rbx, r12
    jae .lex_done
    mov rcx, r14                   ; buf
    mov rdx, r12                   ; len
    mov r8, rbx                    ; pos
    lea r9, [rbp-104]              ; &tok
    sub rsp, 32
    call dex_lex_one
    add rsp, 32
    test rax, rax
    jz .lex_done                   ; 0 = fim (contrato)
    add rbx, rax                   ; pos += consumidos
    mov eax, [rbp-104+DexToken.kind]
    cmp eax, 17
    jae .lex_bad
    inc r13d                       ; total
    inc qword [r15+rax*8]          ; counts[kind]++
    jmp .lex
.lex_bad:
    lea rcx, [rel s_err_tok]
    call .print_cstr
    mov ecx, 2
    call ExitProcess
.lex_done:
    ; resumo (1ª linha = golden p/ findstr)
    lea rcx, [rel s_lex]
    call .print_cstr
    mov rcx, r13
    call .print_dec
    lea rcx, [rel s_eol]
    call .print_cstr
    mov rcx, [r15+1*8]
    call .print_dec
    lea rcx, [rel s_label]
    call .print_cstr
    mov rcx, [r15+2*8]
    call .print_dec
    lea rcx, [rel s_ident]
    call .print_cstr
    mov rcx, [r15+3*8]
    call .print_dec
    lea rcx, [rel s_reg]
    call .print_cstr
    mov rcx, [r15+4*8]
    call .print_dec
    lea rcx, [rel s_num]
    call .print_cstr
    mov rcx, [r15+5*8]
    call .print_dec
    lea rcx, [rel s_str]
    call .print_cstr
    mov rcx, [r15+6*8]
    call .print_dec
    lea rcx, [rel s_lbr]
    call .print_cstr
    mov rcx, [r15+7*8]
    call .print_dec
    lea rcx, [rel s_rbr]
    call .print_cstr
    mov rcx, [r15+8*8]
    call .print_dec
    lea rcx, [rel s_comma]
    call .print_cstr
    mov rcx, [r15+9*8]
    call .print_dec
    lea rcx, [rel s_plus]
    call .print_cstr
    mov rcx, [r15+11*8]
    call .print_dec
    lea rcx, [rel s_minus]
    call .print_cstr
    mov rcx, [r15+12*8]
    call .print_dec
    lea rcx, [rel s_colon]
    call .print_cstr
    mov rcx, [r15+10*8]
    call .print_dec
    lea rcx, [rel s_star]
    call .print_cstr
    mov rcx, [r15+13*8]
    call .print_dec
    lea rcx, [rel s_slash]
    call .print_cstr
    mov rcx, [r15+14*8]
    call .print_dec
    lea rcx, [rel s_comm]
    call .print_cstr
    mov rcx, [r15+15*8]
    call .print_dec
    lea rcx, [rel s_unk]
    call .print_cstr
    mov rcx, [r15+16*8]
    call .print_dec
    lea rcx, [rel s_crlf]
    call .print_cstr
    ; dump completo (2ª passada; kind+texto p/ inspeção manual)
    xor ebx, ebx                   ; pos
.dump:
    cmp rbx, r12
    jae .dump_done
    mov rcx, r14
    mov rdx, r12
    mov r8, rbx
    lea r9, [rbp-104]
    sub rsp, 32
    call dex_lex_one
    add rsp, 32
    test rax, rax
    jz .dump_done
    mov [rbp-136], rax             ; consumidos
    lea rcx, [rel s_tpre]
    call .print_cstr
    mov ecx, [rbp-104+DexToken.kind]
    call .print_dec
    lea rcx, [rel s_sp]
    call .print_cstr
    mov ecx, [rbp-104+DexToken.line]
    call .print_dec
    lea rcx, [rel s_at]
    call .print_cstr
    mov ecx, [rbp-104+DexToken.col]
    call .print_dec
    lea rcx, [rel s_plusat]
    call .print_cstr
    mov rcx, rbx
    call .print_dec
    cmp dword [rbp-104+DexToken.kind], LEX_EOL
    je .dump_eol
    lea rcx, [rel s_sp]
    call .print_cstr
    lea rcx, [rel s_q]
    call .print_cstr
    mov rcx, [rbp-104+DexToken.ptr]
    mov r8, [rbp-104+DexToken.len]
    call .print_mem
    lea rcx, [rel s_q]
    call .print_cstr
    cmp dword [rbp-104+DexToken.kind], LEX_REG
    je .dump_val
    cmp dword [rbp-104+DexToken.kind], LEX_NUM
    jne .dump_eol
.dump_val:
    lea rcx, [rel s_eq0x]
    call .print_cstr
    mov rcx, [rbp-104+DexToken.val]
    call .print_hex
.dump_eol:
    lea rcx, [rel s_crlf]
    call .print_cstr
    mov rax, [rbp-136]
    add rbx, rax
    jmp .dump
.dump_done:
    mov rax, [r15+16*8]            ; unknowns
    test rax, rax
    jnz .have_unk
    xor ecx, ecx
    call ExitProcess
.have_unk:
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
; Helpers de saída (hOut em [rbp-112]; preservam rbx/r12-r15 do main).
; .print_cstr — rcx=cstr. .print_dec — rcx=u64. .print_mem — rcx=ptr,r8=len.
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
    mov qword [rsp+32], 0          ; overlapped NULL
    lea r9, [rsp+40]               ; &written (WriteFile exige válido)
    call WriteFile
    add rsp, 48
    pop rbx
    ret
.print_dec:
    push rbx
    mov rax, rcx
    lea rbx, [rbp-160]             ; tmp final (24B)
    test rax, rax
    jnz .pd_conv
    mov byte [rbx], '0'
    mov r8, 1
    jmp .pd_wr
.pd_conv:
    sub rsp, 40
    mov rcx, rsp                   ; dígitos reversos (até 20)
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
    mov rcx, r8                   ; n
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
    mov qword [rsp+32], 0          ; overlapped NULL
    lea r9, [rsp+40]               ; &written (WriteFile exige válido)
    call WriteFile
    add rsp, 48
    pop rbx
    ret
.print_hex:
    push rbx
    mov rax, rcx
    lea rbx, [rbp-160]             ; tmp final (24B)
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
    mov rcx, r8                   ; n
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
    mov qword [rsp+32], 0          ; overlapped NULL
    lea r9, [rsp+40]               ; &written (WriteFile exige válido)
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
    mov qword [rsp+32], 0          ; overlapped NULL
    lea r9, [rsp+40]               ; &written (WriteFile exige válido)
    call WriteFile
    add rsp, 48
    pop rbx
.pm_done:
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

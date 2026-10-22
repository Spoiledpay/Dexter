;=============================================================================
; Dexter/src/cli/parse_args.asm
; Parser da linha de comando (GetCommandLineA + tokenização própria).
;
; Requisitos atendidos: Projeto.md §2 (CLI completa)
; Testes: manual (dexter -h, dexter --help, dexter -ver, casos de erro -> 1)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"

global dex_parse_args

extern dex_strlen
extern dex_streq
extern dex_memcpy
extern dex_malloc
extern dex_free
extern dex_parse_hex_u64
extern dex_console_print_err
extern GetFileAttributesA

section .rodata
s_o           db "-o", 0
s_O           db "-O", 0
s_m           db "-m", 0
s_r           db "-r", 0
s_L           db "-L", 0
s_N           db "-N", 0
s_s           db "-s", 0
s_start       db "-start", 0
s_end         db "-end", 0
s_hex         db "-hex", 0
s_noppad      db "-nop-pad", 0
s_noimports   db "-no-imports", 0
s_norelocs    db "-no-relocs", 0
s_strings     db "-strings", 0
s_native      db "-native", 0
s_emit        db "-emit", 0
s_emit_db     db "db", 0
s_emit_native db "native", 0
s_astdump     db "-ast-dump", 0
s_overview    db "-overview", 0
s_json        db "-json", 0
s_func        db "-func", 0
s_xrefs       db "-xrefs", 0
s_trace       db "-trace", 0
s_depth       db "-depth", 0
s_rsrc        db "-rsrc", 0
s_doctor      db "-doctor", 0
s_doctor2     db "--doctor", 0
s_snapshot    db "-snapshot", 0
s_compare     db "-compare", 0
s_v           db "-v", 0
s_vv          db "-vv", 0
s_q           db "-q", 0
s_ver         db "-ver", 0
s_h           db "-h", 0
s_help        db "--help", 0
s_win64       db "win64", 0
s_bin         db "bin", 0
s_dotasm      db ".asm", 0
s_def_nasm    db "C:\Nasm\nasm.exe", 0
s_def_link    db "C:\Nasm\link.exe", 0
s_bare_nasm   db "nasm.exe", 0
s_bare_link   db "link.exe", 0
e_no_input    db "dexter: no input file (use -h for help)", 13, 10, 0
e_opt_val     db "dexter: option requires a value", 13, 10, 0
e_bad_opt     db "dexter: unknown option", 13, 10, 0
e_dup_input   db "dexter: more than one input file", 13, 10, 0
e_bad_mode    db "dexter: -m must be win64 or bin", 13, 10, 0
e_oom         db "dexter: out of memory (args)", 13, 10, 0
e_bin_mode    db "dexter: -m bin not supported yet (see docs/ROADMAP.md phase 5)", 13, 10, 0
e_bad_hex     db "dexter: invalid hex value (use 0x...)", 13, 10, 0
e_bad_emit    db "dexter: -emit must be db or native", 13, 10, 0
e_bad_depth   db "dexter: -depth must be 1..64 (use 0x...)", 13, 10, 0

section .text

;-----------------------------------------------------------------------------
; dex_parse_args
; Args:   rcx = DexConfig* (zerado pelo chamador)
; Ret:    rax = 0 ok | 1 erro uso | 2 help | 3 version
; Preenche cfg com defaults (nasm/link) e deriva output_asm=<input>.asm.
;-----------------------------------------------------------------------------
dex_parse_args:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88               ; 7 pushes -> rsp%16==0; 96%16==0 => ok
    mov r15, rcx              ; cfg
    ; defaults: C:\Nasm\... se existir; senao nasm.exe/link.exe via PATH
    ; (CI e instalacoes sem C:\Nasm). -N/-L continuam sobrescrevendo.
    lea rcx, [rel s_def_nasm]
    sub rsp, 32
    call GetFileAttributesA
    add rsp, 32
    cmp eax, -1
    je .def_nasm_bare
    lea rax, [rel s_def_nasm]
    jmp .def_nasm_set
.def_nasm_bare:
    lea rax, [rel s_bare_nasm]
.def_nasm_set:
    mov [r15+DexConfig.nasm_path], rax
    lea rcx, [rel s_def_link]
    sub rsp, 32
    call GetFileAttributesA
    add rsp, 32
    cmp eax, -1
    je .def_link_bare
    lea rax, [rel s_def_link]
    jmp .def_link_set
.def_link_bare:
    lea rax, [rel s_bare_link]
.def_link_set:
    mov [r15+DexConfig.linker_path], rax
    mov dword [r15+DexConfig.mode], DEX_MODE_WIN64
    ; obter linha de comando (2 pushes? não — dentro do frame)
    sub rsp, 32
    call GetCommandLineA
    add rsp, 32
    test rax, rax
    jz .err_usage
    mov r14, rax              ; cmdline (somente leitura!)
    ; copiar p/ buffer mutável (até 32768)
    mov rcx, 32768
    call dex_malloc
    test rax, rax
    jz .err_usage
    mov r13, rax              ; buf (base p/ free)
    mov rbx, rax              ; dst
    mov rsi, r14              ; src
    lea r11, [r13+32760]      ; end (r11 livre: sem calls neste loop)
.copy_cl:
    cmp rbx, r11
    jae .trunc_cl
    mov al, [rsi]
    mov [rbx], al
    test al, al
    jz .tok_start
    inc rsi
    inc rbx
    jmp .copy_cl
.trunc_cl:
    mov byte [r13+32767], 0   ; trunca com NUL no fim do buffer
    jmp .tok_start
.tok_start:
    ; tokenizar: parsing direto com cursor, sem argv: pular argv[0], depois loop.
    mov dword [rbp-72], 0        ; contador de tokens (p/ banner em linha vazia)
    mov r12, r13              ; cursor
    ; pular argv[0] (respeitando aspas)
    movzx eax, byte [r12]
    cmp al, 34               ; '"'
    je .skip0q
.skip0:
    movzx eax, byte [r12]
    test al, al
    jz .ret_banner            ; só o exe, sem nada: banner (ret 4)
    cmp al, 32
    je .args_begin
    cmp al, 9
    je .args_begin
    inc r12
    jmp .skip0
.skip0q:
    inc r12
.skip0q_l:
    movzx eax, byte [r12]
    test al, al
    jz .ret_banner
    cmp al, 34
    je .skip0q_e
    inc r12
    jmp .skip0q_l
.skip0q_e:
    inc r12
.args_begin:
    ; loop: pular espaços, extrair token (com aspas), classificar
.next_tok:
    ; pular ws
.ws:
    movzx eax, byte [r12]
    test al, al
    jz .end_args
    cmp al, 32
    je .ws_n
    cmp al, 9
    je .ws_n
    jmp .tok
.ws_n:
    inc r12
    jmp .ws
.tok:
    ; rdi = início do token (sem aspas); respeitar "..."
    movzx eax, byte [r12]
    cmp al, 34
    je .tok_q
    mov rdi, r12
.tok_plain_l:
    movzx eax, byte [r12]
    test al, al
    jz .tok_end
    cmp al, 32
    je .tok_end
    cmp al, 9
    je .tok_end
    inc r12
    jmp .tok_plain_l
.tok_q:
    inc r12
    mov rdi, r12
.tok_q_l:
    movzx eax, byte [r12]
    test al, al
    jz .tok_end
    cmp al, 34
    je .tok_q_e
    inc r12
    jmp .tok_q_l
.tok_q_e:
    mov byte [r12], 0
    inc r12
    jmp .classify
.tok_end:
    movzx eax, byte [r12]
    test al, al
    jz .classify_noskip     ; fim de string: não avançar
    mov byte [r12], 0
    inc r12
    jmp .classify
.classify_noskip:
    ; rdi = token, r12 aponta p/ NUL final
.classify:
    ; token vazio? (ex.: "") -> ignora
    cmp byte [rdi], 0
    je .next_tok
    mov rbx, rdi             ; token atual
    ; chamar classificador (consome próximo token p/ -o etc.)
    mov rcx, r15            ; cfg
    mov rdx, rbx            ; tok
    mov r8, r12             ; cursor (p/ opções com valor avançarem)
    sub rsp, 64
    call .classify_one
    add rsp, 64
    ; rax: 0=ok(cursor em rdx), 1=erro, 2=help, 3=version
    cmp rax, 1
    je .err_usage_free
    cmp rax, 2
    je .ret_help
    cmp rax, 3
    je .ret_ver
    ; rax==0: rdx = novo cursor
    mov r12, rdx
    inc dword [rbp-72]         ; +1 token classificado
    jmp .next_tok
.end_args:
    ; validar input (linha vazia via .args_begin -> banner, não erro)
    cmp qword [r15+DexConfig.input_path], 0
    jne .has_input
    cmp dword [rbp-72], 0
    je .ret_banner
    jmp .no_input_free
.has_input:
    ; derivar output_asm se ausente
    cmp qword [r15+DexConfig.output_asm], 0
    jne .ok
    mov rcx, r15
    sub rsp, 32
    call .derive_asm
    add rsp, 32
    test eax, eax
    jnz .err_usage_free
.ok:
    mov rcx, r13
    sub rsp, 32
    call dex_free
    add rsp, 32
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
.no_input:
    lea rcx, [rel e_no_input]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
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
.no_input_free:
    lea rcx, [rel e_no_input]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    jmp .err_usage_free
.err_usage:
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
.err_usage_free:
    mov rcx, r13
    sub rsp, 32
    call dex_free
    add rsp, 32
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
.ret_help:
    mov rcx, r13
    sub rsp, 32
    call dex_free
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
.ret_ver:
    mov rcx, r13
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov eax, 3
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
.ret_banner:
    mov rcx, r13
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov eax, 4
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
; .classify_one (interna)
; rcx=cfg, rdx=tok, r8=cursor
; Ret: rax=0/1/2/3; rdx=novo cursor (se valor consumido)
; Usa rbx preservado? NÃO — usa só voláteis + r15(cfg global no frame).
; CUIDADO: chamada com sub rsp,64 acima; aqui podemos usar frame próprio.
;-----------------------------------------------------------------------------
.classify_one:
    push rbp
    mov rbp, rsp
    push r15                  ; cfg (redundante, mas seguro)
    push rbx
    push r14
    push r12
    sub rsp, 48
    mov r15, rcx
    mov rbx, rdx              ; tok
    mov r12, r8               ; cursor
    ; -h / --help
    lea rcx, [rel s_h]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_help
    ; (comparações seguintes usam helper local .eq)
    lea rcx, [rel s_help]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_help
    lea rcx, [rel s_ver]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_ver
    lea rcx, [rel s_o]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_o
    lea rcx, [rel s_O]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_O
    lea rcx, [rel s_m]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_m
    lea rcx, [rel s_r]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_r
    lea rcx, [rel s_L]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_L
    lea rcx, [rel s_N]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_N
    lea rcx, [rel s_s]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_s
    lea rcx, [rel s_start]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_start
    lea rcx, [rel s_end]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_end
    lea rcx, [rel s_hex]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_hex
    lea rcx, [rel s_noppad]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_noppad
    lea rcx, [rel s_noimports]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_noimports
    lea rcx, [rel s_norelocs]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_norelocs
    lea rcx, [rel s_strings]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_strings
    lea rcx, [rel s_native]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_native
    lea rcx, [rel s_emit]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_emit
    lea rcx, [rel s_astdump]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_astdump
    lea rcx, [rel s_overview]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_overview
    lea rcx, [rel s_json]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_json
    lea rcx, [rel s_func]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_func
    lea rcx, [rel s_xrefs]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_xrefs
    lea rcx, [rel s_trace]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_trace
    lea rcx, [rel s_depth]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_depth
    lea rcx, [rel s_rsrc]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_rsrc
    lea rcx, [rel s_doctor]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_doctor
    lea rcx, [rel s_doctor2]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_doctor
    lea rcx, [rel s_snapshot]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_snapshot
    lea rcx, [rel s_compare]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_compare
    lea rcx, [rel s_v]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_v
    lea rcx, [rel s_vv]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_vv
    lea rcx, [rel s_q]
    mov rdx, rbx
    call .eq
    test eax, eax
    jnz .c_q
    ; começa com '-'? -> desconhecida
    cmp byte [rbx], 45        ; '-'
    je .c_unknown
    ; posicional = input (duplicar: buffer cmdline será liberado!)
    cmp qword [r15+DexConfig.input_path], 0
    jne .c_dup
    mov rcx, rbx
    sub rsp, 32
    call .dup_str
    add rsp, 32
    test rax, rax
    jz .c_oom
    mov [r15+DexConfig.input_path], rax
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_help:
    mov rdx, r12
    mov eax, 2
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_ver:
    mov rdx, r12
    mov eax, 3
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_o:
    call .next_val             ; rax=ptr ou 0; rdx=cursor novo
    test rax, rax
    jz .c_errval
    mov rcx, rax
    sub rsp, 32
    call .dup_str
    add rsp, 32
    test rax, rax
    jz .c_oom
    mov [r15+DexConfig.output_asm], rax
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_O:
    call .next_val
    test rax, rax
    jz .c_errval
    mov rcx, rax
    sub rsp, 32
    call .dup_str
    add rsp, 32
    test rax, rax
    jz .c_oom
    mov [r15+DexConfig.output_exe], rax
    or dword [r15+DexConfig.flags], DF_REBUILD
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_m:
    call .next_val
    test rax, rax
    jz .c_errval
    mov [rbp-48], rdx          ; spill cursor (r14/.eq clobberam rdx)
    mov r14, rax
    lea rcx, [rel s_win64]
    mov rdx, r14
    call .eq
    test eax, eax
    jnz .m_win
    lea rcx, [rel s_bin]
    mov rdx, r14
    call .eq
    test eax, eax
    jnz .m_bin
    lea rcx, [rel e_bad_mode]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 1
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.m_win:
    mov dword [r15+DexConfig.mode], DEX_MODE_WIN64
    mov rdx, [rbp-48]
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.m_bin:
    mov dword [r15+DexConfig.mode], DEX_MODE_BIN
    mov rdx, [rbp-48]
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_r:
    or dword [r15+DexConfig.flags], DF_REBUILD
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_L:
    call .next_val
    test rax, rax
    jz .c_errval
    mov rcx, rax
    sub rsp, 32
    call .dup_str
    add rsp, 32
    test rax, rax
    jz .c_oom
    mov [r15+DexConfig.linker_path], rax
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_N:
    call .next_val
    test rax, rax
    jz .c_errval
    mov rcx, rax
    sub rsp, 32
    call .dup_str
    add rsp, 32
    test rax, rax
    jz .c_oom
    mov [r15+DexConfig.nasm_path], rax
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_s:
    call .next_val
    test rax, rax
    jz .c_errval
    mov rcx, rax
    sub rsp, 32
    call .dup_str
    add rsp, 32
    test rax, rax
    jz .c_oom
    mov [r15+DexConfig.section_filter], rax
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_start:
    call .next_val
    test rax, rax
    jz .c_errval
    mov [rbp-48], rdx          ; spill cursor (hex parse clobbera rdx)
    mov rcx, rax
    sub rsp, 32
    call dex_parse_hex_u64
    add rsp, 32
    test edx, edx
    jz .c_badhex
    mov [r15+DexConfig.start_rva], rax
    mov byte [r15+DexConfig.has_start], 1
    mov rdx, [rbp-48]
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_end:
    call .next_val
    test rax, rax
    jz .c_errval
    mov [rbp-48], rdx          ; spill cursor
    mov rcx, rax
    sub rsp, 32
    call dex_parse_hex_u64
    add rsp, 32
    test edx, edx
    jz .c_badhex
    mov [r15+DexConfig.end_rva], rax
    mov byte [r15+DexConfig.has_end], 1
    mov rdx, [rbp-48]
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_hex:
    or dword [r15+DexConfig.flags], DF_HEXDUMP
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_noppad:
    or dword [r15+DexConfig.flags], DF_NOP_PAD
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_noimports:
    or dword [r15+DexConfig.flags], DF_NO_IMPORTS
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_norelocs:
    or dword [r15+DexConfig.flags], DF_NO_RELOCS
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_strings:
    or dword [r15+DexConfig.flags], DF_STRINGS
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_native:
    or dword [r15+DexConfig.flags], DF_NATIVE
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_emit:
    ; -emit db|native (R-6.5): forma explícita do emissor; -native segue
    ; como alias. Last-wins entre ambos (documentado em docs/CLI.md).
    call .next_val
    test rax, rax
    jz .c_errval
    mov [rbp-48], rax          ; spill token (eq/call matam rax)
    lea rcx, [rel s_emit_native]
    mov rdx, [rbp-48]
    sub rsp, 32
    call .eq
    add rsp, 32
    test eax, eax
    jnz .c_emit_nat
    lea rcx, [rel s_emit_db]
    mov rdx, [rbp-48]
    sub rsp, 32
    call .eq
    add rsp, 32
    test eax, eax
    jz .c_bad_emit
    and dword [r15+DexConfig.flags], ~DF_NATIVE  ; -emit db
    jmp .c_emit_ok
.c_emit_nat:
    or dword [r15+DexConfig.flags], DF_NATIVE    ; -emit native
.c_emit_ok:
    mov rdx, r12               ; cursor (next_val já avançou r12)
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_bad_emit:
    lea rcx, [rel e_bad_emit]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 1
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_astdump:
    or dword [r15+DexConfig.flags], DF_ASTDUMP
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_overview:
    or dword [r15+DexConfig.flags], DF_OVERVIEW
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_json:
    or dword [r15+DexConfig.flags], DF_JSON
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_func:
    call .next_val
    test rax, rax
    jz .c_errval
    mov [rbp-48], rdx          ; spill cursor (hex parse clobbera rdx)
    mov rcx, rax
    sub rsp, 32
    call dex_parse_hex_u64
    add rsp, 32
    test edx, edx
    jz .c_badhex
    mov [r15+DexConfig.func_addr], rax
    mov byte [r15+DexConfig.has_func], 1
    or dword [r15+DexConfig.flags], DF_FUNC
    mov rdx, [rbp-48]
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_xrefs:
    call .next_val
    test rax, rax
    jz .c_errval
    mov [rbp-48], rdx
    mov rcx, rax
    sub rsp, 32
    call dex_parse_hex_u64
    add rsp, 32
    test edx, edx
    jz .c_badhex
    mov [r15+DexConfig.xrefs_addr], rax
    mov byte [r15+DexConfig.has_xrefs], 1
    or dword [r15+DexConfig.flags], DF_XREFS
    mov rdx, [rbp-48]
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_trace:
    call .next_val
    test rax, rax
    jz .c_errval
    mov [rbp-48], rdx
    mov rcx, rax
    sub rsp, 32
    call dex_parse_hex_u64
    add rsp, 32
    test edx, edx
    jz .c_badhex
    mov [r15+DexConfig.trace_addr], rax
    mov byte [r15+DexConfig.has_trace], 1
    or dword [r15+DexConfig.flags], DF_TRACE
    mov rdx, [rbp-48]
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_depth:
    call .next_val
    test rax, rax
    jz .c_errval
    mov [rbp-48], rdx
    mov rcx, rax
    sub rsp, 32
    call dex_parse_hex_u64
    add rsp, 32
    test edx, edx
    jz .c_badhex
    cmp rax, 1
    jb .c_baddepth
    cmp rax, 64
    ja .c_baddepth
    mov [r15+DexConfig.depth], rax
    mov byte [r15+DexConfig.has_depth], 1
    mov rdx, [rbp-48]
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_v:
    mov dword [r15+DexConfig.verbose], 1
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_vv:
    mov dword [r15+DexConfig.verbose], 2
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_q:
    mov dword [r15+DexConfig.quiet], 1
    or dword [r15+DexConfig.flags], DF_QUIET
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_unknown:
    lea rcx, [rel e_bad_opt]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 1
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_dup:
    lea rcx, [rel e_dup_input]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 1
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_errval:
    lea rcx, [rel e_opt_val]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 1
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_badhex:
    lea rcx, [rel e_bad_hex]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 1
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_baddepth:
    lea rcx, [rel e_bad_depth]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 1
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_rsrc:
    or dword [r15+DexConfig.flags], DF_RSRC
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_doctor:
    or dword [r15+DexConfig.flags], DF_DOCTOR
    mov rdx, r12
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_snapshot:
    call .next_val
    test rax, rax
    jz .c_errval
    mov rcx, rax
    sub rsp, 32
    call .dup_str
    add rsp, 32
    test rax, rax
    jz .c_oom
    mov [r15+DexConfig.snapshot_path], rax
    or dword [r15+DexConfig.flags], DF_SNAP
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret
.c_compare:
    call .next_val
    test rax, rax
    jz .c_errval
    mov rcx, rax
    sub rsp, 32
    call .dup_str
    add rsp, 32
    test rax, rax
    jz .c_oom
    mov [r15+DexConfig.compare_path], rax
    or dword [r15+DexConfig.flags], DF_CMP
    xor eax, eax
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret

; .eq local: rcx=a, rdx=b -> eax 1/0 (chama dex_streq sem frame extra)
.eq:
    sub rsp, 32
    call dex_streq
    add rsp, 32
    ret

; .next_val: extrai próximo token do cursor r12 (pula ws, respeita aspas).
; Ret: rax=ptr ou 0; rdx=cursor após o token.
.next_val:
    push r14
    push rbx
.ws_v:
    movzx eax, byte [r12]
    test al, al
    jz .nv_none
    cmp al, 32
    je .ws_vn
    cmp al, 9
    je .ws_vn
    jmp .tk_v
.ws_vn:
    inc r12
    jmp .ws_v
.tk_v:
    cmp al, 34
    je .tk_vq
    mov rax, r12
.tk_vl:
    movzx ebx, byte [r12]
    test bl, bl
    jz .tk_ve
    cmp bl, 32
    je .tk_ve
    cmp bl, 9
    je .tk_ve
    inc r12
    jmp .tk_vl
.tk_ve:
    test bl, bl
    jz .tk_vdone
    mov byte [r12], 0
    inc r12
.tk_vdone:
    mov rdx, r12
    pop rbx
    pop r14
    ret
.tk_vq:
    inc r12
    mov rax, r12
.tk_vql:
    movzx ebx, byte [r12]
    test bl, bl
    jz .tk_vdone
    cmp bl, 34
    je .tk_vqe
    inc r12
    jmp .tk_vql
.tk_vqe:
    mov byte [r12], 0
    inc r12
    mov rdx, r12
    pop rbx
    pop r14
    ret
.nv_none:
    xor eax, eax
    mov rdx, r12
    pop rbx
    pop r14
    ret

; .c_oom — erro de alocação em opção: imprime e retorna 1
.c_oom:
    lea rcx, [rel e_oom]
    sub rsp, 32
    call dex_console_print_err
    add rsp, 32
    mov eax, 1
    add rsp, 48
    pop r12
    pop r14
    pop rbx
    pop r15
    pop rbp
    ret

; .dup_str — rcx=cstr -> rax=cópia heap (NUL) ou 0 (OOM)
; Preserva rbx, rdx, r12 (cursor do chamador sobrevive).
.dup_str:
    push rbp
    mov rbp, rsp
    push rbx
    push rdx
    push r12
    sub rsp, 40
    mov rbx, rcx
    test rbx, rbx
    jz .dup_no
    sub rsp, 32
    call dex_strlen
    add rsp, 32
    mov r12, rax               ; len (sem NUL)
    lea rcx, [rax+1]
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .dup_no
    mov rcx, rax
    mov rdx, rbx
    mov r8, r12
    add r8, 1                  ; +NUL (dentro do buffer tokenizado)
    sub rsp, 32
    call dex_memcpy
    add rsp, 32
    add rsp, 40
    pop r12
    pop rdx
    pop rbx
    pop rbp
    ret
.dup_no:
    xor eax, eax
    add rsp, 40
    pop r12
    pop rdx
    pop rbx
    pop rbp
    ret

; .derive_asm: rcx=cfg — aloca "<input sem ext>.asm". Ret eax=0 ok.
; Preserva r15 do chamador (usa slot de pilha p/ cfg).
.derive_asm:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    sub rsp, 40                ; 7 pushes -> rsp%16==0; 40%16==8 => call alinhado
    mov [rbp-56], rcx          ; salva cfg (slot livre abaixo dos pushes)
    mov rbx, [rcx+DexConfig.input_path]
    mov rcx, rbx
    call dex_strlen            ; rax = len
    mov r12, rax
    ; achar fim do basename e último ponto
    mov rsi, rbx
    add rsi, r12               ; fim
    mov rdi, rsi               ; last_dot = 0
    xor r13, r13
    mov rdx, rbx               ; last_sep
    mov r14, rbx
.scan_d:
    cmp r14, rsi
    jae .scan_e
    movzx eax, byte [r14]
    cmp al, 92                 ; '\'
    je .sep_d
    cmp al, 47                 ; '/'
    je .sep_d
    cmp al, 46                 ; '.'
    je .dot_d
    inc r14
    jmp .scan_d
.sep_d:
    mov rdx, r14
    inc r14
    jmp .scan_d
.dot_d:
    mov rdi, r14
    inc r14
    jmp .scan_d
.scan_e:
    ; base_len = (dot válido após sep) ? dot-input : len
    mov rax, r12               ; default: troca nada, anexa
    cmp rdi, rsi
    je .no_dot
    cmp rdi, rdx
    jbe .no_dot
    ; tem ponto após separador: cortar nele
    mov rax, rdi
    sub rax, rbx
    jmp .have_bl
.no_dot:
    mov rax, r12
.have_bl:
    mov r13, rax               ; base_len
    lea rcx, [r13+5]           ; + ".asm" + NUL
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .d_fail
    mov r14, rax
    mov rcx, r14
    mov rdx, rbx
    mov r8, r13
    sub rsp, 32
    call dex_memcpy
    add rsp, 32
    lea rsi, [rel s_dotasm]    ; ".asm\0" (4+1)
    mov rcx, r14
    add rcx, r13
    mov edx, [rsi]
    mov [rcx], edx
    movzx edx, byte [rsi+4]
    mov [rcx+4], dl
    mov rdx, [rbp-56]          ; cfg
    mov [rdx+DexConfig.output_asm], r14
    jmp .d_ok
.d_fail:
    mov eax, 1
    add rsp, 40
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.d_ok:
    xor eax, eax
    add rsp, 40
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

extern dex_streq
extern dex_strlen
extern dex_memcpy
extern dex_malloc
extern dex_parse_hex_u64
extern dex_console_print_err

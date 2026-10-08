;=============================================================================
; Dexter/tests/lift_check.asm
; Driver de teste do lifter (R-6.4 fatia 1): 12 Insns craftados (sem file
; I/O, sem deps do produto além de lift.obj) via dex_lift_insn, com
; PeImage/seções/imports fakes, e imprime 2 linhas golden:
;   LIFT db=1 instr=3 call=3 callimp=1 jmp=1 jmpimp=1 branch=1 ret=1
;   TKIND none=4 code=3 data=2 import=3
; Retorno: 0 se tudo confere com o esperado interno, 2 em divergência.
; (O run_tests.bat [11] ainda pina as 2 linhas via findstr.)
;
; Requisitos atendidos: R-6.4 (lift DexOp->IR)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global main

extern GetStdHandle
extern WriteFile
extern ExitProcess
extern dex_lift_insn

section .rodata
s_l0     db "LIFT db=", 0
s_l1     db " instr=", 0
s_l2     db " call=", 0
s_l3     db " callimp=", 0
s_l4     db " jmp=", 0
s_l5     db " jmpimp=", 0
s_l6     db " branch=", 0
s_l7     db " ret=", 0
s_t0     db "TKIND none=", 0
s_t1     db " code=", 0
s_t2     db " data=", 0
s_t3     db " import=", 0
s_crlf   db 13, 10, 0
s_mne    db "x", 0
s_dll    db "KERNEL32.dll", 0
s_fn0    db "LoadLibraryA", 0
s_fn1    db "GetProcAddress", 0

section .data
align 8
; ---- seções fakes: .text CODE 0x1000-0x2000, .data 0x2000-0x2200 ----
fake_secs:
    db ".text", 0, 0, 0
    dd 0x1000, 0x1000, 0x1000, 0x400, 0x60000020, 0
    db ".data", 0, 0, 0
    dd 0x200, 0x2000, 0x200, 0x1400, 0xC0000040, 0
; ---- imports fakes: #0 iat 0x2100, #1 iat 0x2108 ----
fake_imps:
    dq s_dll, s_fn0                  ; dll_name, func_name
    dw 0                             ; ordinal
    db 0                             ; is_ordinal
    db 0, 0, 0, 0, 0                 ; pad
    dd 0x2100                        ; iat_rva
    dd 0                             ; pad2
    dq s_dll, s_fn1
    dw 0
    db 0
    db 0, 0, 0, 0, 0
    dd 0x2108
    dd 0
; ---- PeImage fake ----
fake_img:
    dq 0, 0                                  ; file_buffer, file_size
    dq 0x140000000                           ; image_base
    dq 0x1000                                ; entry_point (RVA)
    dd 2, 0                                  ; num_sections
    dq fake_secs                             ; sections_ptr
    dq fake_imps                             ; imports_ptr
    dd 2, 0                                  ; imports_count
    dq 0, 0                                  ; exports, relocs
    dd 0, 0
    dq 0, 0, 0                               ; opt_header, nt_headers
    dd 1, 0                                  ; is_valid
fake_ctx:
    dq fake_img

section .bss
align 8
g_insns: resb 1920               ; 12 x SIZEOF_INSN (160)
g_ir:    resb SIZEOF_IR

section .text

;-----------------------------------------------------------------------------
; main — crafta 12 Insns, lifta, conta cls/tkind, imprime e confere.
; Frame: 3 pushes + sub 144 (24+144=168 ≡ 8: antes de call, rsp%16==0).
; Slots (área sub [rbp-168,-24), fora dos salvos [rbp-24,rbp)):
;   hOut [rbp-32,-24), cls[8] [rbp-96,-32), tkind[4] [rbp-128,-96),
;   dec-tmp 24B [rbp-152,-128).
;-----------------------------------------------------------------------------
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r14                     ; 3 pushes (24B) + sub 144 = 168 ≡ 8:
                                 ; antes de call, rsp%16==0 (rdi/rsi/r12/r13/
                                 ; r15 não são usados aqui — sem push inútil)
    sub rsp, 144
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-32], rax              ; hOut
    ; ---- crafta insns (repetição explícita, sem macros) ----
    ; i0: mne=0 -> DB (resto zero do .bss)
    ; i1: mov reg,reg -> INSTR/NONE
    lea rax, [rel g_insns+160*1]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_REG
    ; i2: E8 call rel code -> CALL/CODE
    lea rax, [rel g_insns+160*2]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0xE8
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.is_call], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_REL
    mov rdx, 0x140001500
    mov [rax+Insn.op0+DexOp.val], rdx
    ; i3: FF15 call [rip=IAT#0] -> CALLIMP/IMPORT
    lea rax, [rel g_insns+160*3]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0xFF
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.is_call], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_MEM
    mov byte [rax+Insn.op0+DexOp.base], DEX_NOBASE
    mov rdx, 0x140002100
    mov [rax+Insn.op0+DexOp.val], rdx
    ; i4: FF15 call [rip=dados] -> CALL/DATA
    lea rax, [rel g_insns+160*4]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0xFF
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.is_call], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_MEM
    mov byte [rax+Insn.op0+DexOp.base], DEX_NOBASE
    mov rdx, 0x140002050
    mov [rax+Insn.op0+DexOp.val], rdx
    ; i5: FFD0 call rax -> CALL/NONE
    lea rax, [rel g_insns+160*5]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0xFF
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.is_call], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_REG
    ; i6: E9 jmp rel -> JMP/CODE
    lea rax, [rel g_insns+160*6]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0xE9
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.is_branch], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_REL
    mov rdx, 0x140001600
    mov [rax+Insn.op0+DexOp.val], rdx
    ; i7: 0F84 jz rel -> BRANCH/CODE
    lea rax, [rel g_insns+160*7]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0x84
    mov dword [rax+Insn.opcode_len], 2
    mov byte [rax+Insn.is_branch], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_REL
    mov rdx, 0x140001700
    mov [rax+Insn.op0+DexOp.val], rdx
    ; i8: FF25 jmp [rip=IAT#1] -> JMPIMP/IMPORT
    lea rax, [rel g_insns+160*8]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0xFF
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.is_branch], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_MEM
    mov byte [rax+Insn.op0+DexOp.base], DEX_NOBASE
    mov rdx, 0x140002108
    mov [rax+Insn.op0+DexOp.val], rdx
    ; i9: C3 ret -> RET/NONE
    lea rax, [rel g_insns+160*9]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0xC3
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.is_ret], 1
    ; i10: 8B mov reg,[rip=dados] -> INSTR/DATA
    lea rax, [rel g_insns+160*10]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0x8B
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_REG
    mov byte [rax+Insn.op1+DexOp.kind], DEX_OP_MEM
    mov byte [rax+Insn.op1+DexOp.base], DEX_NOBASE
    mov rdx, 0x140002050
    mov [rax+Insn.op1+DexOp.val], rdx
    ; i11: 8B mov reg,[rip=IAT#0] -> INSTR/IMPORT
    lea rax, [rel g_insns+160*11]
    lea rcx, [rel s_mne]
    mov [rax+Insn.mne], rcx
    mov dword [rax+Insn.opcode], 0x8B
    mov dword [rax+Insn.opcode_len], 1
    mov byte [rax+Insn.op0+DexOp.kind], DEX_OP_REG
    mov byte [rax+Insn.op1+DexOp.kind], DEX_OP_MEM
    mov byte [rax+Insn.op1+DexOp.base], DEX_NOBASE
    mov rdx, 0x140002100
    mov [rax+Insn.op1+DexOp.val], rdx
    ; ---- lifta as 12, conta cls[8] ([rbp-96,-32)) e tkind[4] ([rbp-128,-96))
    xor eax, eax
    mov [rbp-96], rax
    mov [rbp-88], rax
    mov [rbp-80], rax
    mov [rbp-72], rax
    mov [rbp-64], rax
    mov [rbp-56], rax
    mov [rbp-48], rax
    mov [rbp-40], rax
    mov [rbp-128], rax
    mov [rbp-120], rax
    mov [rbp-112], rax
    mov [rbp-104], rax
    xor r14d, r14d                 ; i
.lift_l:
    cmp r14d, 12
    jae .lift_done
    mov eax, r14d
    imul eax, 160
    lea rcx, [rel g_insns]
    add rcx, rax                   ; insn
    lea rdx, [rel fake_ctx]
    lea r8, [rel g_ir]
    sub rsp, 32
    call dex_lift_insn
    add rsp, 32
    test eax, eax
    jnz .fail
    mov eax, [g_ir+DexIR.cls]
    cmp eax, 8
    jae .fail
    lea rcx, [rbp-96]
    inc qword [rcx+rax*8]          ; cls[eax]++
    mov eax, [g_ir+DexIR.tkind]
    cmp eax, 4
    jae .fail
    lea rcx, [rbp-128]
    inc qword [rcx+rax*8]          ; tkind[eax]++
    inc r14d
    jmp .lift_l
.lift_done:
    ; ---- imprime LIFT + TKIND ----
    lea rcx, [rel s_l0]
    call .print_cstr
    mov rcx, [rbp-96]              ; db
    call .print_dec
    lea rcx, [rel s_l1]
    call .print_cstr
    mov rcx, [rbp-88]              ; instr
    call .print_dec
    lea rcx, [rel s_l2]
    call .print_cstr
    mov rcx, [rbp-80]              ; call
    call .print_dec
    lea rcx, [rel s_l3]
    call .print_cstr
    mov rcx, [rbp-72]              ; callimp
    call .print_dec
    lea rcx, [rel s_l4]
    call .print_cstr
    mov rcx, [rbp-64]              ; jmp
    call .print_dec
    lea rcx, [rel s_l5]
    call .print_cstr
    mov rcx, [rbp-56]              ; jmpimp
    call .print_dec
    lea rcx, [rel s_l6]
    call .print_cstr
    mov rcx, [rbp-48]              ; branch
    call .print_dec
    lea rcx, [rel s_l7]
    call .print_cstr
    mov rcx, [rbp-40]              ; ret
    call .print_dec
    lea rcx, [rel s_crlf]
    call .print_cstr
    lea rcx, [rel s_t0]
    call .print_cstr
    mov rcx, [rbp-128]             ; none
    call .print_dec
    lea rcx, [rel s_t1]
    call .print_cstr
    mov rcx, [rbp-120]             ; code
    call .print_dec
    lea rcx, [rel s_t2]
    call .print_cstr
    mov rcx, [rbp-112]             ; data
    call .print_dec
    lea rcx, [rel s_t3]
    call .print_cstr
    mov rcx, [rbp-104]             ; import
    call .print_dec
    lea rcx, [rel s_crlf]
    call .print_cstr
    ; ---- confere goldens internos (db=1 instr=3 call=3 callimp=1 jmp=1
    ;      jmpimp=1 branch=1 ret=1; none=4 code=3 data=2 import=3) ----
    cmp qword [rbp-96], 1
    jne .fail
    cmp qword [rbp-88], 3
    jne .fail
    cmp qword [rbp-80], 3
    jne .fail
    cmp qword [rbp-72], 1
    jne .fail
    cmp qword [rbp-64], 1
    jne .fail
    cmp qword [rbp-56], 1
    jne .fail
    cmp qword [rbp-48], 1
    jne .fail
    cmp qword [rbp-40], 1
    jne .fail
    cmp qword [rbp-128], 4
    jne .fail
    cmp qword [rbp-120], 3
    jne .fail
    cmp qword [rbp-112], 2
    jne .fail
    cmp qword [rbp-104], 3
    jne .fail
    xor ecx, ecx
    call ExitProcess
.fail:
    mov ecx, 2
    call ExitProcess

;-----------------------------------------------------------------------------
; Helpers de saída (hOut em [rbp-32]; dec-tmp 24B em [rbp-152,-128)).
;-----------------------------------------------------------------------------
.print_cstr:
    push rbx
    mov rbx, rcx
    mov rcx, rbx
    call .strlen_loc
    mov r8, rax
    mov rdx, rbx
    mov rcx, [rbp-32]              ; hOut
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
    lea rbx, [rbp-152]
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
    mov rcx, [rbp-32]              ; hOut
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

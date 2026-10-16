;=============================================================================
; Dexter/tests/unwind_check.asm
; Driver de teste do parser SEH/unwind (R-5.4 F1): PeImage/sections FILE
; craftados em memória (sem I/O), com 2 RUNTIME_FUNCTION e 2 UNWIND_INFO
; (um simples, um com EHANDLER). Confere campos decodificados + casos de
; borda (índice fora, rva fora) e imprime "UNWIND OK count=2".
; Retorno: 0 se tudo confere, 2 em divergência.
;
; Requisitos atendidos: R-5.4 (SEH/unwind, F1)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global main

extern GetStdHandle
extern WriteFile
extern ExitProcess
extern dex_unwind_count
extern dex_unwind_rf
extern dex_unwind_info

section .rodata
s_ok   db "UNWIND OK count=2", 13, 10, 0
s_bad  db "UNWIND FAIL", 13, 10, 0

section .data
align 16
; ---- arquivo fake: 0x400 B; .text@0x100, .pdata@0x200, .xdata@0x300 ----
g_buf:
    times 0x200 db 0
    ; .pdata: 2 RUNTIME_FUNCTION
    dd 0x1000, 0x1010, 0x3000
    dd 0x1010, 0x1020, 0x3008
    times (0x300 - 0x218) db 0
    ; .xdata @0x300:
    ;   info0 @rva 0x3000: ver1 flags0 prolog4 ncodes2, 2 codes
    db 0x01, 0x04, 0x02, 0x00, 0x01, 0x00, 0x02, 0x00
    ;   info1 @rva 0x3008: ver1 flags=EHANDLER prolog8 ncodes1 (+pad) + handler
    db 0x09, 0x08, 0x01, 0x00, 0x03, 0x00, 0x00, 0x00
    dd 0x1000
    times (0x320 - 0x314) db 0
    times (0x400 - 0x320) db 0

align 16
fake_secs:
    db ".text", 0, 0, 0
    dd 0x20, 0x1000, 0x20, 0x100, 0x60000020, 0
    db ".pdata", 0, 0
    dd 0x18, 0x2000, 0x18, 0x200, 0x40000040, 0
    db ".xdata", 0, 0
    dd 0x20, 0x3000, 0x20, 0x300, 0x40000040, 0

align 8
fake_opt:
    times 60 db 0
    dd 0x400                     ; SizeOfHeaders (rvas >= 0x400 caem em secoes)
    dd 0                         ; NumberOfRvaAndSizes

align 8
fake_img:
    dq g_buf                     ; file_buffer
    dq 0x400                     ; file_size
    dq 0x140000000               ; image_base
    dq 0x1000                    ; entry_point
    dd 3, 0                      ; num_sections + pad_ns
    dq fake_secs                 ; sections_ptr
    dq 0                         ; imports_ptr
    dd 0, 0                      ; imports_count + pad_ic
    dq 0                         ; exports_ptr
    dq 0                         ; relocs_ptr
    dd 0, 0                      ; relocs_count + pad_rc
    dq fake_opt                  ; opt_header
    dq 0                         ; nt_headers
    dd 1, 0                      ; is_valid + pad_v
    dd DEX_ARCH_X64, 0           ; arch + pad_arch

section .bss
align 8
g_rf:   resb SIZEOF_RUNTIME_FUNCTION
g_ui:   resb 32
g_out:  resb 256

section .text

;-----------------------------------------------------------------------------
; main — rbp + 4 pushes + sub 32 -> rsp%16==0. hOut em [rbp-40].
;-----------------------------------------------------------------------------
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 32
    mov ecx, -11
    sub rsp, 32
    call GetStdHandle
    add rsp, 32
    mov [rbp-40], rax              ; hOut
    lea r15, [rel g_out]
    ; ---- count = 2 ----
    lea rcx, [rel fake_img]
    sub rsp, 32
    call dex_unwind_count
    add rsp, 32
    cmp eax, 2
    jne .fail
    ; ---- rf0 ----
    lea rcx, [rel fake_img]
    xor edx, edx
    lea r8, [rel g_rf]
    sub rsp, 32
    call dex_unwind_rf
    add rsp, 32
    test eax, eax
    jnz .fail
    cmp dword [rel g_rf+RuntimeFunction.begin], 0x1000
    jne .fail
    cmp dword [rel g_rf+RuntimeFunction.end], 0x1010
    jne .fail
    cmp dword [rel g_rf+RuntimeFunction.unwind], 0x3000
    jne .fail
    ; ---- rf1 ----
    lea rcx, [rel fake_img]
    mov edx, 1
    lea r8, [rel g_rf]
    sub rsp, 32
    call dex_unwind_rf
    add rsp, 32
    test eax, eax
    jnz .fail
    cmp dword [rel g_rf+RuntimeFunction.begin], 0x1010
    jne .fail
    cmp dword [rel g_rf+RuntimeFunction.unwind], 0x3008
    jne .fail
    ; ---- rf2 fora -> 1 ----
    lea rcx, [rel fake_img]
    mov edx, 2
    lea r8, [rel g_rf]
    sub rsp, 32
    call dex_unwind_rf
    add rsp, 32
    cmp eax, 1
    jne .fail
    ; ---- info0 @0x3000 ----
    lea rcx, [rel fake_img]
    mov edx, 0x3000
    lea r8, [rel g_ui]
    sub rsp, 32
    call dex_unwind_info
    add rsp, 32
    test eax, eax
    jnz .fail
    cmp byte [rel g_ui+UnwindInfo.version], 1
    jne .fail
    cmp byte [rel g_ui+UnwindInfo.flags], 0
    jne .fail
    cmp byte [rel g_ui+UnwindInfo.prolog], 4
    jne .fail
    cmp byte [rel g_ui+UnwindInfo.ncodes], 2
    jne .fail
    cmp dword [rel g_ui+UnwindInfo.total], 8
    jne .fail
    cmp dword [rel g_ui+UnwindInfo.rvacnt], 0
    jne .fail
    ; ---- info1 @0x3008 ----
    lea rcx, [rel fake_img]
    mov edx, 0x3008
    lea r8, [rel g_ui]
    sub rsp, 32
    call dex_unwind_info
    add rsp, 32
    test eax, eax
    jnz .fail
    cmp byte [rel g_ui+UnwindInfo.flags], 1
    jne .fail
    cmp byte [rel g_ui+UnwindInfo.prolog], 8
    jne .fail
    cmp byte [rel g_ui+UnwindInfo.ncodes], 1
    jne .fail
    cmp dword [rel g_ui+UnwindInfo.total], 12
    jne .fail
    cmp dword [rel g_ui+UnwindInfo.rvacnt], 1
    jne .fail
    cmp dword [rel g_ui+UnwindInfo.rvaoff], 8
    jne .fail
    ; ---- rva fora -> 1 ----
    lea rcx, [rel fake_img]
    mov edx, 0x9000
    lea r8, [rel g_ui]
    sub rsp, 32
    call dex_unwind_info
    add rsp, 32
    cmp eax, 1
    jne .fail
    ; ---- sucesso ----
    lea rcx, [rel s_ok]
    call .estr
    call .flush
    xor ecx, ecx
    call ExitProcess
.fail:
    lea r15, [rel g_out]
    lea rcx, [rel s_bad]
    call .estr
    call .flush
    mov ecx, 2
    call ExitProcess

;-----------------------------------------------------------------------------
; .estr — rcx=cstr -> appenda em [r15]. Clobber rax, rdx, rcx.
;-----------------------------------------------------------------------------
.estr:
    mov dl, [rcx]
    test dl, dl
    jz .estr_d
    mov [r15], dl
    inc r15
    inc rcx
    jmp .estr
.estr_d:
    ret

;-----------------------------------------------------------------------------
; .flush — WriteFile(hOut, g_out, r15-g_out).
;-----------------------------------------------------------------------------
.flush:
    lea rdx, [rel g_out]
    mov r8, r15
    lea rax, [rel g_out]
    sub r8, rax
    mov rcx, [rbp-40]
    sub rsp, 56
    mov qword [rsp+32], 0
    lea r9, [rsp+40]
    call WriteFile
    add rsp, 56
    ret

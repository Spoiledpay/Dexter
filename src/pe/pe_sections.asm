;=============================================================================
; Dexter/src/pe/pe_sections.asm
; dex_pe_find_section — busca seção por nome (NUL-aware, até 8 chars).
;
; Requisitos atendidos: R-1.x, flag -s
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global dex_pe_find_section

extern dex_strlen
extern dex_memcmp

section .text

;-----------------------------------------------------------------------------
; dex_pe_find_section
; Args:   rcx = PeImage*, rdx = nome (NUL-terminado, ex. ".text")
; Ret:    rax = PeSection* ou 0
; Clobber: rax, rcx, rdx, r8-r11
;-----------------------------------------------------------------------------
dex_pe_find_section:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40                ; 8 pushes -> rsp%16==8; 40%16==8 => alinhado
    test rcx, rcx
    jz .nf
    test rdx, rdx
    jz .nf
    mov rbx, rcx               ; img
    mov r12, rdx               ; filtro
    mov rcx, rdx
    sub rsp, 32
    call dex_strlen            ; rax = flen
    add rsp, 32
    cmp rax, 8
    ja .nf
    mov r13, rax               ; flen
    mov rsi, [rbx+PeImage.sections_ptr]
    test rsi, rsi
    jz .nf
    mov r15d, [rbx+PeImage.num_sections]
    test r15d, r15d
    jz .nf
    xor r14d, r14d             ; i
.loop:
    cmp r14d, r15d
    jae .nf
    mov eax, r14d
    imul eax, SIZEOF_PE_SECTION
    mov rsi, [rbx+PeImage.sections_ptr]  ; reload (dex_memcmp clobbera rsi)
    lea rdi, [rsi+rax]         ; sec (rdi preservado por dex_memcmp)
    mov rcx, rdi
    mov rdx, r12
    mov r8, r13
    sub rsp, 32
    call dex_memcmp
    add rsp, 32
    test eax, eax
    jnz .next
    cmp r13, 8
    je .found
    movzx eax, byte [rdi+r13]
    test al, al
    jnz .next
.found:
    mov rax, rdi
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret
.next:
    inc r14d
    jmp .loop
.nf:
    xor eax, eax
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

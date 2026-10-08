;=============================================================================
; Dexter/src/pe/rva.asm
; dex_rva_to_offset / dex_offset_to_rva.
;
; Requisitos atendidos: R-1.x
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"
%include "pe.inc"

global dex_rva_to_offset
global dex_offset_to_rva

section .text

;-----------------------------------------------------------------------------
; dex_rva_to_offset
; Args:   rcx = PeImage*, edx = RVA
; Ret:    rax = offset no arquivo.
;         RVA < SizeOfHeaders sempre mapeia p/ offset=RVA (cabeçalhos).
;         Fora de qualquer região conhecida retorna 0 (documentado: ambíguo
;         com offset 0; chamadores devem tratar rva < SizeOfHeaders à parte).
;-----------------------------------------------------------------------------
dex_rva_to_offset:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push r12
    sub rsp, 40                ; 4 pushes -> rsp%16==8; 32 ok
    test rcx, rcx
    jz .none
    mov rbx, rcx
    mov r12d, edx              ; rva
    mov rsi, [rbx+PeImage.opt_header]
    test rsi, rsi
    jz .none
    mov eax, [rsi+ OH64_SIZE_OF_HEADERS]
    cmp r12d, eax
    jae .sections
    ; cabeçalhos: offset = rva (validar < file_size)
    mov rax, r12
    cmp rax, [rbx+PeImage.file_size]
    jae .none
    add rsp, 40
    pop r12
    pop rsi
    pop rbx
    pop rbp
    ret
.sections:
    mov rsi, [rbx+PeImage.sections_ptr]
    test rsi, rsi
    jz .none
    mov r10d, [rbx+PeImage.num_sections]
    xor r11d, r11d             ; i
.loop:
    cmp r11d, r10d
    jae .none
    mov eax, r11d
    imul eax, SIZEOF_PE_SECTION
    lea r9, [rsi+rax]          ; sec
    mov eax, [r9+PeSection.vaddr]
    cmp r12d, eax
    jb .next
    ; span = max(vsize, raw_size)
    mov ecx, [r9+PeSection.vsize]
    mov edx, [r9+PeSection.raw_size]
    cmp ecx, edx
    jae .span_v
    mov ecx, edx
.span_v:
    test ecx, ecx
    jz .next
    sub r12d, eax              ; delta = rva - vaddr (r12 era rva!)
    cmp r12d, ecx
    jae .restore_next
    ; delta < raw_size? (só há bytes em arquivo até raw_size)
    mov ecx, [r9+PeSection.raw_size]
    cmp r12d, ecx
    jae .none_bss              ; cai em .bss: sem offset (retorna 0)
    mov eax, [r9+PeSection.raw_ptr]
    add eax, r12d              ; offset (u32+u32, sem overflow p/ u64)
    mov rax, rax
    cmp rax, [rbx+PeImage.file_size]
    jae .none
    add rsp, 40
    pop r12
    pop rsi
    pop rbx
    pop rbp
    ret
.restore_next:
    add r12d, [r9+PeSection.vaddr]  ; restaura rva
.next:
    inc r11d
    jmp .loop
.none_bss:
.none:
    xor eax, eax
    add rsp, 40
    pop r12
    pop rsi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_offset_to_rva
; Args:   rcx = PeImage*, rdx = offset
; Ret:    rax = RVA (headers: identidade; seções: vaddr+delta) ou 0 se luar.
;         NOTA: offset 0 -> RVA 0 (válido, cabeçalhos).
;-----------------------------------------------------------------------------
dex_offset_to_rva:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push r12
    sub rsp, 40
    test rcx, rcx
    jz .none_o
    mov rbx, rcx
    mov r12, rdx               ; off
    cmp r12, [rbx+PeImage.file_size]
    jae .none_o
    mov rsi, [rbx+PeImage.opt_header]
    test rsi, rsi
    jz .none_o
    mov eax, [rsi+ OH64_SIZE_OF_HEADERS]
    cmp r12, rax
    jb .ident                  ; headers: rva = off
    mov rsi, [rbx+PeImage.sections_ptr]
    test rsi, rsi
    jz .none_o
    mov r10d, [rbx+PeImage.num_sections]
    xor r11d, r11d
.loop_o:
    cmp r11d, r10d
    jae .none_o
    mov eax, r11d
    imul eax, SIZEOF_PE_SECTION
    lea r9, [rsi+rax]
    mov eax, [r9+PeSection.raw_ptr]
    cmp r12, rax
    jb .next_o
    mov ecx, [r9+PeSection.raw_size]
    test ecx, ecx
    jz .next_o
    sub r12, rax
    cmp r12, rcx
    jae .restore_o
    mov eax, [r9+PeSection.vaddr]
    add rax, r12
    add rsp, 40
    pop r12
    pop rsi
    pop rbx
    pop rbp
    ret
.restore_o:
    add r12, [r9+PeSection.raw_ptr]
.next_o:
    inc r11d
    jmp .loop_o
.ident:
    mov rax, r12
    add rsp, 40
    pop r12
    pop rsi
    pop rbx
    pop rbp
    ret
.none_o:
    xor eax, eax
    add rsp, 40
    pop r12
    pop rsi
    pop rbx
    pop rbp
    ret

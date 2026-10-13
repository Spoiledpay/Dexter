;=============================================================================
; Dexter/src/pe/pe_relocs.asm
; dex_pe_parse_relocs — percorre o Base Reloc Directory e coleta RVAs
; (u32) que precisam de relocação (tipos != ABSOLUTE). Cap 65536.
; Layout em img.relocs_ptr: vetor u32[count]. Ausente/corrompido => 0.
;
; Requisitos atendidos: R-3.x, flag -no-relocs
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "dexter.inc"
%include "pe.inc"

global dex_pe_parse_relocs

extern dex_rva_to_offset
extern dex_malloc

section .text

;-----------------------------------------------------------------------------
; dex_pe_parse_relocs — rcx=PeImage* -> rax=count
;-----------------------------------------------------------------------------
dex_pe_parse_relocs:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56
    test rcx, rcx
    jz .zero_r
    mov rbx, rcx
    mov rsi, [rbx+PeImage.file_buffer]
    test rsi, rsi
    jz .zero_r
    mov r12, [rbx+PeImage.file_size]
    mov rax, [rbx+PeImage.opt_header]
    test rax, rax
    jz .zero_r
    cmp dword [rbx+PeImage.arch], DEX_ARCH_X32
    je .rdir32
    mov ecx, [rax+ OH64_NUM_RVA_SIZES]
    cmp ecx, 6
    jb .zero_r
    mov ecx, [rax+ OH64_DATA_DIR + 8*5]       ; reloc rva
    mov edx, [rax+ OH64_DATA_DIR + 8*5 + 4]   ; reloc size
    jmp .rdir_ok
.rdir32:
    mov ecx, [rax+ OH32_NUM_RVA_SIZES]
    cmp ecx, 6
    jb .zero_r
    mov ecx, [rax+ OH32_DATA_DIR + 8*5]       ; reloc rva
    mov edx, [rax+ OH32_DATA_DIR + 8*5 + 4]   ; reloc size
.rdir_ok:
    test ecx, ecx
    jz .zero_r
    test edx, edx
    jz .zero_r
    mov r13d, ecx
    mov r14d, edx
    mov rcx, rbx
    mov edx, r13d
    sub rsp, 32
    call dex_rva_to_offset
    add rsp, 32
    test rax, rax
    jz .zero_r
    mov rdi, rax               ; reloc_off
    mov rax, rdi
    add rax, r14
    cmp rax, r12
    ja .zero_r
    ; passada 1: contar (tipos != 0)
    xor r13d, r13d             ; count
    mov r15, rdi               ; cursor off
.blocks:
    mov rax, r15
    add rax, 8
    cmp rax, r12
    ja .b1_done
    mov ecx, [rsi+r15+4]       ; SizeOfBlock
    cmp ecx, 8
    jb .b1_done                ; bloco inválido: parar (gracioso)
    mov rax, r15
    add rax, rcx
    cmp rax, r12
    ja .b1_done
    mov edx, ecx
    sub edx, 8
    shr edx, 1                 ; n_entries
    xor r10d, r10d
.entries:
    cmp r10d, edx
    jae .next_blk
    mov rax, r15
    add rax, 8
    mov ecx, r10d
    lea rax, [rax+rcx*2]
    movzx eax, word [rsi+rax]
    test eax, eax
    jz .e_next                 ; ABSOLUTE: pula
    inc r13d
    cmp r13d, DEX_MAX_RELOCS
    jae .b1_done
.e_next:
    inc r10d
    jmp .entries
.next_blk:
    add r15, rcx
    ; fim? próximo bloco com SizeOfBlock==0 ou cursor >= off+size
    mov rax, r15
    sub rax, rdi
    cmp rax, r14
    jae .b1_done
    jmp .blocks
.b1_done:
    test r13d, r13d
    jz .zero_r
    ; alocar count*4
    mov eax, r13d
    shl eax, 2
    mov rcx, rax
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .zero_r
    mov r10, rax               ; vec
    mov [rbp-80], r14          ; spill reloc_size (r14d será o índice ei)
    ; passada 2: preencher
    xor r11d, r11d             ; vi
    mov r15, rdi               ; cursor
.blocks2:
    mov rax, r15
    add rax, 8
    cmp rax, r12
    ja .b2_done
    mov ecx, [rsi+r15+4]
    cmp ecx, 8
    jb .b2_done
    mov rax, r15
    add rax, rcx
    cmp rax, r12
    ja .b2_done
    mov eax, [rsi+r15]         ; page_rva
    mov [rbp-72], eax          ; spill page (slot local)
    mov edx, ecx
    sub edx, 8
    shr edx, 1
    xor r14d, r14d             ; ei
.entries2:
    cmp r14d, edx
    jae .next_blk2
    cmp r11d, r13d
    jae .b2_done
    mov rax, r15
    add rax, 8
    mov ecx, r14d
    lea rax, [rax+rcx*2]
    movzx eax, word [rsi+rax]
    test eax, eax
    jz .e2_next
    mov ecx, eax
    shr ecx, 12                ; tipo
    test ecx, ecx
    jz .e2_next
    and eax, 0xFFF              ; offset
    add eax, [rbp-72]
    mov ecx, r11d
    mov [r10+rcx*4], eax
    inc r11d
.e2_next:
    inc r14d
    jmp .entries2
.next_blk2:
    mov ecx, [rsi+r15+4]
    add r15, rcx
    mov rax, r15
    sub rax, rdi
    cmp rax, [rbp-80]
    jae .b2_done
    jmp .blocks2
.b2_done:
    mov [rbx+PeImage.relocs_ptr], r10
    mov [rbx+PeImage.relocs_count], r11d
    mov eax, r11d
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
.zero_r:
    xor eax, eax
    add rsp, 56
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

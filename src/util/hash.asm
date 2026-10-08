;=============================================================================
; Dexter/src/util/hash.asm
; FNV-1a 64-bit para a symbol table.
;
; Requisitos atendidos: R-gen (symbols)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

global dex_fnv1a
global dex_hash_va

section .text

;-----------------------------------------------------------------------------
; dex_fnv1a
; Args:   rcx=data, rdx=len
; Ret:    rax = hash64
;-----------------------------------------------------------------------------
dex_fnv1a:
    push rbx
    push rsi
    mov rsi, rcx                ; data
    mov rcx, rdx                ; len -> contador
    mov rax, 0xCBF29CE484222325
    test rcx, rcx
    jz .done
    mov rbx, 0x100000001B3      ; prime
.L:
    movzx edx, byte [rsi]
    xor rax, rdx
    mul rbx                     ; rdx:rax = rax*prime
    inc rsi
    dec rcx
    jnz .L
.done:
    pop rsi
    pop rbx
    ret

;-----------------------------------------------------------------------------
; dex_hash_va
; Args:   rcx=va, edx=num_buckets (potência de 2)
; Ret:    rax = va & (buckets-1)
;-----------------------------------------------------------------------------
dex_hash_va:
    mov eax, edx
    dec eax
    and rcx, rax
    mov rax, rcx
    ret

;=============================================================================
; Dexter/src/util/memory.asm
; Wrappers de heap (GetProcessHeap + HeapAlloc/HeapFree).
;
; Requisitos atendidos: Projeto.md §4.1, R-0.3
; Testes: build + run (alocação usada por asm_buffer/symbols)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"
%include "errors.inc"

global dex_malloc
global dex_free
global dex_realloc_grow

section .text

;-----------------------------------------------------------------------------
; dex_malloc
; Aloca size bytes zerados no heap do processo.
; Args:   rcx = size (deve ser >0 e <= 1GiB)
; Ret:    rax = ponteiro ou 0 (OOM / tamanho inválido)
; Clobber: rax, rcx, rdx, r8-r11
; Preserva: rbx, rbp, rdi, rsi, r12-r15
;-----------------------------------------------------------------------------
dex_malloc:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    sub rsp, 32                   ; shadow (rsp%16==0 antes do call)
    mov rbx, rcx                ; size
    test rbx, rbx
    jz .fail
    cmp rbx, DEX_MAX_FILE_SIZE
    ja .fail
    call GetProcessHeap         ; rax = heap
    test rax, rax
    jz .fail
    mov r12, rax
    mov rcx, r12                ; hHeap
    mov edx, HEAP_ZERO_MEMORY
    mov r8, rbx                 ; size
    call HeapAlloc              ; rax = ptr ou 0
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret
.fail:
    xor eax, eax
    add rsp, 32
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_free
; Libera ponteiro (NULL é no-op).
; Args:   rcx = ptr
; Ret:    nada
;-----------------------------------------------------------------------------
dex_free:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 40
    test rcx, rcx
    jz .done
    mov rbx, rcx
    call GetProcessHeap
    test rax, rax
    jz .done
    mov rcx, rax                ; hHeap
    xor edx, edx                ; dwFlags = 0
    mov r8, rbx                 ; ptr
    call HeapFree
.done:
    add rsp, 40
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_realloc_grow
; Duplica a capacidade de um buffer (usado por AsmBuf).
; Args:   rcx = old_ptr (pode ser 0), rdx = old_cap, r8 = min_needed
; Ret:    rax = new_ptr ou 0; rdx = new_cap (0 se falha)
; Clobber: rax, rcx, rdx, r8-r11
;-----------------------------------------------------------------------------
dex_realloc_grow:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push r12
    push r13
    sub rsp, 32
    mov rbx, rcx                ; old_ptr
    mov r12, rdx                ; old_cap
    mov r13, r8                 ; min_needed
    ; new_cap = max(old_cap*2, 64, min_needed)
    mov rax, r12
    shl rax, 1
    cmp rax, 64
    jae .have_dbl
    mov rax, 64
.have_dbl:
    cmp rax, r13
    jae .have_cap
    mov rax, r13
.have_cap:
    cmp rax, DEX_MAX_FILE_SIZE
    ja .fail
    mov r12, rax                ; new_cap
    call GetProcessHeap
    test rax, rax
    jz .fail
    mov rcx, rax
    xor edx, edx
    test rbx, rbx
    jnz .realloc_path
    ; alloc novo zerado
    mov edx, HEAP_ZERO_MEMORY
    mov r8, r12
    call HeapAlloc
    test rax, rax
    jz .fail
    mov rdx, r12
    add rsp, 32
    pop r13
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret
.realloc_path:
    ; HeapReAlloc(hHeap, 0, old, new)
    mov r8, rbx
    mov r9, r12
    ; 5º arg? HeapReAlloc tem 4 args: rcx,rdx,r8,r9 -> ok, só shadow
    call HeapReAlloc
    test rax, rax
    jz .fail
    mov rdx, r12
    add rsp, 32
    pop r13
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret
.fail:
    xor eax, eax
    xor edx, edx
    add rsp, 32
    pop r13
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret

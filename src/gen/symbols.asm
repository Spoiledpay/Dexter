;=============================================================================
; Dexter/src/gen/symbols.asm
; SymbolTable — hash VA->nome p/ imports (__imp_) e labels de código.
; Buckets potência de 2, encadeamento, FNV-1a.
;
; Requisitos atendidos: R-4.x (símbolos)
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "dexter.inc"

global symtab_new
global symtab_lookup_va
global symtab_insert_va
global symtab_free
global symtab_to_sorted

extern dex_malloc
extern dex_free
extern dex_strlen
extern dex_memcpy
extern dex_fnv1a
extern dex_hash_va

section .rodata
; Gaps de Shellsort (Ciura, sem divisão): robusto p/ R grande (ld.lld).
ss_gaps: dd 701, 301, 132, 57, 23, 10, 4, 1

section .text

;-----------------------------------------------------------------------------
; symtab_new — ecx=buckets (0 => 256; arredonda p/ pot. de 2, máx 65536)
; Ret: rax=SymbolTable* ou 0.
;-----------------------------------------------------------------------------
symtab_new:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    mov ebx, ecx
    test ebx, ebx
    jnz .pow
    mov ebx, 256
.pow:
    ; arredondar p/ cima até potência de 2
    mov eax, 1
.p2:
    cmp eax, ebx
    jae .p2d
    shl eax, 1
    cmp eax, 0x10000
    ja .fail_s
    jmp .p2
.p2d:
    cmp eax, 0x10000
    ja .fail_s
    mov r13d, eax              ; n
    mov rcx, 24
    call dex_malloc            ; SymbolTable (24 bytes: 8+4+4+4+4)
    test rax, rax
    jz .fail_s
    mov r12, rax
    mov eax, r13d
    shl eax, 3                 ; n*8
    mov rcx, rax
    call dex_malloc
    test rax, rax
    jz .fail_t
    mov [r12+SymbolTable.buckets], rax
    mov [r12+SymbolTable.num_buckets], r13d
    mov dword [r12+SymbolTable.count], 0
    mov dword [r12+SymbolTable.label_seq], 0
    mov rax, r12
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.fail_t:
    mov rcx, r12
    call dex_free
.fail_s:
    xor eax, eax
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; symtab_lookup_va — rcx=tab, rdx=va -> rax=DexSymbol* ou 0.
;-----------------------------------------------------------------------------
symtab_lookup_va:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 40
    test rcx, rcx
    jz .nf
    mov rbx, rcx
    mov r12, rdx               ; va
    mov rcx, rdx
    mov edx, [rbx+SymbolTable.num_buckets]
    call dex_hash_va           ; rax = idx
    mov r13, [rbx+SymbolTable.buckets]
    mov rcx, [r13+rax*8]       ; head
.lk:
    test rcx, rcx
    jz .nf
    cmp [rcx+DexSymbol.va], r12
    je .found
    mov rcx, [rcx+DexSymbol.next]
    jmp .lk
.found:
    mov rax, rcx
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.nf:
    xor eax, eax
    add rsp, 40
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; symtab_insert_va — rcx=tab, rdx=va, r8=name(NUL) -> rax=DexSymbol* ou 0.
; Se VA já existe, retorna o existente (sem duplicar).
; Copia o nome para o heap.
;-----------------------------------------------------------------------------
symtab_insert_va:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 56                ; 8 pushes -> rsp%16==8; 56%16==8 => alinhado
    mov rbx, rcx               ; tab
    mov r14, rdx               ; va
    mov r15, r8                ; name
    test rbx, rbx
    jz .fail_i
    test r15, r15
    jz .fail_i
    mov rcx, rbx
    mov rdx, r14
    sub rsp, 32
    call symtab_lookup_va
    add rsp, 32
    test rax, rax
    jnz .done_i                ; já existe: retorna o existente
    mov rcx, r15
    sub rsp, 32
    call dex_strlen
    add rsp, 32
    lea rcx, [rax+1]
    mov [rbp-72], rcx          ; namelen
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .fail_i
    mov r12, rax               ; name_copy
    mov rcx, rax
    mov rdx, r15
    mov r8, [rbp-72]
    sub rsp, 32
    call dex_memcpy
    add rsp, 32
    mov rcx, 24
    sub rsp, 32
    call dex_malloc            ; DexSymbol
    add rsp, 32
    test rax, rax
    jz .fail_i2
    mov r13, rax               ; node
    mov [r13+DexSymbol.va], r14
    mov [r13+DexSymbol.name_ptr], r12
    mov rcx, r14
    mov edx, [rbx+SymbolTable.num_buckets]
    sub rsp, 32
    call dex_hash_va           ; rax = idx
    add rsp, 32
    mov rdi, [rbx+SymbolTable.buckets]
    mov rsi, [rdi+rax*8]
    mov [r13+DexSymbol.next], rsi
    mov [rdi+rax*8], r13
    inc dword [rbx+SymbolTable.count]
    mov rax, r13
.done_i:
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
.fail_i2:
    mov rcx, r12
    sub rsp, 32
    call dex_free
    add rsp, 32
.fail_i:
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

;-----------------------------------------------------------------------------
; symtab_free — rcx=tab (libera nomes, nós e tabela).
;-----------------------------------------------------------------------------
symtab_free:
    test rcx, rcx
    jz .done_sf
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40                ; 6 pushes -> rsp%16==8; 40%16==8 => alinhado
    mov [rbp-56], rcx          ; tab (slot local)
    mov r13, [rcx+SymbolTable.buckets]
    mov r12d, [rcx+SymbolTable.num_buckets]
    xor r14d, r14d             ; i
.bk:
    cmp r14d, r12d
    jae .bk_done
    mov rbx, [r13+r14*8]       ; node
.nd:
    test rbx, rbx
    jz .nd_done
    mov r15, [rbx+DexSymbol.next]
    mov rcx, [rbx+DexSymbol.name_ptr]
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rcx, rbx
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rbx, r15
    jmp .nd
.nd_done:
    inc r14d
    jmp .bk
.bk_done:
    mov rcx, r13
    sub rsp, 32
    call dex_free
    add rsp, 32
    mov rcx, [rbp-56]
    sub rsp, 32
    call dex_free
    add rsp, 32
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
.done_sf:
    ret

;-----------------------------------------------------------------------------
; symtab_to_sorted — rcx=tab -> rax=array(qword VAs crescentes, malloc) +
; rdx=count; 0,0 = OOM (n==0 retorna array dummy de 1 slot, nunca 0).
; Achata os buckets (ordem de hash) e ordena com Shellsort (gaps Ciura).
; Caller libera com dex_free. Sem chamadas além de malloc (1x).
; Preserva: rbx, rbp, rdi, rsi, r12-r15.
;-----------------------------------------------------------------------------
symtab_to_sorted:
    test rcx, rcx
    jz .ss_oom
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15                     ; 6 pushes (48B) + sub 40 = 88 ≡ 8: calls ok
    sub rsp, 40                  ; 48+40 = 88 ≡ 8: calls ok
    mov rbx, rcx                 ; tab
    mov r14d, [rbx+SymbolTable.count]
    mov rax, r14
    shl rax, 3                   ; n*8 (n=0 -> 0)
    test rax, rax
    jnz .ss_alloc
    mov eax, 8                   ; dummy p/ n==0 (distingue de OOM)
.ss_alloc:
    mov rcx, rax
    sub rsp, 32
    call dex_malloc
    add rsp, 32
    test rax, rax
    jz .ss_oom_f
    mov [rbp-80], rax            ; arr
    mov r15, [rbx+SymbolTable.buckets]
    mov r13d, [rbx+SymbolTable.num_buckets]
    xor r12d, r12d               ; idx (fill)
    xor ebx, ebx                 ; bi (tab em [rbp-56]; rbx livre agora)
    mov [rbp-56], r15            ; buckets
    jmp .ss_bk
.ss_bk_l:
    mov r15, [rbp-56]            ; buckets
    mov rdx, [r15+rbx*8]         ; node
    test rdx, rdx
    jz .ss_bk_nx
.ss_nd:
    test rdx, rdx
    jz .ss_bk_nx
    mov rax, [rbp-80]            ; arr
    mov rsi, [rdx+DexSymbol.va]
    mov [rax+r12*8], rsi
    inc r12d
    mov rdx, [rdx+DexSymbol.next]
    jmp .ss_nd
.ss_bk_nx:
    inc ebx
    cmp ebx, r13d
    jb .ss_bk_l
    ; r12d = fill (deve == count em tabela íntegra; senão OOM alto).
    cmp r12d, r14d
    jne .ss_integ
    mov [rbp-64], r12d           ; nfill
    jmp .ss_sort
.ss_bk:
    jmp .ss_bk_l
.ss_sort:
    ; Shellsort sobre [arr, nfill), gaps Ciura (sem div).
    mov r15d, 8                  ; gi = 8 gaps
.ss_gap:
    dec r15d
    js .ss_done
    lea rax, [rel ss_gaps]
    mov eax, [rax+r15*4]             ; gap (rip+índice não encoda: via base)
    cmp eax, [rbp-64]
    jae .ss_gap                  ; gap >= n: pula
    test eax, eax
    jz .ss_gap
    mov [rbp-72], eax            ; gap
    mov ebx, eax                 ; i = gap
.ss_i:
    cmp ebx, [rbp-64]
    jae .ss_gap
    mov rdx, [rbp-80]            ; arr
    mov rsi, [rdx+rbx*8]         ; tmp = a[i]
    mov edi, ebx                 ; j = i
.ss_j:
    mov eax, edi
    sub eax, [rbp-72]            ; j-gap
    js .ss_put                    ; j < gap: insere
    mov rdx, [rbp-80]
    cmp rsi, [rdx+rax*8]         ; tmp >= a[j-gap]?
    jae .ss_put
    mov rcx, [rdx+rax*8]
    mov [rdx+rdi*8], rcx         ; a[j] = a[j-gap]
    mov edi, eax                 ; j -= gap
    jmp .ss_j
.ss_put:
    mov rdx, [rbp-80]
    mov [rdx+rdi*8], rsi         ; a[j] = tmp
    inc ebx
    jmp .ss_i
.ss_done:
    mov rax, [rbp-80]
    mov edx, [rbp-64]
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.ss_oom_f:
    xor eax, eax
    xor edx, edx
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.ss_integ:
    ; Tabela inconsistente (fill != count): vaza o array (erro fatal
    ; mesmo) e retorna OOM — falha alta e visível, nunca smash.
    xor eax, eax
    xor edx, edx
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.ss_oom:
    xor eax, eax
    xor edx, edx
    ret
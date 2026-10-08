;=============================================================================
; Dexter/src/io/mmap.asm
; Mapeamento do arquivo de entrada (CreateFileMapping + MapViewOfFile).
;
; Requisitos atendidos: R-0.3
; Autor: Dexter Engineer
;=============================================================================
bits 64
default rel

%include "win64.inc"

global dex_mmap_read
global dex_mmap_rw
global dex_unmap

section .text

;-----------------------------------------------------------------------------
; dex_mmap_read
; Args:   rcx=HANDLE arquivo, rdx=tamanho (>0)
; Ret:    rax = base mapeada ou 0
;-----------------------------------------------------------------------------
dex_mmap_read:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push r12
    sub rsp, 56               ; shadow + 3 slots (rsp%16==0 antes de call)
    mov rbx, rcx              ; hFile
    mov r12, rdx              ; size
    test rbx, rbx
    jz .fail
    cmp rbx, -1
    je .fail
    test r12, r12
    jz .fail
    ; hMap = CreateFileMappingA(hFile, NULL, PAGE_READONLY, 0, 0, NULL)
    mov rcx, rbx
    xor edx, edx
    mov r8d, PAGE_READONLY
    xor r9d, r9d
    mov qword [rsp+32], 0     ; dwMaximumSizeHigh
    mov qword [rsp+40], 0     ; dwMaximumSizeLow
    mov qword [rsp+48], 0     ; lpName
    call CreateFileMappingA
    test rax, rax
    jz .fail
    mov rdi, rax              ; hMap
    ; base = MapViewOfFile(hMap, FILE_MAP_READ, 0, 0, 0)
    mov rcx, rdi
    mov edx, FILE_MAP_READ
    xor r8d, r8d
    xor r9d, r9d
    mov qword [rsp+32], 0     ; dwNumberOfBytesToMap
    call MapViewOfFile
    mov rbx, rax              ; base (salva)
    ; CloseHandle(hMap)
    mov rcx, rdi
    call CloseHandle
    mov rax, rbx
    test rax, rax
    jz .fail
    add rsp, 56
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret
.fail:
    xor eax, eax
    add rsp, 56
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_mmap_rw
; Args:   rcx=HANDLE arquivo (rw), rdx=tamanho (>0)
; Ret:    rax = base mapeada (leitura+escrita) ou 0
;-----------------------------------------------------------------------------
dex_mmap_rw:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push r12
    sub rsp, 56               ; 4 pushes -> rsp%16==8; 56%16==8 => alinhado
    mov rbx, rcx              ; hFile
    mov r12, rdx              ; size
    test rbx, rbx
    jz .fail_w
    cmp rbx, -1
    je .fail_w
    test r12, r12
    jz .fail_w
    ; hMap = CreateFileMappingA(hFile, NULL, PAGE_READWRITE, 0, 0, NULL)
    mov rcx, rbx
    xor edx, edx
    mov r8d, PAGE_READWRITE
    xor r9d, r9d
    mov qword [rsp+32], 0
    mov qword [rsp+40], 0
    mov qword [rsp+48], 0
    call CreateFileMappingA
    test rax, rax
    jz .fail_w
    mov rdi, rax              ; hMap
    ; base = MapViewOfFile(hMap, FILE_MAP_READ|FILE_MAP_WRITE, 0, 0, 0)
    mov rcx, rdi
    mov edx, FILE_MAP_READ | FILE_MAP_WRITE
    xor r8d, r8d
    xor r9d, r9d
    mov qword [rsp+32], 0
    call MapViewOfFile
    mov rbx, rax              ; base (salva)
    mov rcx, rdi
    call CloseHandle          ; fecha hMap (view permanece válida)
    mov rax, rbx
    test rax, rax
    jz .fail_w
    add rsp, 56
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret
.fail_w:
    xor eax, eax
    add rsp, 56
    pop r12
    pop rdi
    pop rbx
    pop rbp
    ret

;-----------------------------------------------------------------------------
; dex_unmap — rcx=base (0 = no-op)
;-----------------------------------------------------------------------------
dex_unmap:
    test rcx, rcx
    jz .done_u
    push rbp
    mov rbp, rsp
    sub rsp, 32
    call UnmapViewOfFile
    add rsp, 32
    pop rbp
.done_u:
    ret

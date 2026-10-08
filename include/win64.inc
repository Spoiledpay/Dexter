;=============================================================================
; Dexter/include/win64.inc
; Protótipos kernel32 + constantes Win64 usadas pelo Dexter.
; Link: kernel32.lib (e shell32.lib não é necessário).
;=============================================================================
%ifndef DEX_WIN64_INC
%define DEX_WIN64_INC

; ---- kernel32 ----
extern GetCommandLineA
extern GetStdHandle
extern WriteFile
extern ReadFile
extern CreateFileA
extern GetFileSizeEx
extern CreateFileMappingA
extern MapViewOfFile
extern UnmapViewOfFile
extern CloseHandle
extern GetProcessHeap
extern HeapAlloc
extern HeapFree
extern HeapReAlloc
extern ExitProcess
extern CreateProcessA
extern WaitForSingleObject
extern GetExitCodeProcess
extern GetLastError
extern FlushFileBuffers
extern DeleteFileA
extern GetTickCount
extern lstrlenA
extern Sleep

; ---- msvcrt (apenas para futura extensão; não usado no núcleo) ----

; ---- Constantes ----
%define STD_INPUT_HANDLE   -10
%define STD_OUTPUT_HANDLE  -11
%define STD_ERROR_HANDLE   -12

%define GENERIC_READ      0x80000000
%define GENERIC_WRITE     0x40000000
%define FILE_SHARE_READ   0x00000001
%define FILE_SHARE_WRITE  0x00000002
%define OPEN_EXISTING     3
%define CREATE_ALWAYS     2
%define FILE_ATTRIBUTE_NORMAL 0x80
%define INVALID_HANDLE_VALUE -1

%define PAGE_READONLY     0x02
%define PAGE_READWRITE    0x04
%define FILE_MAP_READ     0x0004
%define FILE_MAP_WRITE    0x0002

%define HEAP_ZERO_MEMORY  0x00000008

%define CREATE_NO_WINDOW  0x08000000
%define STARTF_USESTDHANDLES 0x100
%define INFINITE          0xFFFFFFFF

%define SW_HIDE 0

; STARTUPINFOA (104 bytes) offsets
%define SI_CB              0
%define SI_DWFLAGS         60
%define SI_HSTDINPUT       80
%define SI_HSTDOUTPUT      88
%define SI_HSTDERROR       96
%define SIZEOF_STARTUPINFO 104

; PROCESS_INFORMATION (24 bytes)
%define PI_HPROCESS  0
%define PI_HTHREAD   8
%define PI_DWPROC_ID 16
%define PI_DWTHR_ID  20
%define SIZEOF_PROCINFO 24

%endif

;=============================================================================
; Dexter/include/pe.inc
; Estruturas PE/COFF (offsets exatos, little-endian).
; Referência: Microsoft PE/COFF spec. Todos os campos são lidos com
; validação de limites contra o tamanho do arquivo (nunca confiar).
;
; Requisitos atendidos: Projeto.md seção 4
; Autor: Dexter Engineer
;=============================================================================
%ifndef DEX_PE_INC
%define DEX_PE_INC

%define IMAGE_DOS_SIGNATURE     0x5A4D  ; "MZ"
%define IMAGE_NT_SIGNATURE       0x00004550  ; "PE\0\0"
%define IMAGE_FILE_MACHINE_AMD64 0x8664
%define IMAGE_FILE_MACHINE_I386  0x014C
%define IMAGE_NT_OPTIONAL_HDR64_MAGIC 0x20B
%define IMAGE_NT_OPTIONAL_HDR32_MAGIC 0x10B

; ---- Directory entries ----
%define IMAGE_DIRECTORY_ENTRY_EXPORT         0
%define IMAGE_DIRECTORY_ENTRY_IMPORT         1
%define IMAGE_DIRECTORY_ENTRY_RESOURCE       2
%define IMAGE_DIRECTORY_ENTRY_EXCEPT         3
%define IMAGE_DIRECTORY_ENTRY_SECURITY       4
%define IMAGE_DIRECTORY_ENTRY_BASERELOC       5
%define IMAGE_DIRECTORY_ENTRY_DEBUG           6
%define IMAGE_NUMBEROF_DIRECTORY_ENTRIES     16

; ---- Section characteristics ----
%define IMAGE_SCN_CNT_CODE               0x00000020
%define IMAGE_SCN_CNT_INITIALIZED_DATA   0x00000040
%define IMAGE_SCN_CNT_UNINITIALIZED_DATA 0x00000080
%define IMAGE_SCN_MEM_EXECUTE            0x20000000
%define IMAGE_SCN_MEM_READ               0x40000000
%define IMAGE_SCN_MEM_WRITE              0x80000000

; ---- Relocation types (x64) ----
%define IMAGE_REL_BASED_ABSOLUTE 0
%define IMAGE_REL_BASED_HIGHLOW  3
%define IMAGE_REL_BASED_DIR64    10

; Offsets dentro dos headers (para leitura byte-exata sem struc).
; IMAGE_DOS_HEADER
%define DOS_E_MAGIC   0
%define DOS_E_LFANEW  0x3C
%define DOS_HEADER_SIZE 64

; IMAGE_FILE_HEADER (20 bytes, base = nt_hdrs)
%define FH_MACHINE              0
%define FH_NUMBER_OF_SECTIONS   2
%define FH_TIME_DATE_STAMP      4
%define FH_SIZE_OF_OPT_HDR      16
%define FH_CHARACTERISTICS      18
%define SIZEOF_FILE_HEADER       20

; IMAGE_OPTIONAL_HEADER64 (base = nt_hdrs + 4 + 20)
%define OH64_MAGIC               0
%define OH64_ENTRY_POINT         16
%define OH64_BASE_OF_CODE       20
%define OH64_IMAGE_BASE          24
%define OH64_SECTION_ALIGN       32
%define OH64_FILE_ALIGN          36
%define OH64_SIZE_OF_IMAGE       56
%define OH64_SIZE_OF_HEADERS     60
%define OH64_SUBSYSTEM           68
%define OH64_NUM_RVA_SIZES       108
%define OH64_DATA_DIR            112
%define SIZEOF_OPT_HDR64         240

; IMAGE_OPTIONAL_HEADER32 (PE32, base = nt_hdrs + 4 + 20). Só os campos
; que o loader usa; offsets da spec (ImageBase u32 em 28!).
%define OH32_MAGIC               0
%define OH32_ENTRY_POINT         16
%define OH32_BASE_OF_CODE       20
%define OH32_BASE_OF_DATA       24
%define OH32_IMAGE_BASE          28
%define OH32_SECTION_ALIGN       32
%define OH32_FILE_ALIGN          36
%define OH32_SIZE_OF_IMAGE       56
%define OH32_SIZE_OF_HEADERS     60
%define OH32_SUBSYSTEM           68
%define OH32_NUM_RVA_SIZES       92
%define OH32_DATA_DIR            96
%define SIZEOF_OPT_HDR32        224

; IMAGE_SECTION_HEADER (40 bytes cada)
%define SH_NAME            0
%define SH_VSIZE           8
%define SH_VADDR           12
%define SH_RAW_SIZE        16
%define SH_RAW_PTR         20
%define SH_CHARACTERIST    36
%define SIZEOF_SECT_HDR    40

; IMAGE_IMPORT_DESCRIPTOR (20 bytes)
%define IID_ORIG_FIRST_THUNK 0
%define IID_TIME_DATE        4
%define IID_FORWARDER       8
%define IID_NAME            12
%define IID_FIRST_THUNK     16
%define SIZEOF_IMPORT_DESC  20

; IMAGE_BASE_RELOCATION (8 bytes + entries)
%define BRB_VADDR  0
%define BRB_SIZE   4

struc IMAGE_DATA_DIRECTORY
    .VirtualAddress resd 1
    .Size           resd 1
endstruc

%endif ; DEX_PE_INC

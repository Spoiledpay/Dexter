# Dexter — Notas de PE/COFF (achados de campo)

## 1. `for.exe` (corpus): `OptionalHeader.Magic = 0x0000`

PE x64 com `Magic` zerado (esperado `0x20B`). O Dexter rejeita com saída 3
— comportamento correto por especificação. Observação: o Windows parece
tolerar/rodar o arquivo mesmo assim (teste travou em loop — **não executar
`for.exe` sem timeout; é tratado como corpus negativo/fuzz**).
Usado em `run_tests.bat` como teste de rejeição.

## 2. Arquivos de 32 bits (`var32.exe`, `link.exe` de tests)

`Machine = 0x14C`, `Magic = 0x10B`. Rejeitados com 3 (só x64 suportado).
`tests\link.exe` é cópia do linker MS de 32 bits — serve de negativo.

## 3. `SizeOfOptionalHeader` de x64 real = 240 (`0xF0`)

`hello.exe`/`var64.exe` (link.exe MS) usam 240. O loader exige `>= 240`
quando `Magic == 0x20B`.

## 4. Import Directory pode viver em `.rdata` (não só `.idata`)

`hello.exe` (link MS): `dir[1]` aponta p/ dentro de `.rdata`. O parser
resolve via `rva_to_offset` genérico (qualquer seção), não assume `.idata`.

## 5. MinGW (`var64.exe`): 11 seções, nomes de 8 bytes

`.eh_fram` (truncado de `.eh_frame`), `.xdata`/`.pdata` SEH, `.tls` com
`vsize < raw_size`, `.bss` com `raw_size = 0`. Tudo tratado: db-copy,
trim de unwind p/ `vsize`, `.bss` vazia.

## 6. Linker MS reordena seções e injeta `.rdata` próprio

`link.exe` (mesmo `/NODEFAULTLIB /DEBUG:NONE`) emite `.rdata$voltmd` /
`.rdata$zzzdbg` + load-config e, com atributos diferentes (`LNK4078`),
**não funde** com o nosso `.rdata` — cria segunda seção em outro VA.
Lições aplicadas:
- seções R/O com classe NASM `rdata` (`0x40400040`), não `data`;
- DataDirectories adotados via `dex_patch_dirs` (o link não regenera
  diretórios a partir de bytes `db`);
- round-trip fiel de PEs reais = `-m bin` (sem linker no caminho).

## 7. `.pdata` com padding zero → `LNK1223`

O linker valida `RUNTIME_FUNCTION` das contribuições e rejeita entradas
zeradas de padding. Solução: aparar `.pdata`/`.xdata` p/ `vsize` no modo
win64 **se e somente se** o VA da próxima seção não mudar (guarda por
`SectionAlignment`).

## 8. `NumberOfRvaAndSizes` real = 16; limitar, não falhar

Leituras de diretório sempre com `min(count, 16)` e checagem de limites.
Diretórios ausentes/corrompidos → count 0 (degradação graciosa), nunca crash
(requisito fuzz do SKILL).

## 9. RVAs absolutas em código (`mov rax, imm64`) exigem base fixa

Por isso o rebuild win64 usa `/BASE:<original> /DYNAMICBASE:NO`, e o modo
bin preserva a base byte a byte.

## 10. Quirk WinAPI neste ambiente (documentado, sem workaround necessário)

`SetFilePointerEx` (por valor, conforme ABI) e `ReadFile` com `OVERLAPPED`
explícito falharam com `87` em handles válidos onde `ReadFile`
sequencial, `GetFileSizeEx` e `mmap` funcionam. I/O posicional do Dexter =
`mmap_rw`; wrappers de seek foram removidos em vez de mantidos quebrados.

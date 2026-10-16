# Dexter — Notas de PE/COFF (achados de campo)

## 1. `Magic = 0x0000` (negativo)

PE com `OptionalHeader.Magic` zerado (esperado `0x20B`/`0x10B`). O Dexter
rejeita com saída 3 — comportamento correto por especificação. A suíte
gera o fixture na hora (`tests\out\corrupt_mz.exe`, `hello.exe` com `MZ`
zerado) e nunca o executa.
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

## 11. Corpus de exceção real (`tests/exc.exe`) — R-5.4 F4
`tests/exc.exe` (MinGW-w64 `g++ -O1`, fonte `tests/exc_cpp.cpp`) é um
programa C++ que lança `throw 7` no fundo de uma recursão **não-tail**
(6 frames, cada um com um destrutor não-trivial) e captura em `main`
(`catch (int)`), exigindo que o desenrolar (unwind) do Windows percorra os
`RUNTIME_FUNCTION`/`UNWIND_INFO` reais e rode os destrutores.

Perfil do binário (oráculo para o fixture): **18 seções**; `.pdata` com
**117 `RUNTIME_FUNCTION`** e flags de unwind
`{UNW_FLAG_NHANDLER(0), EHANDLER(1), EHANDLER|UHANDLER(3)}` — ou seja
`UNWIND_INFO` com **handler RVA real** (`__CxxFrameHandler3`), não apenas
prolog. É o corpus que exercita o handler de verdade (o `var64` só tinha
prologs).

Fatos de campo:
- `-m bin -native`: **byte-idêntico** (`fc /b` 0 diffs) e o reconstruído
  roda o throw/catch (`caught=7 cleanups=6`, **exit 42**) — prova que a
  `.pdata`/`.xdata` simbólica da F3 é funcional, não só fiel em bytes.
- **Modo win64: o rebuild crasha (`0xC000007B`).** Causa = **D-19**: o
  `link.exe` funde/reordena (`18→16` seções; `.xdata` some dentro de
  `.rdata`; `.pdata` muda de VA) e o `dex_patch_dirs` copia os
  DataDirectories originais cegos — o Import Directory continua apontando
  `0x10000`, que após o remanejo é `.bss` (a `.idata` foi para `0xE000`).
  Não é falha do unwind simbólico (as flags reemitidas da `.pdata` saem
  idênticas às originais); reforça que PEs reais pedem `-m bin`
  (D-19 / R-8.2).

## 12. `-f bin`: label = file-offset ⇒ `disp32` entre seções precisa de K

Em `nasm -f bin` **não há segmentos**: cada label recebe como valor o seu
**offset no arquivo** (não o RVA). O layout do Dexter reproduz os
`raw_ptr` originais (padding `times N db 0`), então *dentro* de uma seção
o deslocamento relativo coincide com o RVA e o `disp32` RIP-relativo sai
correto. **Entre seções diferentes não coincide**, porque cada seção tem
seu próprio `delta = vaddr − raw_ptr` (hello: `.text` 0xC00, `.rdata`
0x1A00).

Consequência para `call|jmp [rel __imp_X]` (IAT em `.rdata`, código em
`.text`): o `disp32` montado seria o do espaço de offsets, deslocado do
original por `K = (vaddr_iat − raw_iat) − (vaddr_code − raw_code)`.
Correção (R-5.3 F1): emitir `[rel __imp_X + K]` — a expressão somada ao
label devolve o `disp32` original (hello/var64: `K = 0xE00` / `0x6600`).
Sem K o `.asm` ainda monta, mas o binário fica byte-diferente (falha
silenciosa se não houver o gate `[rel __imp_` na suíte).

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

## 13. `-f bin` simbólico: descritores de import (R-5.3 F2)

No `-m bin -native` o `IMAGE_IMPORT_DESCRIPTOR` (20 B) deixa de ser `db`
opaco: cada descritor vira `label_<VA>:` + 5 `dd`, com
`OriginalFirstThunk`/`Name`/`FirstThunk` como `dd label_<alvoVA> + C`
(`C = vaddr − raw_ptr` da seção do alvo — a mesma constante do `.pdata` da
F3) e o alvo ganhando `label_<VA>:` no stream. `TimeDateStamp`/`ForwarderChain`
ficam crus (`dd 0x…`).

- **`Import Directory.Size` cobre MAIS que os descritores.** No MSVC/MinGW ele
  abrange também a ILT/IAT/nomes: `hello` `dir[1].Size = 0x28` (2 descritores),
  `var64` `Size = 0xC18` = 12 descritores + ILT/IAT/nomes (`size/20` = 154,8).
  Logo NÃO se pode derivar a contagem de `size/20`; o limite correto é o
  **descritor terminador** (5 campos u32 zero), com tetos de segurança
  (`imp_rva+Size`, nº máx., `raw_size` da seção e `offset+20 ≤ file_size`).
- **Label só para alvo "rotulável".** Só se concede `dd label_ + C` se o alvo
  cai numa seção de dados com bytes (`raw>0`), não executável e não
  `.pdata`/`.xdata`; caso contrário sai `dd 0x<rva>` cru (byte-idêntico, sem
  risco de label indefinido). A referência e a emissão do label concordam por
  construção.
- **Evento = menor VA, não item.** Um mesmo VA pode ser descritor, alvo e slot
  de IAT (ex.: `FirstThunk == início da IAT`); os rótulos são deduplicados por
  VA. O label da seção já cobre `off==0`.
- **Verificação estrutural:** `tests/pe_impdesc.py <exe> <asm>` reconstrói cada
  campo a partir dos bytes originais do PE e confere as linhas `dd` e os
  labels (seção `[45]`). É mais forte que `findstr`, pois `db` e `dd` são
  byte-idênticos (o `fc` não distingue simbólico de copiado).

## 14. Limite honesto: `ld.lld -m bin -native` (pré-existente, fora da F2)

`tests/ld.lld.exe` (68 MB) em `-m bin -native` **já falhava no `nasm`** antes
da F2: a `.pdata` simbólica (F3) referencia RVAs de `.xdata` que não recebem
label em seções grandes do ld.lld → **59160** `symbol ... not defined` + **5**
`label-redef-late`. Provado gerando com o binário do HEAD (sem F2): assinatura
de erro idêntica (58960 "not defined" + 5 "redef-late" nos dois). A suíte
lenta cobre ld.lld apenas em `-m bin` (`[S1]`, byte-idêntico OK); o caminho
`-native` de PE grande provado é o `gcc` (`[S2]`) + hello/var64/exc/tiny.

## 15. `UNWIND_INFO` em QUALQUER seção (R-5.4) — MS funde `.xdata` no `.rdata`

MSVC / MS link em PE real (ex.: `tests/notepad.exe`) **não** cria seção
`.xdata`: o `UNWIND_INFO` vive dentro do `.rdata`. O código SEH antigo só
rotulava unwinds numa seção **nomeada** `.xdata`, então a `.pdata`
(`dd label_<UnwindInfo>`) gerava label indefinido (386 no notepad; `win64` e
`-m bin -native` falhavam no `nasm`). Agora o unwind é reemitido simbólico
**onde estiver**: núcleo `.uw_bitmap` (bitmap dos inícios na seção, da `.pdata`
+ `chained` propagado) + `.uw_emit` (`label_` + `db` do header/codes + `dd`
simbólico dos campos RVA via `.pd_field`); o bin (`.gb_db_slots`) varre os
inícios e os reemite intercalados com imports/db, byte-exato.

**D-20 (FECHADA):** `-m bin -native` do notepad agora é **byte-idêntico**
(`fc /b` 0), via `src/disasm/emit_nasm.asm`. Duas classes de divergência do
codegen nativo (achadas com `fc`+listing): (1) ALU/mov **reg-reg na forma
"load"** (`02/03..3A/3B`, `8A/8B`: reg=dst) — o NASM monta na forma "store"
(`89/31`) → cai p/ `db`; (2) **prefixo de segmento** (`gs:`/`fs:`) era
descartado nos caminhos **sem base** (`[abs …]`/`[rel …]`) → reemitido
`[<seg>:…]` (sub-rotina `.fo_segpre`). O path **fiel** `-m bin` também segue
byte-idêntico. O `win64` de PE MS real segue **D-19** (link funde seções →
Import Directory aponta p/ seção errada → `0xC000007B`).

## 16. `-f bin` simbólico: thunks ILT/IAT (R-5.3 F3)

No `-m bin -native` as arrays de thunks deixam de ser `db`: cada entrada
não-nula de `OriginalFirstThunk` (ILT) e `FirstThunk` (IAT) sai
`dq label_<hint/name VA> + C` (`C = vaddr − raw_ptr` da seção do alvo — mesma
constante da F2; o alvo `IMAGE_IMPORT_BY_NAME` ganha `label_` no stream).

- **`bound`/ordinal → `dq 0x<v>` cru.** O valor de um thunk é um RVA de
  `IMAGE_IMPORT_BY_NAME` **apenas se** o bit63 estiver limpo (senão é ordinal)
  e o valor couber em 32 bits. IAT *bound* (pré-vinculada) guarda endereços
  reais (> 4 GiB) → `> 32 bits` → sai cru; ordinal idem. Alvo não-rotulável
  (`.pdata`/`.xdata`/código/sem bytes) também cai em cru. Byte-fiel em todos
  os casos (`notepad`: `thunks=630 sym=620 raw=10`).
- **Alvo ≠ slot no scanner de 1-VA-por-iteração.** O caminho de dados do bin
  resolve **um** VA por iteração (o menor ≥ `floor`), então registrar o alvo
  dentro do teste do slot o deixaria órfão quando o slot já tivesse sido
  emitido (< `floor`) — o `label_` nunca sairia e o nasm acusaria *symbol not
  defined*. Correção: o alvo é testado **independente** do slot.
- **Terminador do array fica em `db`.** A varredura para na primeira entrada
  zero (não registra evento), então os 8 bytes do terminador saem no `db`
  seguinte — inofensivo (`dq 0` e `db 0×8` são idênticos).
- **Verificação:** `tests/pe_impdesc.py` percorre OFT/FT do PE original e
  confere cada `dq`/`label_`; a suíte trava o golden em `[47]`.

## 17. `-f bin` simbólico: hint/name + nomes de DLL (R-5.3 F4)

Com a F4 a import table fica **100% regenerada** no `-m bin -native`:

- cada `IMAGE_IMPORT_BY_NAME` (alvo de um thunk by-name) sai
  `label_<VA>:` + `dw <hint>` + `db "<nome>", 0`;
- o `Name` do `IMAGE_IMPORT_DESCRIPTOR` sai `label_<VA>:` + `db "<dll>", 0`.

Regras e armadilhas:

- **Fallback honesto.** Só vira string se o cstring é ASCII imprimível
  (0x20..0x7E), tem NUL **dentro da seção** (`raw - best`) e len ≤ 255; senão
  emite `db` cru (1 byte por evento, o resto pelo caminho normal) — byte-fiel
  sempre. O escape de `"` é feito por `dex_emit_qstr` (vira `", 34, "`).
- **`dex_emit_qstr` é file-scope.** O antigo `.emit_qstr` era um label
  **local** de `dex_generate_asm`; labels com `.` são escopados ao label
  não-local anterior, então os `.gb_*` (escopo `dex_generate_bin`) geravam
  `symbol 'dex_generate_bin.emit_qstr' not defined` (e uma cascata de
  `label-redef-late`). Promovido a `dex_emit_qstr`.
- **`dw` validado ANTES de emitir** (`.gb_hint_emit` lê e valida o nome antes
  de escrever o `dw`) — evita `dw` órfão se o nome for inválido.
- **Verificação:** `tests/pe_impdesc.py` lê o hint (`<H`) e o nome dos bytes
  do PE e confere as linhas `dw`/`db`; golden na suíte `[48]` (hello
  `hint=6 nomes=1`, notepad `hint=620 nomes=50`, `ruins=0`).

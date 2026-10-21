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

## 18. SIB-abs COM índice (loads indexados) e o "split" do NASM

Um operando de memória sem base (`ModRM mod=00 rm=100` + `SIB base=101`) tem
como endereço `disp32 + index*scale` — o `[rcx*4]` de x64 e o
`[0x40A000+eax*4]` (tabela absoluta) de x32.

- **NASM re-encoda a forma.** `lea eax, [abs 0x2+rax*2]` monta como
  `8D 44 00 02` = `lea eax, [rax+rax+0x2]` (base=rax + index=rax scale 1,
  disp8) — **4 bytes** em vez dos **7** da forma SIB-abs. Ou seja: o NASM
  prefere a forma "splitada" quando `index*2 == base+index` com o mesmo
  registrador (só scale 2), encurtando a instrução e mudando os bytes.
  Solução: **`nosplit`** na expressão — força a forma exata
  (`[nosplit abs 0x2+rax*2]` → `8D 04 45 02 00 00 00`).
- **`abs` vem PRIMEIRO em x64.** `[rcx*4+abs 0x10]` é *expression syntax
  error*; o correto é `[nosplit abs 0x10+rcx*4]`. Em x32 não há `abs`
  (`[nosplit 0x40A000+eax*4]`).
- **disp32 é obrigatório nesta forma** (não há variante sem disp para
  base=101), então difere de `.fo_disp` (base+index), que cai em `db` quando o
  disp é 0 porque ali o NASM encurtaria `[reg+0x0]` → `[reg]`. Se o disp32 for
  0, a emissão omite o disp (`[nosplit rcx*4]`) — o encoding continua com
  disp32=0.
- **Bug colateral corrigido:** em x32 o caminho `.fo_abs32` era tomado antes
  de checar `has_sib` e **descartava o índice**; agora a checagem de SIB vem
  primeiro e o índice é emitido.
- **Verificação:** fixture `tests/sibabs.asm` (`lea [idx*scale]`) + seção
  `[49]` (round-trip `-m bin -native` byte-idêntico + exit 42); notepad
  `-m bin -native` `fc /b` 0 diffs (regressão do emissor).

## 19. Runs de string com CR/LF (`-strings`) — aspas com estado

O `-strings` marcava como string só um run de ≥8 bytes **imprimíveis**
(0x20..0x7E) seguido de NUL — runs com CR/LF (as literais `"...\r\n"`, muito
comuns) eram rejeitados e saíam como `db` byte a byte.

- **`.str_run` agora aceita CR(13)/LF(10) DENTRO do run** (o **primeiro** byte
  continua tendo de ser imprimível, senão um bloco de CRs viraria "string").
  Qualquer outro não-imprimível (fora CR/LF/NUL) rejeita o run.
- **`dex_emit_qstr` fecha/reabre as aspas** em volta de cada escape, com um
  estado `open`: byte cru reabre com `, "` (vírgula + aspa) se estiver fechado;
  escape fecha (se aberto) e emite `, 13`/`, 10`/`, 34`; no fim fecha se preciso
  e emite `, 0`. Resultado: **uma linha NASM**, sem `""` (que era o artefato de
  dois escapes seguidos, ex.: `\r\n`).
  ```
  db "alpha-one", 13, 10, 0
  db "say ", 34, "hi", 34, " ok", 13, 10, 0
  ```
- **Armadilha:** `al` é volátil — o byte cru tem de ser **recarregado** de
  `[r12+r14]` depois dos `call` de reabertura (senão o 1º byte de cada
  segmento virava lixo).
- **Só afeta o texto** (o bin ignora `-strings` com aviso): bytes preservados;
  prova = `[21]` (round-trip comportamental) + `[50]` (linha exata + nasm).

## 20. Índice simbólico em x32 (SIB-abs): `[nosplit label_<VA>+eax*4]`

`jmp dword [jtab+eax*4]` (tabela de switch absoluta, padrão x32) tem o
endereço `disp32 + index*scale`, com o disp32 sendo a **VA** da tabela.

- **Só x32 é simbolizável.** A VA precisa caber em 32 bits: em x32 (base
  ~0x400000) cabe; em x64 (base 0x140000000) o disp32 nunca é uma VA da
  imagem (e em `-f bin` um label absoluto precisaria de `+C`, que o emissor
  não tem). Então o emissor só simboliza com `addr_mode == 1` (x32).
- **O scanner registra a VA (não o índice).** `.cs_abs32sib` (x32) aceita
  `mod=00 rm=100`, `SIB base=101` (sem base), disp32 = VA, e insere a **RVA**
  no R (mesmo R dos refs RIP; chaveado por RVA e consumido pelo data walker,
  que emite `label_<VA>`). Sem isso o emissor não teria como saber o VA.
  **Armadilha real:** o campo *base* do SIB são os **bits 2-0** — extraí-lo
  com `shr 5` (bits 7-5) fazia o check `base==101` nunca casar (o valor saía
  sempre `0x2008` cru).
- **Canal emissor↔rebuild = DADOS, não função.** Os drivers de teste
  (`codegen_check`, `[12]`) linkam `emit_nasm.obj` **sem** `rebuild.obj`;
  um `extern` de função novo (ou `global` no rebuild) quebra o link da suíte.
  Solução: `emit_nasm.asm` **define** `g_abs_vas`/`g_abs_n`/`g_abs_base` (0 =
  desligado) e o `rebuild` só **escreve** neles (R ordenado + image_base); o
  emissor faz a busca binária. Qualquer linker que inclua `emit_nasm.obj`
  fecha.
- **Verificação:** `tests/absidx.asm` (switch real + load indexado) + `[51]`
  (forma simbólica + round-trip `-native` → exit 42). x64 segue numérico
  (`tests/sibabs.asm` + `[49]`).

## 21. Spans de ponteiro em x32 = 4 bytes (`dd`) — jump-to-code

O pré-scan de ponteiros (`.collect_strs` passada B) e o emissor de spans
(`.wds_emit_span`) eram **8 bytes** (`dq`), então em x32 as tabelas de ponteiro
(`dd VA`) ficavam `db` byte a byte; o x32 até forçava `g_spanflags=1` ("corpos
db") e o pré-scan era gated em `arch == X64`.

Agora o **stride vem do arch** (8 = `dq`/qword; 4 = `dd`/dword):

- `.collect_strs` passada B: lê `dword` em x32 (zero-estendido) e valida pelo
  mesmo `.ptr_tgt_ok`/`.code_tgt_ok`.
- `.wds_emit_span`: `stride` em `[rbp-88]`, leitura dword/qword, diretiva
  `s_dqpre`/`s_dd4`, avanço `o += stride`.
- `.wds_plain` (sem `-strings`): a linha que punha `g_spanflags=1` p/ x32 foi
  removida — ambos os archs usam chunks com spans.
- Resultado em x32: a tabela de switch aponta p/ **código** via D-7 →
  `dd label_401017` (antes `db 0x17, 0x10, 0x40, 0x00`).
- **Verificação:** `tests/absidx.asm` + `[51]` (grep `dd label_401017` +
  round-trip exit 42); `[30]`–`[33]` (x32) e a suíte lenta seguem verdes.

## 22. `-s <seção>` × reemissão simbólica da `.pdata`/`.xdata` (SEH)

Com `-s <seção>` o contrato é "só essa seção é desassemblada; as demais saem
`db`". O caminho `asm`/`win64 -native` já aplicava isso às seções comuns, mas
**furava a exceção da R-5.4**: `.pdata`/`.xdata` eram reemitidas
simbolicamente (`dd label_<code VA> wrt ..imagebase`) **independentemente do
filtro**. Como a `.text` filtrada-fora vira `db` e não ganha `label_` por-VA, a
`.pdata` referenciava `label_<VA>` **nunca definido** → o `nasm -f win64`
abortava com 122 `symbol not defined` + 113 `label changed during code
generation` (234 erros em `tests/exc.exe -s .rdata`). Sem `-s` o mesmo binário
monta 0 erros (não tem relação com D-19/D-20: o defeito é do filtro).

Correção (`src/gen/rebuild.asm`, `.walk_data`): com `section_filter != 0` a
exceção `.pdata`/`.xdata` é **pulada** e as duas caem no caminho `db` comum
(`.wd_plain`) — direção segura do **D-17** ("na dúvida, db; nunca símbolo
indefinido") e exatamente o contrato do `-s`. Efeito: `.pdata`/`.xdata` saem
`section .pdata rdata` + `db` byte-fiel; `-s .text` continua assemblando (o
entry está na seção percorrida) e o caminho `-m bin` (que percorre tudo e
rotula cada instrução) fica intacto.

Limite honesto: `-s <seção>` que **exclui a seção do entrypoint** combinado com
`-r` (rebuild via link) segue impossível por natureza — o `global
label_<entry>` do cabeçalho referencia um símbolo não definido (a seção do
entry virou `db`), então o link falha com `LNK2001`/`exit 5`. Sem `-r` a saída
monta normalmente; `-s .text -r` (entry preservado) segue linkando OK.

- **Verificação:** `tests/exc.exe -s .rdata -native` → 0 erros (antes 234);
  `-s .rdata -m bin -native` `fc /b` 0; suíte `[52]` (7 checks) + `run_slow`.
- **Armadilha de ambiente:** o `nasm` do `PATH` era o 2.16.01 do Strawberry
  (`C:\Strawberry\c\bin`), não o do projeto (`C:\Nasm\nasm.exe`, 3.01). Com o
  2.16 o mesmo `.asm` acusa 19 `mismatch in operand sizes` **falsos**. Screens
  manuais devem usar `C:\Nasm\nasm.exe`.

## 23. `UNWIND_INFO` em qualquer seção também no win64 (D-19, fatia 1)

O caminho `bin` já reemitia o `UNWIND_INFO` simbólico onde quer que ele
morasse (`.uw_bitmap`/`.uw_emit`, R-5.4 estendido), mas o caminho
`asm`/`win64 -native` só o fazia para uma seção literalmente chamada `.xdata`
(`.emit_xdata_sec`). Em PEs do MS link o `.xdata` é **fundido na `.rdata`**,
então a `.pdata` emitia `dd label_<unwind VA> wrt ..imagebase` para 193 alvos
(386 referências) que **nunca ganhavam label** → `nasm -f win64` abortava com
386 `symbol not defined` (`notepad.exe -native`).

Correção: `.walk_data_sec` calcula `.uw_bitmap` (só sem `-s`) e, se a seção tem
inícios de UNWIND_INFO, usa o novo caminho `.wds_plain_uw`: a fatia
`[cur, próximo início)` vai ao `.wds_chunks` (**preserva R-labels/spans** —
essencial, pois a `.text` referencia VAs da `.rdata` via RIP) e cada início
marcado vai ao `.uw_emit` (simbólico via `.pd_field`; win64 = `wrt
..imagebase`). Novo `.uw_next_bit` (ecx=limit, edx=start → próximo offset
marcado no bitmap). `g_uwbm` guarda o bitmap e é liberado ao fim da seção.

Regra: com `-s` ativo o caminho fica **desligado** (os handlers referenciados
pelo unwind podem estar em seção filtrada-fora, sem label) — mesma direção
D-17/D-21. Trocar `.wds_chunks` por `.emit_xdata_sec` para a seção **não**
serve: perdem-se as R-labels e a `.text` fica com `[rel label_...]`
indefinido (tentado e descartado com erro: 48.840 `symbol not defined`).

- **Verificação:** `notepad.exe -native` → nasm **0 erros** (antes 386);
  `-m bin -native` do notepad segue byte-idêntico; `[53]` (5 checks);
  win64 de hello/var64/exc/tiny/loop/strings/jtable/no_relocs = 0 erros.
- **Nota:** `notepad.exe -native -r` já **linka** (exit 0, `np_rt.exe`
  353.280 B vs 360.448 B do original); o comportamento do exe reconstruído é a
  **fatia 2** (D-19: `dex_patch_dirs` cego + seções fundidas pelo link).

## 24. D-19 fatia 2a — DataDirectories remapeados por (seção, offset)

O `link.exe` **reordena/funde** seções. Ex. (`exc.exe`): original
`.text .data .rdata /4 .pdata .xdata .bss .idata .CRT .tls .reloc …`;
rebuildado `.text .rdata .data .pdata .idata _4 .bss .CRT .reloc …` → a
`.idata` saiu de `0x10000` para `0xE000`. O `dex_patch_dirs` copiava a RVA
**crua**, então o IMPORT dir (`0x10000`) passou a apontar para a **`.bss`**
nova → o loader rejeita com **`0xC000007B`** (`STATUS_INVALID_IMAGE_FORMAT`);
o `-overview` do rebuildado mostrava `Imports: 0`.

Correção: novo `.pd_remap` (local de `dex_patch_dirs`) — acha a seção
**original** que contém a RVA, guarda o `offset` e devolve
`VirtualAddress` da seção **rebuildada homônima** + `offset` (nome comparado
com a sanitização do gerador: `/NNN` → `_NNN`). Se não houver seção homônima
ou o offset cair fora, o dir **não** é copiado (fica 0 — nunca uma RVA velha).
Guarda preservada: só patcheia quando o slot rebuildado é `(0,0)`.

Efeito medido (`exc.exe -native -r`): o erro mudou de **`0xC000007B`**
(imagem inválida) para **`0xC0000005`** (AV) — a imagem agora **carrega**;
falta a **fatia 2b** (as RVAs *internas* do `.idata` copiado continuam
absolutas: `OFT=0x10130`, `Name=0x10AD4`, `FirstThunk=0x103C8` → lixo).
Por isso 2a **sozinha não** fecha o comportamento.

Exceção documentada: **SECURITY (dir 4)** e **DEBUG (dir 6)** são
"regeneráveis" — o `link.exe` produz o próprio DEBUG dir (válido; o
certificado não é copiado por design) — o oráculo não exige
`(seção, offset)` iguais para eles, só que continuem válidos.

- **Verificação:** `tests/pe_dirs.py` (oráculo estrutural) — `exc` 5/5 e
  `hello` 3/3 dirs OK; suíte `[54]` (4 checks); `run_tests.bat` **385/385**;
  `run_slow.bat` **7/7**; `-m bin` intacto.

## 25. D-22 — `-s <seção>` + `-r`: entry label via `equ`

Quando `-s` aponta para uma seção diferente da seção do entrypoint, o gerador
win64/win32 emite a seção do entry como dados (`db`/chunks) — contrato do
filtro. O cabeçalho do `.asm` só declarava `global label_<entry>`, mas a
definição `label_<entry>:` só nascia no walker de código; sem ela, o
`link.exe` abortava com `LNK2001: unresolved external symbol
label_<entry>` (exit 5) — mesmo com a imagem gerada estando correta.

Fix: `.emit_entry_alias` (`src/gen/rebuild.asm`) localiza a seção que contém
o `entry_point` e, no fim do arquivo, emite:

```text
label_<entryVA> equ label_<secVA> + 0x<delta>
```

`label_<secVA>` é o `lab0` que toda seção emitida já produz (db/chunks/bss),
então a expressão é constante e não há forward reference. Guardas:
`delta == 0` não emite (o label da seção já é o entry) e `-s` na seção do
entry não emite (o walker define o label; evita duplicata). `-m bin` não é
afetado (não usa `/ENTRY`).

- **Verificação:** `[55]` (6 checks): `exc -s .rdata -native -r` e `-r` (db)
  linkam; `-s .text` sem `equ` redundante; `tiny32 -s .rdata -r` (x32,
  delta 0). Suíte **391/391**; `run_slow.bat` **7/7**.

# Sessão 2026-10-16 — R-5.4: UNWIND_INFO em QUALQUER seção (`.rdata`) + corpus `notepad.exe`

> Leitura: `skill.md` → `Projeto.md` → `marco.md` → `docs/ROADMAP.md` → este.
> **STATUS: verde, NÃO commitado.** Firmware: **1.2.356**. `tests\run_tests.bat`
> **335/335 OK**; `run_slow.bat` **7/7 OK**.

## 0. Motivação

O usuário adicionou `tests\notepad.exe` (MS x64 real, 8 seções, 315 imports,
352 KB). Em `-m bin -native` e `win64` o `nasm` falhava com **386** `symbol
not defined` — todos da `.pdata` (`dd label_<UnwindInfo>`) referenciando
`UNWIND_INFO` que moram no **`.rdata`** (o MS link funde o `.xdata` ali; não
há seção `.xdata`). Provado **pré-existente**: o binário do HEAD dá os mesmos
386 (mesmo 1º erro `label_14003009C`); a F2 (imports) adiciona **zero**.

## 1. O que foi feito (R-5.4 estendido: unwind em qualquer seção)

Núcleo reutilizável em `src/gen/rebuild.asm` (escopo `dex_generate_asm`):

- **`.uw_bitmap(img, sec)`** → bitmap de bytes (1 bit/offset) com os inícios
  de `UNWIND_INFO` **dentro desta seção**, derivados da `.pdata` + propagação
  `chained` (até 8 passadas) — `0` se a seção não tem unwinds.
- **`.uw_emit(buf, img, sec, off)`** → `label_<VA>` + `db` do
  header/unwind-codes + `dd` simbólico dos campos RVA (via `.pd_field`, que já
  faz bin `+ C` e win64 `wrt ..imagebase`); devolve o total (>0), `0` (não
  decodificável → caller emite 1 byte `db`) ou `-1` (OOM).
- **`.gb_db_slots`** (bin): nova varredura — acha o 1º início de unwind `>=
  floor` no bitmap e, no evento (`GK_UW`/flag `[rbp-168]`), chama `.uw_emit` e
  avança `total`. Assim a `.rdata` do notepad sai com os 386 unwinds
  **simbólicos** intercalados com imports/db, byte-exato.

## 2. Evidência (comandos exatos)

```bat
build.bat                                                            rem limpo 1.2.356
out\dexter.exe tests\notepad.exe -o tests\out\notepad_th.asm -m bin -r -O tests\out\notepad_th.exe -q
cmd /v:on /c "fc /b tests\notepad.exe tests\out\notepad_th.exe >nul 2>&1 & echo FC=!errorlevel!"   rem FC=0
cmd /dev/null
cmd /v:on /c "tests\run_tests.bat > log & echo BAT_EXIT=!errorlevel!"  rem 335/335 OK
cmd /v:on /c "tests\run_slow.bat > log & echo SLOW=!errorlevel!"       rem 7/7 OK
```

- **`-m bin` do notepad: byte-idêntico** (`fc /b` 0).
- **`-m bin -native` do notepad: COMPILA agora** (0 erros do nasm; antes 386).
  O `.asm` contém `dd label_...` / `label_<VA>:` dos unwinds em `.rdata`.
- Corpus antigo intacto: hello/var64/gcc/exc (bin e `-native`) byte-idênticos;
  gcc/ld.lld na lenta 7/7.

## 3. D-20 (codegen nativo) — FECHADA

Primeiro o `-m bin -native` do notepad compilava mas divergia (~290 k bytes;
3 B menor; 1º diff `.text` RVA 0x1008 `4C 8B DC` (MSVC) vs `49 89 E3`).
Achei a causa com `fc`+listing (`label_<VA>` fora de offset) e fechei em
**duas classes** (`src/disasm/emit_nasm.asm`):

1. **ALU/mov reg-reg na forma "load"** (`02/03..3A/3B`, `8A/8B`: reg=dst):
   o NASM canoniza para a forma "store" (`89/31/…`) — bytes ≠ do MSVC. Agora
   o emissor manda essas p/ `db` (byte-exato; comportamento idêntico).
2. **Prefixo de segmento** (`gs:`/`fs:`) era **descartado** nos caminhos
   **sem base** (`.fo_ripabs`: `[abs …]`, `[rel …]`, `[0xVA]` x32) — o
   segmento só era emitido em `.fo_membody` (com base). Corrigido: reemite
   `[<seg>:…]` (ex.: `gs:[abs 0x30]`) via sub-rotina `.fo_segpre` (que
   realinha a pilha).

Resultado: **`-m bin -native` do notepad byte-idêntico** (`fc /b` 0,
360448 B). O gate `[46]` passou a EXIGIR isso. gcc/ld.lld seguem
byte-idênticos. Nota de método: meus `fc` manuais via `cmd /c "... & echo
%errorlevel%"` davam "FC=0" **falso** (`%errorlevel%` expande em parse-time);
o gate correto é `fc … ; if errorlevel 1`.

## 4. Limite honesto — win64 de PE MS real = D-19

A `.data`/`.rdata` do win64 é emitida por `.walk_data_sec`/`.wds_chunks`
(com R-labels/`dq`), caminho **diferente** do bin. Integrar unwind ali exige
reestruturar o merge de fronteiras do `.wds_chunks` (grande/arriscado) e, de
qualquer forma, o win64 de PE MS real continua bloqueado por **D-19**
(`link.exe` funde seções → Import Directory cego aponta p/ seção errada →
`0xC000007B`) — independente do SEH. O path **fiel** é `-m bin` (agora com o
unwind simbólico em qualquer seção).

## 5. Corpus

`tests/notepad.exe` adicionado (whitelist em `.gitignore`) + seção **`[46]`**
(5 checks): `-m bin` byte-idêntico; `-m bin -native` compila (o gate do SEH);
unwind simbólico (`dd label_`); descritores de import (`pe_impdesc.py`).

## 6. Estado do git

- **Não commitado**: `.gitignore`, `src/gen/rebuild.asm`, `tests/run_tests.bat`,
  `version.bin`, `docs/*`, `marco.md`; novos `tests/notepad.exe`,
  `tests/pe_impdesc.py`, este doc.
- **Retomada**: R-5.3 F3/F4 (pausa da sessão anterior) e/ou D-20 (fidelidade
  do codegen nativo em PE MS) e/ou win64→D-19.

# ADR 0003 — Import table simbólica no `win64 -native` (D-19 fatia 2b)

- **Data:** 2026-10-21
- **Status:** aceito
- **Contexto:** D-19 (o `link.exe` reordena/funde seções), R-5.3 (import
  table simbólica, provada apenas em `-m bin`) e D-17 (nunca emitir símbolo
  indefinido).
- **Requisito:** o `.asm` gerado por `dexter <pe> -native` (modo win64) deve
  ter a import table inteira simbólica, de modo que o linker recalcule as
  RVAs depois de mover as seções.

## Contexto

No modo `-m bin` o arquivo é remontado byte a byte e os labels são offsets de
arquivo; `label_<VA> + C` (C = `vaddr - raw_ptr` da seção do alvo) vira a RVA
correta — R-5.3 F1–F4.

No modo win64 o `.idata` era copiado como `db` cru. Como o `link.exe`
reordena/funde seções (ex.: `exc.exe`: `.idata` de `0x10000` para `0xE000`),
as RVAs internas do `.idata` (`OriginalFirstThunk`, `Name`, `FirstThunk` e as
entradas ILT/IAT) ficavam apontando para o layout antigo. A fatia 2a corrigiu
o ponteiro do DataDirectory; a imagem passou a carregar, mas o loader lia uma
import table inválida (`0xC0000005`).

## Decisão

1. **Reusar o walker de eventos do bin** (`.gb_db_slots`) no win64, em vez de
   escrever um segundo walker. O walker já cobre descritores, IATs, arrays
   ILT/IAT, `IMAGE_IMPORT_BY_NAME`, nomes de DLL e unwind, por varredura de
   seção.
2. **Modo de escrita por flag** (`g_unwind_bin`): o mesmo emissor grava
   - bin: `dd label_<VA> + 0x<C>` / `dq label_<VA> + 0x<C>`;
   - win64: `dd label_<VA> wrt ..imagebase` (relocação `ADDR32NB`).
3. **Slot da IAT em 8 bytes** como `dd label_<VA> wrt ..imagebase, 0`:
   o pré-load da IAT é uma RVA de 32 bits zero-estendida (não um VA de 64
   bits). Isso preserva a semântica do PE e cabe no `qword` do array.
4. **Gaps preservam R-labels/spans** via `.wds_chunks`; com `-strings` o gap
   usa `.wds_gap_win`, que reemite runs como `db "..."` e só cai em chunks
   quando há alvo R no interior do run (evita splits que somariam NULs).
5. **Seleção de seção por metadado** (`.imp_sec_has`): só vai para o walker
   a seção que contém Import Directory, IAT, OFT/Name/FT ou hint/name. As
   demais mantêm o caminho antigo (chunks/strings), minimizando diffs.
6. **`-s` e `-no-imports` continuam em `db`** (D-17): com filtro de seção os
   alvos podem não ter label; a direção segura é não simbolizar.
7. **`__imp_` único por slot**: quando o mesmo `(dll, func|ordinal)` aparece
   em mais de um slot IAT (gcc importa `_fileno`/`_open`/`_read`/`_close`
   duas vezes), a **primeira** ocorrência mantém `__imp_<dll>_<func>` e as
   seguintes recebem `_<iat_rva hex>`. A regra é aplicada no walker (ref) e
   em `dex_emit_imp_label` (definição); sem isso o `nasm` acusa label
   redefinido e a referência não casa.

## Alternativas descartadas

- **Walker dedicado no win64:** duplicaria toda a lógica de eventos (F1–F4)
  e criaria deriva entre bin e win64.
- **Emitir RVA absoluta e corrigir depois no `.exe`:** exige saber o layout
  final que o linker escolheu; é o mesmo problema que a D-19 ataca, com uma
  segunda passada frágil.
- **Congelar o layout (`/FIXED`/ordem de seção):** não resolve a fusão de
  `.bss`/`.tls`/`.xdata` pelo `link.exe` e viola o objetivo da fase.

## Consequências

- O `.asm` win64 passa a depender de relocações `ADDR32NB` que o `link.exe`
  resolve; `nasm -f win64` monta com 0 erros.
- O caminho `-m bin` não muda (`g_impwds = 0`, gaps em `db`).
- Comportamento do `.exe` win64 em PE real **continua** limitado pela fatia 2
  (fusão de seções, `.bss`/`.tls`/`.CRT`, `LNK4078`); a 2b fecha a estrutura
  da import table, não o comportamento.
- Limite honesto: x32/win32 e `-s` seguem com import table em `db`.

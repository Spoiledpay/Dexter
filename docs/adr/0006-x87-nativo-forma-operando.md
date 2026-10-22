# ADR-0006 — x87 nativo: forma de operando em tabela e grafia NASM

- Data: 2026-10-22
- Status: aceito
- Requisito: item 2 da fila pós-2c, fatia **2a** (x87)
- Ver: `docs/PE_NOTES.md §32`, `src/disasm/x87.asm`, `tests/x87nat.asm`,
  `tests/x87nat32.asm`, `tests/x87_native_check.py`, `[60]`

## Contexto

O decoder já resolvia o **mnemônico** x87 (R-2.7, tabela verificada contra
capstone 5.0.7), mas `dex_build_operands` devolvia `db` para todo `D8-DF`:
não havia forma de operando, e o emissor não sabia imprimir `st(i)` nem os
keywords de tamanho do x87. O item 2 pede semântica de operandos, não só
rótulo no comentário.

Fatos medidos no NASM 3.01 (`-f bin -l`, 2048 codificações):

1. `tbyte` **não existe** no NASM; 80 bits é `tword`.
2. `feni`/`fdisi` emitem `9B` (FWAIT) antes do opcode — 3 bytes. As formas
   sem wait são `fneni`/`fndisi` (DB E0/E1), únicas byte-idênticas.
3. Capstone chama `fcompi`/`fucompi`; o NASM só conhece `fcomip`/`fucomip`.
4. `fstpnce` (D9 D8-DF, 8 codificações) **não tem mnemônico no NASM**.
5. Com dois operandos `st0, st0` o NASM escolhe a forma DC (ambígua). A
   forma de um operando (`fadd st0`) fixa a codificação D8.
6. Em x32, `[disp32]` absoluto fora da imagem já caía em `db` antes deste
   trabalho (`mov ecx,[0x100]` idem) — limite do modo, não do x87.

## Decisão

1. **Forma em tabela, no módulo dono do conhecimento** (`x87.asm`):
   `x87_shape[64]` (por opcode × grupo de ModRM) e `x87_memsz[64]` (por
   opcode × campo reg). `dex_x87_form` devolve `eax = X87_SH_*` e
   `edx = tamanho do operando de memória`.
2. **Semântica monta DexOp de verdade**: `DEX_OP_ST` (novo kind, reg = i)
   para `st(i)`; `DEX_OP_REG`/size 2 para `ax`; o operando de memória
   reusa `.build_rm` (ModRM/SIB/disp/seg e as regras de forma do emissor).
3. **Emissor ganha só o que faltava**: `st<i>`, `tword` e `DEX_MEM_NOSZ`
   (sem keyword: `fldenv`/`fnstenv`/`frstor`/`fnsave`).
4. **Grafia NASM na tabela**: `fneni`, `fndisi`, `fucomip`, `fcomip`
   substituem os nomes do capstone. O comentário do `db` e a instrução
   passam a usar a mesma palavra válida no NASM.
5. **`fstpnce` permanece `db`** (8 codificações, com comentário): o texto
   NASM não existe; inventar símbolo seria mentira. Contagem declarada no
   TSV e verificada na suíte.
6. **x32 também emite**, pelo allowlist existente (`D8-DF`), com o limite
   já conhecido do modo (absoluto fora da imagem → `db`): 1736 nativas.

## Alternativas descartadas

- **Mapear x87 para o modelo genérico de operandos** (REG/MEM com tamanhos
  1/2/4/8): `st(i)` não é GPR, `tword` não é tamanho de registrador e as
  formas implícitas (`faddp st1` = `st1, st0`) não cabem em `op0/op1`
  genéricos sem hacks.
- **Usar `feni`/`fdisi`** (FWAIT): muda bytes (3 em vez de 2). Rejeitado
  por fidelidade.
- **Adiar x32**: o allowlist x32 é o contrato do modo; a mesma tabela vale,
  e a prova é o mesmo oráculo com a coluna `native32`.

## Consequências

- `DexOp.size` ganha dois códigos (10 = tword, 0xFF = sem keyword); só x87
  os usa hoje.
- As codificações x87 válidas saem como instrução real no `-m bin -native`
  e no `-native` link, com bytes idênticos (o NASM reencoda o mesmo
  encoding para todas as 1796 formas do x64).
- Fixture gerado (2048 instruções) + TSV de classificação: qualquer
  regressão (uma forma que volte a `db`) falha a suíte com o índice exato.
- Rótulos de comentário mudam para 4 mnemônicos (goldens de `[39]`
  regenerados com justificativa).

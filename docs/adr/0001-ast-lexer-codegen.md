# ADR-0001 — AST / Lexer / Geração de código nativo sobre o Dexter

Data: 2026-10-07 · Status: aceito (Fase 6, R-6.1–R-6.6) · Autor: Dexter Engineer

## Contexto

O Dexter hoje é um desassemblador/reassemblador fiel:

* `dex_disasm_one` → `Insn` (+ `raw[15]` + `mne` comentário).
* Walker win64 emite `label_<VA>: + db b,b,...` (`dex_emit_insn kind=0`).
* Round-trip garantido por cópia byte-exata + `link /BASE:idem /DYNAMICBASE:NO` (win64 simples) ou `nasm -f bin` (byte-idêntico, PEs reais).

Paralelamente já existe a base do nativo, desligada:

* `DexOp` (`dexter.inc:88-117`): AST flat 16B (`kind/reg/base/index/scale/size/seg/val`).
* `dex_build_operands` (`src/disasm/semantics.asm`): `(opcode,ModRM,prefixos) → op0/op1/op2 + mne preciso`, whitelist estrita, `1 = use db`.
* `dex_emit_native` (`src/disasm/emit_nasm.asm:521+`): `Insn → "    mov rax, rbx" / "[rel label]"`, `1 = use db`.
* Passada 1 em `rebuild.asm:.collect_syms`: tabelas D (VAs decodificadas) e R (RIP→dados).

O que falta para análise/otimização/reemissão: lexer do NASM gerado,
parser para AST hierárquica (funções/blocos/CFG), lifter para IR e
codegen que reuse o `emit_native`. É a Fase 6.

## Decisão

Evolução incremental em 3 propostas (A+B agora, C futura), sem quebrar o `db`:

* **Opção A (R-6.1): emissor nativo opt-in.** Novo flag `-native`
  (`DF_NATIVE`): walker tenta `dex_emit_native`, fallback `db` se `1`.
  `dex_build_operands` passa a rodar no walker (hoje só na coleta).
  Default continua `db` até R-6.1 fechar com round-trip `hello/tiny/loop`.
* **Opção B (R-6.2–R-6.3): lexer + parser + AST.** Novos módulos
  `src/front/lexer.asm` (`dex_lex_one`), `src/front/parser.asm`,
  `src/front/ast.asm` (`Func → Blocks → Instr → Op`, CFG via
  `target_va/is_branch/is_call/is_ret`). Teste golden sobre `tests/hello.asm`.
* **Opção C (R-6.4–R-6.6, futura): lift + codegen.** `src/back/lift.asm`
  (`DexOp → IR`), `src/back/codegen.asm` (`IR → AsmBuf` via `emit_native`);
  só aqui reativar `call [rel __imp_X]` (R-3.3/R-4.5); `-ast-dump`,
  `-emit=db|native`; backend `-f bin` regenerado por último.

## Alternativas consideradas

1. Reescrever tudo para AST direto (rejeitado: quebraria os 31+ testes verdes).
2. Usar parser NASM externo em Python (rejeitado: SKILL exige ferramenta
   nativa, sem dependência externa no runtime).
3. Reativar rewrite de IAT já (rejeitado: ARQUITETURA §1 — linker invalida;
   só faz sentido com layout não-idêntico da Fase 6).

## Consequências

* Positivas: `.asm` editável (`mov` real em vez de `db`), base para
  decompilação/otimização/instrumentação; reaproveita LDE/tabelas/testes.
* Negativas: walker fica mais complexo (2 caminhos); risco de divergência
  `native vs db` — mitigado por fallback + suíte com/sem `-native`.
* Riscos: VEX/EVEX/x87 continuam `db` (correto); jump-tables/SEH só em R-6.4.

## Plano de verificação (por R)

* R-6.1: `build.bat` + `run_tests.bat` OK sem `-native`; com `-native`:
  `hello/tiny/loop/strings/no_relocs` geram, montam (`nasm -f win64`),
  executam com mesma saída (`hi`, `42`, `55`).
* R-6.2: teste de lexer com contagem de tokens golden, zero `TODO/stub`.
* R-6.3+: AST dump comparado + round-trip nativo.

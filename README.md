# Dexter — Desassemblador/Reassemblador x64 nativo (NASM/Windows)

> Toda contribuição (humana ou IA) deve aderir ao protocolo de
> `skill.md`. Leitura obrigatória antes de qualquer alteração:
> `skill.md` → `Projeto.md` → `docs/ROADMAP.md`.

Ferramenta real, 100% NASM x86-64, sem CRT: lê um PE x64, gera `.asm`
reassemblável e reconstrói o `.exe` — incluindo **round-trip byte-idêntico**
no modo `-m bin` (hello 2560 B e var64 91872 B: `fc /b` igual e
comportamento igual).

## Requisitos

- Windows x64, `nasm.exe` (`C:\Nasm\` ou PATH) e `link.exe` (MSVC).
- `kernel32.lib` do Windows SDK (o `build.bat` localiza sozinho).

## Uso rápido

```bat
build.bat
out\dexter.exe tests\hello.exe -o tests\out\hello.asm -r -O tests\out\hello_rt.exe
tests\out\hello_rt.exe            &:: imprime "hi"
out\dexter.exe tests\var64.exe -o tests\out\var64_bin.asm -m bin -r -O tests\out\var64_bin.exe
fc /b tests\var64.exe tests\out\var64_bin.exe   &:: iguais
tests\run_tests.bat               &:: suíte completa (124/124)
```

Flags e códigos de retorno: `docs/CLI.md`. Arquitetura e decisões:
`docs/ARQUITETURA.md`. Status por requisito: `docs/ROADMAP.md`.

## Layout

```
build.bat  clean.bat
include/         win64.inc dexter.inc pe.inc errors.inc macros.inc
src/cli io pe disasm gen util   (30 módulos NASM, 1 responsabilidade cada)
runtime/         templates Fase 5 (modo bin avançado)
docs/            CLI ARQUITETURA ROADMAP REVISAO CHANGELOG PE_NOTES
tests/           hello.asm (golden) + corpus + run_tests.bat + out/
out/ obj/        artefatos de build (ignorados no git)
```

## Corpus de teste

| Arquivo | Papel |
|---|---|
| `tests\hello.asm` | Fonte golden (NASM) — a suíte monta `hello.exe` a partir dele |
| `tests\var64.exe` | x64 real (mingw, 11 seções, TLS, 14 imports) — round-trip bin |
| `tests\var32.exe`, `tests\link.exe` | 32-bit — rejeição limpa (saída 3) |
| `tests\for.exe` | `Magic=0` — rejeição limpa (saída 3); **não executar sem timeout** |

## Estado atual (v1.2.186 + R-6.4 fechado + R-7.2)

- [x] Fases 0–4 + `bin`: build sem warnings, `run_tests.bat` 124/124 OK
  (R-6.4.3 fechado em 2026-10-11 — ver
  `docs/SESSAO-2026-10-11-R643.md`).
- [x] R-7.1: `-overview`/`-json` inspect-only (texto + JSON validado).
- [x] R-7.2: `-func`/`-xrefs`/`-trace` (+`-depth`) inspect-only.
- [x] R-6.4 fatias 1–3: lift (`DexIR`) + codegen (rollback) + R-labels
  (`lea [rel label_]` nativo com round-trip) + rewrite IAT
  (`call|jmp [rel __imp_X]` + labels, round-trip) + drivers de teste.
- [x] R-6.5 parcial: `-ast-dump` (resumo AST do `.asm` gerado em stdout).
- [x] R-6.1: `-native` opt-in com round-trip no corpus simples (hello,
  tiny, loop, strings, no_relocs) + fixes (hang collect, D O(n²),
  dispatch C0+, mov-SIB, `.cs_in_code`, spill `[rbp-56]`).
- [x] R-6.2: `dex_lex_one` (`src/front/lexer.asm`, 17 kinds) + driver
  `tests/lex_check.asm` (golden 166 tokens, 0 unknowns).
- [ ] R-2.7 (VEX/EVEX), R-5.3+, R-6.5 resto (`-emit`), R-6.6 — ver ROADMAP + `docs/adr/0001-ast-lexer-codegen.md`.

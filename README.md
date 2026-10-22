<p align="center">
  <img src="Dexter_logo_US.png" alt="Dexter" width="420">
</p>

<h1 align="center">Dexter</h1>

<p align="center">Desassemblador / Reassemblador x64 nativo — NASM / Windows</p>

Ferramenta real, 100% NASM x86-64, sem CRT: lê um PE x64, gera `.asm`
reassemblável e reconstrói o `.exe` — incluindo **round-trip byte-idêntico**
no modo `-m bin` (hello 2560 B e var64 91872 B: `fc /b` igual e
comportamento igual).

Projeto: [github.com/Spoiledpay/Dexter](https://github.com/Spoiledpay/Dexter)

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
tests\run_tests.bat               &:: suíte completa (426/426)
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
| `tests\var64.exe` | x64 real (mingw, 11 seções, TLS, 62 imports) — round-trip bin/win64 |
| `tests\notepad.exe` | PE MSVC x64 real (315 imports, 8 seções) — `-m bin` byte-idêntico |
| `tests\exc.exe` | C++ MinGW (EH/unwind reais) — `-m bin -native` exit 42 |
| `tests\taildata.asm` | Fixture `.data` com `vsize > raw` (D-19 2c-3) |
| `tests\var32.exe`, `tests\link.exe`, `Calculator/Case/Char/color/Color2/Contador.exe` | 32-bit — desmonta em `bits 32` (`[30]`, `[6c]`) |
| `Magic=0` (fixture `tests\out\corrupt_mz.exe`, gerado na suíte) | rejeição limpa (saída 3) |

## Estado atual (v1.2.417)

- Suíte rápida `tests\run_tests.bat`: **426/426 OK**. Suíte lenta
  `tests\run_slow.bat`: **7/7 OK**.
- `-m bin`: **byte-idêntico** no corpus pequeno, no gcc (2 MB) e no
  ld.lld (68 MB), com comportamento verificado.
- `-native` (opt-in): round-trip no corpus simples; no `win64`, `var64`
  roda exit 0 e `notepad` reconstruído passa nas auditorias
  `rip_audit`/`ptr_audit`.
- Import table simbólica, `UNWIND_INFO`, `disp32` RIP relocável, REX exato
  e `.bss` nobits no caminho `win64 -native`.
- `.data` com `vsize > raw`: tail zerado emitido com labels (D-19 2c-3).
- PEs com EH C++ do GCC são recusados no `-native -r` do modo link
  (exit 4; use `-m bin`) — ADR-0004.
- Flags de análise: `-overview`/`-json`, `-func`, `-xrefs`, `-trace`,
  `-rsrc`, `-snapshot`/`-compare`, `--doctor`, `-strings`, `-ast-dump`,
  `-emit db|native`.
- Pendências e fila de execução: `docs/ROADMAP.md` e `marco.md`.

## Licença

Distribuído sob a **licença MIT**. Veja [LICENSE](LICENSE).

Copyright (c) 2026 LabsObjects.

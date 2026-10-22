<p align="center">
  <img src="Dexter_logo_US.png" alt="Dexter" width="420">
</p>

<h1 align="center">Dexter</h1>

<p align="center">Native PE disassembler / reassembler — x86-64 and x86 — NASM / Windows</p>

<p align="center">
  <a href="README.md">Português</a> ·
  <a href="README.en.md"><strong>English</strong></a> ·
  <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <a href="https://github.com/Spoiledpay/Dexter/actions/workflows/ci.yml"><img src="https://github.com/Spoiledpay/Dexter/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <a href="https://github.com/Spoiledpay/Dexter/releases/latest"><img src="https://img.shields.io/github/v/release/Spoiledpay/Dexter?display_name=tag" alt="Release"></a>
</p>

> **Support the project.** Dexter is independently developed and remains
> free and open source. If it helps your work, consider supporting ongoing
> development through
> [GitHub Sponsors](https://github.com/sponsors/Spoiledpay). Any contribution
> is greatly appreciated and helps keep time dedicated to tests, fixes and
> new features. Thank you for being part of it.

Dexter is a real, 100% NASM x86-64 tool with no CRT: it reads a PE
(PE32/PE32+), generates reassemblable `.asm`, and rebuilds the `.exe`.
`-m bin` produces a **byte-identical round-trip** (hello 2560 B, var64
91872 B, gcc 2 MB and ld.lld 68 MB), with verified behavior.

Project: [github.com/Spoiledpay/Dexter](https://github.com/Spoiledpay/Dexter)
· Download: [Releases](https://github.com/Spoiledpay/Dexter/releases/latest)

## What it does today

### Disassembly and reassembly

- **PE32+ (x64) and PE32 (x86)**: validates DOS/NT headers, sections,
  imports, exports, relocations, resources and unwind info
  (`.pdata`/`.xdata`).
- **Real x86-64/x86 decoder**: legacy prefixes, REX, ModRM/SIB,
  RIP-relative addressing, 1/2/`0F38`/`0F3A` tables, groups, x87, VEX/EVEX
  and 3DNow! (byte-exact lengths; VEX/EVEX/x87 still fall back to `db` in
  `-native`).
- **`-m win64`**: generates `.asm`, assembles with `nasm -f win64`, and
  links with `link.exe`; DataDirectories are remapped by section/offset.
- **`-m bin`**: generates a self-contained `.asm` and assembles with
  `nasm -f bin`; the **byte-faithful** path for real PEs (including
  gcc/ld.lld).
- **`-native`**: emits real mnemonics/labels when possible
  (`mov`, `lea`, `[rel label]`, `call|jmp [rel __imp_X]`), with byte-exact
  `db` fallback; symbolic import table, symbolic `UNWIND_INFO`, relocatable
  RIP-relative `disp32`, exact REX, `.bss` nobits and `.data` tail with
  `vsize > raw`.
- **`-ast-dump`**: parses the generated `.asm` back and prints
  `AST funcs=F blocks=B instrs=I succs=S db=D equ=E dir=R`.

### Analysis (inspect-only, never writes `.asm`)

- `-overview` / `-json`: image base, entrypoint, sections, imports/exports/relocs.
- `-func <VA>`: function bounds plus calls/jumps.
- `-xrefs <VA>`: code and data references (honest `truncated` flag).
- `-trace <VA>` / `-depth <N>`: call-chain DFS.
- `-rsrc`: three-level resource inventory (type/name/language).
- `-snapshot <json>` / `-compare <b.exe>`: FNV-1a fingerprint and diff.
- `--doctor`: nasm/link/kernel32 + version.

### Robustness

- Honest `db` fallback for unsupported opcodes; never a false error.
- Every PE field is validated against the file size.
- `tests/fuzz_pe.py`: deterministic mutations (MZ, `e_lfanew`, sections,
  imports, `.pdata`/`.xdata`, truncation); the mutant is never executed.

## Quick start

```bat
build.bat

:: win64 round-trip (nasm + link)
out\dexter.exe tests\hello.exe -o tests\out\hello.asm -r -O tests\out\hello_rt.exe
tests\out\hello_rt.exe            &:: prints "hi"

:: byte-identical round-trip (nasm -f bin)
out\dexter.exe tests\var64.exe -o tests\out\var64_bin.asm -m bin -r -O tests\out\var64_bin.exe
fc /b tests\var64.exe tests\out\var64_bin.exe

:: full test suite
tests\run_tests.bat               &:: 426/426
```

### Analysis examples

```bat
out\dexter.exe app.exe -overview
out\dexter.exe app.exe -overview -json
out\dexter.exe app.exe -func 0x140001000
out\dexter.exe app.exe -xrefs 0x140001000
out\dexter.exe app.exe -trace 0x140001000 -depth 8
out\dexter.exe app.exe -rsrc
out\dexter.exe app.exe -snapshot app.json
out\dexter.exe app.exe -compare other.exe
out\dexter.exe app.exe --doctor
```

### Output and control

| Flag | Effect |
|---|---|
| `-o <file.asm>` | Generated NASM source (default: `<input>.asm`) |
| `-O <file.exe>` | Reassembled `.exe` (implies `-r`) |
| `-m win64\|bin` | Rebuild path (`win64` = nasm+link; `bin` = byte-faithful) |
| `-r` | Reassemble after generating the `.asm` |
| `-L <linker>` / `-N <nasm>` | Explicit linker/nasm paths |
| `-s <section>` | Disassemble only the given section; the rest becomes data |
| `-start <RVA>` / `-end <RVA>` | Code range (hex) |
| `-hex` | `; @0xVA` / `; mne` comments |
| `-nop-pad` | `0x90`/`0xCC` as real `nop`/`int3` |
| `-no-imports` / `-no-relocs` | Do not process imports/relocs (omit `.reloc`) |
| `-strings` | ASCII runs as `db "..."`, 0; with `-native`, `dq label_` |
| `-native` / `-emit db\|native` | Opt-in native emitter (`-native` is an alias) |
| `-ast-dump` | AST summary of the generated `.asm` |
| `-v` / `-vv` / `-q` | Verbose 1, verbose 2, quiet |
| `-ver` / `-h` / `--help` | Version / help |

Exit codes: `0` success, `1` usage error, `2` I/O, `3` invalid PE,
`4` unsupported opcode or `-native -r` refusal for GCC C++ EH,
`5` rebuild failure. Full reference: [docs/CLI.md](docs/CLI.md).

## Tests

- **Fast suite** (`tests\run_tests.bat`): **426/426 OK** on 1.2.419.
- **Slow suite** (`tests\run_slow.bat`): **7/7 OK** — ld.lld 68 MB
  byte-identical + gcc 2 MB byte-identical and compiling `hello.c`.
- **Fuzz** (`tests/fuzz_pe.py`): corrupted PEs must never crash/hang;
  accepted exits `{0,1,2,3,5}`.
- **CI**: [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on
  `windows-latest` with MSVC + NASM: build + fast suite. The large fixtures
  `tests/gcc.exe` and `tests/ld.lld.exe` are not versioned and are skipped
  in CI (`DEXTER_SKIP_LARGE=1`); the full suite runs locally.

## Current version

**Dexter 1.2.419** (`-ver`). The patch number is incremented on every
`build.bat` via `version.bin` + `tools\bump_version.ps1`.

## Known limitations (honest)

- PEs with **GCC/MinGW C++ EH** (`__gxx_personality_*` /
  `__gcc_personality_*`) use pcrel tables that `link.exe` does not relocate;
  `-native -r` in link mode is **refused with exit 4** and recommends
  `-m bin` (ADR-0004). The faithful path is `-m bin -native -r`.
- x64 SIB-abs symbolic index is still numeric (x32 is already symbolic).
- VEX/EVEX/x87 operands are decoded with byte-exact lengths, but the native
  emitter still uses `db` for them.
- `-no-imports` disables GCC personality detection (documented limit).
- R-6.6 (optimizable IR + own backend, no nasm) remains future work.

## Requirements

- Windows x64.
- `nasm.exe` (in `C:\Nasm\` or on `PATH`) and `link.exe` (MSVC).
- `kernel32.lib` from the Windows SDK (`build.bat` finds it; `SDKLIBDIR`
  overrides).

## Build

```bat
build.bat
```

Output: `out\dexter.exe`. `clean.bat` removes `out\`/`obj\`.

## Layout

```text
build.bat  clean.bat  version.bin
include/         win64.inc dexter.inc pe.inc errors.inc macros.inc
src/cli io pe disasm gen util   NASM modules, one responsibility each
src/front/       lexer + parser + AST
src/back/        lift (DexIR) + codegen
docs/            CLI ARQUITETURA ROADMAP REVISAO CHANGELOG PE_NOTES ADRs
tests/           corpus + fixtures + run_tests.bat + run_slow.bat + fuzz
out/ obj/        build artifacts (ignored)
```

## Contributing

Contributions are welcome: open an issue with a sample PE (no sensitive
data), describe the expected behavior, and include the generated `.asm`/log
if possible. Before changing code, run `build.bat` and
`tests\run_tests.bat`.

## License

Distributed under the **MIT License**. See [LICENSE](LICENSE).

Copyright (c) 2026 Labsobjects.org | Developer.

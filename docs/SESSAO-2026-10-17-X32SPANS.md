# Sessão 2026-10-17 — jump-to-code em x32: spans de 4 bytes (`dd`)

> Leitura: `skill.md` → `Projeto.md` → `marco.md` → `docs/ROADMAP.md` → este.
> **STATUS: verde, NÃO commitado** (ordem do usuário: sem commits). Firmware
> **1.2.381**. `tests\run_tests.bat` **369/369 OK**.

## 0. Placar

- `build.bat` limpo (1.2.381) + `run_tests.bat` **369/369 OK** (368 + 1).
- `run_slow.bat` **7/7 OK**.

## 1. O que foi feito

O pré-scan de ponteiros (`.collect_strs` passada B) e o emissor de spans
(`.wds_emit_span`) eram **8 bytes** (`dq`); em x32 as tabelas de ponteiro
(`dd VA`) ficavam `db` byte a byte (o x32 chegava a forçar `g_spanflags=1`
"corpos db" e o pré-scan era gated em `arch == X64`).

Agora o **stride vem do arch** (8 = `dq`/qword; 4 = `dd`/dword):

```
label_402008:
    dd label_401017          ; case c0 (código, D-7)
    dd label_40101E          ; c1
    dd label_401025          ; c2
    dd label_40102C          ; c3
label_402018:
    db 0x01, 0x00, 0x00, 0x00, ...   ; valores 1 (não-VA): db fiel
```

Onde: `src/gen/rebuild.asm` — `.collect_strs` passada B (leitura dword em x32),
`.wds_emit_span` (`stride` em `[rbp-88]`, `s_dqpre`/`s_dd4`, `o += stride`),
`.wds_plain` (removida a linha que punha `g_spanflags=1` em x32) e o gate de
arch do pré-scan removido.

## 2. Evidência

```bat
build.bat                                                        rem limpo 1.2.381
nasm -f win32 -o tests\out\absidx.obj tests\absidx.asm
link /nologo /nodefaultlib /machine:x86 /subsystem:console /entry:main /out:tests\out\absidx.exe ... X86LIB
out\dexter.exe tests\out\absidx.exe -o tests\out\absidx_nat.asm -native -r -O tests\out\absidx_rt.exe -q
findstr "dd label_401017" tests\out\absidx_nat.asm      rem jump-to-code simbólico
tests\out\absidx_rt.exe                                  rem exit 42
tests\run_tests.bat                                      rem 369/369 OK
tests\run_slow.bat                                       rem 7/7 OK
```

## 3. Armadilhas (CTX / `PE_NOTES §21`)

- **Três lugares, não um**: além do emissor (`.wds_emit_span`), o **pré-scan**
  (`.collect_strs`) lê o span e o **`.wds_plain`** desligava spans em x32 —
  corrigir só o emissor não muda nada (o `g_spanflags=1` cai em `db` antes).
  Sintoma: rótulo/patch aplicados mas saída ainda `db` (silencioso).
- A leitura dword precisa **zero-estender** (`mov eax,[mem]`) — a checagem
  `v >= base` e o cálculo do rva usam o valor inteiro.
- `[30]`–`[33]` (x32) e `[49]` (SIB-abs x64) seguem verdes: o stride do x64
  não mudou.

## 4. Retomada

- Fila do `marco.md` §8: só resta **`-s` + RIP** (gap não reproduzido nos
  probes; hipótese em aberto) e itens de fidelidade de PE grande (D-19).

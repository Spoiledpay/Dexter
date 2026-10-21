# Sessão 2026-10-17 — Índice simbólico em x32 (SIB-abs, tabela de switch)

> Leitura: `skill.md` → `Projeto.md` → `marco.md` → `docs/ROADMAP.md` → este.
> **STATUS: verde, NÃO commitado** (ordem do usuário: sem commits). Firmware
> **1.2.379**. `tests\run_tests.bat` **368/368 OK**.

## 0. Placar

- `build.bat` limpo (1.2.379) + `run_tests.bat` **368/368 OK** (361 + 7 novos).
- `run_slow.bat` **7/7 OK**.

## 1. O que foi feito

Em x32, `jmp dword [jtab+eax*4]` (switch com tabela **absoluta**) tem endereço
`disp32 + index*scale` com o disp32 = **VA** da tabela (base 0x400000, cabe em
32 bits). Antes saía numérico (`0x402008`); agora sai simbólico:

```
jmp dword [nosplit label_402008+eax*4]
mov ecx, [nosplit label_402018+edx*4]
...
label_402008:
    db 0x17, 0x10, 0x40, 0x00, ...      ; tabela (dd VAs dos cases)
```

Onde:
- `src/gen/rebuild.asm` — `.cs_abs32sib` (scanner x32): reconhece
  `mod=00 rm=100` + `SIB base=101` (sem base) + disp32 VA e **registra a RVA
  no R** (mesmo R dos refs RIP).
- `src/disasm/emit_nasm.asm` — `.fo_sibabs`: em x32, busca a RVA no R
  (`g_abs_vas`/`g_abs_n`/`g_abs_base`) e emite `label_<VA>`; x64 fica numérico.
- Fixture `tests/absidx.asm` (x32, switch real + load indexado) + seção `[51]`.

## 2. Evidência

```bat
build.bat                                                    rem limpo 1.2.379
nasm -f win32 -o tests\out\absidx.obj tests\absidx.asm
link /nologo /nodefaultlib /machine:x86 /subsystem:console /entry:main /out:tests\out\absidx.exe ... X86LIB
out\dexter.exe tests\out\absidx.exe -o tests\out\absidx_nat.asm -native -r -O tests\out\absidx_rt.exe -q
findstr "[nosplit label_402008+eax*4]" tests\out\absidx_nat.asm   rem simbólico
tests\out\absidx_rt.exe                                            rem exit 42
tests\run_tests.bat                                                rem 368/368 OK
tests\run_slow.bat                                                 rem 7/7 OK
```

## 3. Técnica / armadilhas (CTX / `PE_NOTES §20`)

- **Só x32 é simbolizável**: a VA tem de caber em 32 bits. x64 (base
  0x140000000) tem disp32 que nunca é VA da imagem; e em `-f bin` um label
  absoluto precisaria de `+C`, que o emissor não tem.
- **SIB base = bits 2-0.** Extraí-lo com `shr 5` (bits 7-5) fazia o check
  `base==101` nunca casar → a VA não entrava no R → saía numérico (sem erro,
  silencioso). Achado comparando com o encoding do nasm (`0x85`/`0x95`).
- **Dispatch de SIB antes do check `rm==101`**: `.cs_abs32` testava
  `modrm&0xC7 == 0x05` (sem SIB) antes de olhar `has_sib`, o que rejeitava a
  forma SIB (`rm=100`).
- **Canal emissor↔rebuild = DADOS, não função.** O driver `codegen_check`
  (`[12]`) linka `emit_nasm.obj` **sem** `rebuild.obj`; um `extern` de função
  novo (primeira tentativa: `dex_abs_label_va`) deixou o link da suíte
  quebrado. Solução: `emit_nasm.asm` **define** `g_abs_vas`/`g_abs_n`/
  `g_abs_base` (0 = desligado) e o `rebuild` só escreve; o emissor faz a
  busca binária. Assim qualquer linker que inclua `emit_nasm.obj` fecha.
- **R é chaveado por RVA** (o data walker compara `v - image_base`), por isso
  o emissor recebe também `g_abs_base` para converter VA→RVA.

## 4. Retomada

- Fila do `marco.md` §8: jump-to-code restante → `-s` + RIP (o gap de `-s`
  +RIP não foi reproduzido nos probes; hipótese em aberto).

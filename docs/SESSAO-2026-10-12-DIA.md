# Sessão 2026-10-12 — dia inteiro (155/155 → 178/178)

> Leitura: `skill.md` → `marco.md` → `docs/ROADMAP.md` → este arquivo.
> Binário ao fechar: Dexter 1.2.254 (`build.bat` limpo + `run_tests.bat`
> 178/178 OK). Commits do dia (base: `16cbf69`, R-7.4 155/155):
> `b32d94a` (marco sync) + `a30c8c7` (Fase 2) + `358a60d` (R-7.5
> `--doctor`) + `fed240a` (3b dq-pointer) + `f11343a` (3c fuzz + hang)
> + `9363fce` (R-6.5 `-emit`).

## 1. Marco sincronizado (`b32d94a`)

`marco.md` §0 marcava 67/13 BLOQUEADA (1.2.16x); base real era R-6.4.3 +
R-7.1–R-7.4 (155/155, 1.2.245). Atualizado §0/§1/§7 + linha REVISAO.
Prova: `build.bat` OK 1.2.247 + suíte 155/155 antes do commit.

## 2. Fase 2 IAT R-3.3/R-4.5 FECHADA por auditoria (`a30c8c7`, sem código)

`[13]`/`[14]` já verdes: hello 3×`jmp [rel __imp_]` + var64 2×`call`/
14 labels, 0 `extern`, round-trip `hi`. ROADMAP R-3.3/R-4.5 → `[x]`
(ativo em `-native`; `db-copy` segue default). Suíte 155/155 revalidada.

## 3. R-7.5 `--doctor` (`358a60d`, 1.2.248, `[20]` 8 checks, 163/163)

`src/diag/doctor.asm` (`dex_doctor → 0`, frame 5 pushes+sub 32, sem
heap): versão + `nasm/link <path> ok|missing` (via `dex_open_read`,
respeita `-N`/`-L`) + `kernel32: ok` + `input: valid PE x64` (fatos,
não inferências). `DF_DOCTOR`, parse `-doctor`/`--doctor`, despacho
`overview > doctor > rsrc`, ajuda. Teste-primeiro: `[20]` falhou com
`unknown option` antes do código.

## 4. 3b dq-pointer (`fed240a`, 1.2.250, `[21]` 5 checks, 168/168)

Gap: `s_tab` (`dq s1, 11, …`) saía `db` hexadecimal — ponteiros
desalinhados p/ starts que NÃO eram runs (`\r\n` quebra `.str_run`) nem
R. Solução: pré-scan `.collect_strs` (runs + alvos de ponteiros →
`g_symR`, espelhando o conjunto emitido na direção segura) +
`.wds_emit_span` (`dq label_`, validador compartilhado `.ptr_tgt_ok`
que rejeita código/`.reloc` skipada/fora-do-eff; regra nova D-17).
`s_tab` virou tabela simbólica; round-trip strings com stdout
byte-igual; default bit-idêntico. Bug real no caminho: `dq` com VA do
slot (auto-ref) em vez da VA alvo — pego pelo `[21]`, fix `base+rva`.
Golden `tests/ref_native/ref_strings.asm` regenerado (só adições;
`ref_hello` difere só por cookie novo a cada link — pré-existente).

## 5. 3c fuzz + hang em imports (`f11343a`, 1.2.253, `[22]`, 170/170)

`tests\fuzz_pe.py` (seed determinístico, mutante nunca executado;
passa = saída em {0,1,2,3,5}): 20 (seed 7) + 200 (seed 42) + 300
(seed 1234) + 50 var64 limpos. Achou 3 TIMEOUTs (hang, não crash):
1 flip em terminador de descritor (`0x747: 00→87`) → ILT lido como
descritor → early-paths do `.fill` com `di/vi` em `r10d/r11d`
clobberados por `dex_rva_to_offset` (classe D-8) → `inc` nunca
alcançava `n_desc`. Prova: bisseção por flags (`-no-imports` escapa),
stdout parcial, flip isolado, sondas temporárias (`F F F…` sem `T`,
100% removidas depois). Fix: spill `[rbp-64]/[rbp-68]` (10 linhas).

## 6. R-6.5 `-emit db|native` (`9363fce`, 1.2.254, `[23]` 8 checks)

Só plumbing sobre `DF_NATIVE` (`native` ≡ `-native`, `db` limpa o bit;
`-native` segue como alias; last-wins; valor inválido/ausente → 1).
Provas: `-emit db` ≡ `-native -emit db` (`fc /b` igual); last-wins nos
dois sentidos. Quirk achado: `|` em `echo` do `.bat` vira pipe —
cabeçalho do `[23]` usa `db-native`.

## 7. Estado final e resto

Suíte 178/178 em 1.2.254. Resta (Fase 4/robustez + dívidas): jump
tables p/ código, SEH/unwind reemitido, VEX/EVEX/x87, R-6.6 backend
próprio, `bin` com imports regenerada, goldens com/sem flag, D-1,
D-2/D-4..D-7, D-15/D-16 latentes, tag.

## 8. Lote rápido pós-sessão (mesmo dia, 1.2.254, sem código)

`[24]` (flags `-q`/`-v`/`-vv` geram `.asm` byte-idêntico, `fc /b`;
`[10]` já cobria `-ast-dump`) + D-1 fechada como superada
(`adr/0001` numerado; convenção `NNNN-*.md`) + tag `v1.2.254`
anotada. Suíte **182/182 OK** (commit `595c865`).

## 9. Continuação (mesmo dia, 1.2.254 → 1.2.257, 182/182 → 199/199)

Lote D-2..D-6 (commit `e5c7861`, 1.2.256, `[25]`+`[26]`, 191/191):

- D-6 com bug real: `-end` ignorado com `-start` presente
  (`.wcs_oor_l` só estendia o lote abaixo do `start`; acima do `end`
  fechava vazio e reentrava como in-range → saída idêntica ao full).
  Fix 2 linhas (cair no check do `end`). `[25]` falhou pré-fix
  (`combo igual ao full`) e passa + round-trip `hi` pós-fix.
  Collect (`.collect_syms`) já tratava ambos os bounds — só o
  walker tinha o defeito.
- D-5: `-no-imports` × `-native` seguro (fallback `db`, 0 `__imp_`,
  rebuild `hi`); `[26]` trava o combo.
- D-4: externs mortos `dex_file_read_at`/`write_at` extirpados de
  `rebuild.asm` (declarados, nunca chamados).
- D-2: `.bss` sai vazia no win64; var64 tem 0xB90 referenciados e o
  rebuild win64 roda mas imprime vazio (R-4.4 confirmada p/ PEs
  complexos); caminho fiel `-m bin`; contramedida futura anotada
  (`resb` vsize nobits).

Jump tables 1ª fatia (commit `d622310`, 1.2.257, `[27]` 8 checks):

- Corpus `tests/jtable.asm` (switch absoluto `dq`, base via
  `lea [rel]`, `jmp rax`; imprime `2`, exit 0; com marcador
  FONTE SAGRADA e build na suíte como `[1]`).
- Bug bloqueador achado pelo corpus: `jmp rax` (`FF E0`, sem REX)
  saía `jmp eax` — inválido em 64 bits, rebuild falhava (5).
  Causa: `.l1_ffmem` assumia operando 32 por default; `call/jmp`
  não têm forma 32 (como `push`, já tratado). Fix espelha o do
  `push` (força size 4→8 em `/2`/`/4`; `/0`/`/1` intocados).
- Base da tabela já era rotulada via R (`lea [rel label_…]`
  confirmado); entradas (VAs em código) seguem `db` — validador
  3b as rejeita por desenho; resolução de alvos = futuro.
- Quirk de bancada: labels locais NASM (`.c0`) colidem com a label
  da tabela na mesma linha (`jtab.c0`) — corpus usa nomes
  file-scope (`jt_c0`).

Resta: SEH/unwind reemitido, VEX/EVEX/x87 rotulado, R-6.6 backend
próprio, `bin` com imports regenerada, D-3 resto (`strpool`/labels),
D-7 tabela D, D-15/D-16 latentes, tag (atual: `v1.2.254`).

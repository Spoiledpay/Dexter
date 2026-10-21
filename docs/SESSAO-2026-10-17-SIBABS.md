# Sessão 2026-10-17 — SIB-abs com índice ("loads indexados", R-5.4)

> Leitura: `skill.md` → `Projeto.md` → `marco.md` → `docs/ROADMAP.md` → este.
> **STATUS: verde, NÃO commitado** (ordem do usuário: sem commits). Firmware
> **1.2.371**. `tests\run_tests.bat` **357/357 OK**.

## 0. Placar

- `build.bat` limpo (1.2.371) + `run_tests.bat` **357/357 OK** (350 + 7 novos).
- `run_slow.bat` **7/7 OK** (gcc/ld.lld seguem byte-idênticos).
- Fixture `tests/sibabs.asm`: `-m bin -native` byte-idêntico + exit 42.
- Regressão do emissor: notepad `-m bin -native` `fc /b` 0 diffs.

## 1. O que foi feito

Operandos de memória **sem base** (`ModRM mod=00 rm=100` + `SIB base=101`),
cujo endereço é `disp32 + index*scale` — o `[rcx*4]` de x64 e o
`[0x40A000+eax*4]` (tabela absoluta) de x32 — deixavam de ser emitidos (caíam
em `db`). Agora saem textuais e **byte-exatos**:

```
lea rax, [nosplit rcx*4]                    ; disp32==0
lea eax, [nosplit abs 0x2+rax*2]            ; x64, disp != 0
jmp dword [nosplit 0x401000+eax*4]          ; x32, tabela absoluta
```

Onde: `src/disasm/emit_nasm.asm` — `.fo_ripabs` (checa `has_sib` antes do
modo de endereço), `.fo_sibabs` (novo ramo com índice), sub-rotina
`.fo_idxemit` (emissão de `index*scale`, reusada por base+index), string
`s_nosplit`.

## 2. Evidência (comandos exatos)

```bat
build.bat                                                            rem limpo 1.2.371
out\dexter.exe tests\out\sibabs.exe -o tests\out\sibabs_nb.asm -m bin -native -r -O tests\out\sibabs_nb.exe -q
fc /b tests\out\sibabs.exe tests\out\sibabs_nb.exe                   rem 0 diffs
tests\out\sibabs_nb.exe                                             rem exit 42
out\dexter.exe tests\notepad.exe -o tests\out\notepad_nb.asm -m bin -native -r -O tests\out\notepad_nb.exe -q
fc /b tests\notepad.exe tests\out\notepad_nb.exe                     rem 0 diffs (regressão)
tests\run_tests.bat                                                  rem 357/357 OK
tests\run_slow.bat                                                   rem 7/7 OK
```

## 3. Duas armadilhas do NASM (registradas no CTX / `PE_NOTES §18`)

- **`nosplit` é obrigatório.** `lea eax, [abs 0x2+rax*2]` o NASM monta como
  `8D 44 00 02` = `lea eax, [rax+rax+0x2]` (4 B) em vez de
  `8D 04 45 02 00 00 00` (7 B): ele "splitaria" `idx*2` em `base+index`
  (mesmo registrador) para encurtar. `nosplit` força a forma SIB-abs exata.
  Só o scale 2 é afetado (scale 4/8 não têm forma splitada curta).
- **`abs` vem PRIMEIRO (x64).** `[rcx*4+abs 0x10]` = *expression syntax
  error*; o correto é `[nosplit abs 0x10+rcx*4]`. Em x32 não há `abs`.
- **disp32 é estrutural** nesta forma (não há variante sem disp para
  base=101), então o disp 0 **não** cai em `db` (difere de `.fo_disp`).
- **Bug colateral x32 corrigido:** `.fo_ripabs` tomava `.fo_abs32` antes de
  checar `has_sib` → descartava o índice. Agora o check de SIB vem primeiro.

## 4. Limite honesto (o que NÃO foi feito)

- **Base simbólica do índice** (o "índice simbólico" do roadmap): o disp32
  sai numérico (`abs 0x…`), não `label_<VA> + C`. Motivo técnico: o emissor
  `dex_emit_native` é compartilhado win64/win32/bin e **não tem canal** para
  (a) consultar se um VA tem label nem (b) aplicar a correção `+C` que um
  operando **absoluto** exige em `-f bin` (label = file-offset). Em x64 o
  disp costuma ser constante pequena (2/4), sem VA a rotular; em x32 `-native`
  o caminho é allowlist-gated. Fica como fatia futura (precisa de decisão de
  arquitetura: passar C/modo ao emissor).

Observação honesta (pré-existente, não desta fatia): `notepad.exe` **win64
`-native`** (não-bin) continua **falhando no nasm** com *symbol not defined* nos
`dd label_<UnwindInfo> wrt ..imagebase` da `.pdata` — o `.xdata` do MS está
fundido no `.rdata` e o caminho win64 não emite esses labels (R-5.4 estendido
corrigiu só o caminho `-m bin`). Confirmado: os 19 `nosplit` emitidos não
geram erro algum; os erros são só `.pdata`. O caminho fiel segue `-m bin
-native` (byte-idêntico, `[46]`).

## 5. Retomada

- Fila do `marco.md` §8: base simbólica do índice / jump-to-code → `-s` + RIP.

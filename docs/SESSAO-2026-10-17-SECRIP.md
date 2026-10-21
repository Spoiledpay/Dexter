# Sessão 2026-10-17 — `-s <seção>` × SEH simbólico: fecha a fila "`-s` + RIP"

> Leitura: `skill.md` → `Projeto.md` → `marco.md` → `docs/ROADMAP.md` → este.
> **STATUS: verde, NÃO commitado** (ordem do usuário: sem commits). Firmware
> **1.2.382**. `tests\run_tests.bat` **376/376 OK** + `run_slow.bat` **7/7**.

## 0. Placar

- `build.bat` limpo (1.2.382) + `run_tests.bat` **376/376 OK** (369 + 7 de `[52]`).
- `run_slow.bat` **7/7 OK**.

## 1. O que era a fila "`-s` + RIP"

Última pendência da ordem do `marco.md` §8, registrada como "gap não
reproduzido nos probes; hipótese em aberto" (sessões `…SIBABS`, `…CRLF`,
`…X32SPANS`). A hipótese era "RIP-relative referenciando código filtrado".
**A hipótese estava errada** — o RIP (via `-m bin`) é sólido.

## 2. Descoberta — o RIP está verde

19 probes `-s <seção> -m bin -native` sobre `exc/notepad/var64/tiny/loop/
strings/jtable/no_relocs` (várias seções por binário): `nasm -f bin` **0
erros** e `fc /b` vs original **0 diffs**. Ex.: `tests/exc.exe -s .text -m bin
-native` byte-idêntico **e** roda o throw/catch (`exit 42`).

## 3. Defeito real — `-s` × `.pdata`/`.xdata` (R-5.4)

No caminho `asm`/`win64 -native` a exceção simbólica da R-5.4 (`.pdata`/
`.xdata` → `dd label_<VA> wrt ..imagebase`) **ignorava o filtro**:

| comando | nasm |
|---|---|
| `tests\exc.exe -native` (sem `-s`) | **0 erros** |
| `tests\exc.exe -s .text -native` | **0 erros** |
| `tests\exc.exe -s .rdata -native` | **234 erros** |
| `tests\var64.exe -s .rdata -native` (`-s .idata`) | **234 erros** |

Com `-s .rdata` a `.text` vira `db` e não ganha `label_` por-VA; a `.pdata`
referenciava `label_140001017` **2× e definido 0×** (122 `symbol not defined` +
113 `label changed during code generation`). Violação do **D-17**.

## 4. Fix

`src/gen/rebuild.asm`, `.walk_data`: com `section_filter != 0` a exceção
`.pdata`/`.xdata` é **pulada** e as duas caem no caminho `db` comum
(`.wd_plain`) — direção segura do D-17 e exatamente o contrato do `-s`
("demais seções viram `db`"). Efeito: `.pdata`/`.xdata` saem
`section .pdata rdata` + `db` **byte-fiel**; `-s .text` segue assemblando;
`-m bin` (que percorre tudo e rotula cada instrução) intacto.

## 5. Evidência

```bat
build.bat                                                        rem limpo 1.2.382
out\dexter.exe tests\exc.exe -s .rdata -o tests\out\secrip_rdata.asm -native -q
C:\Nasm\nasm.exe -f win64 -o tests\out\secrip_rdata.obj tests\out\secrip_rdata.asm   rem 0 erros (antes 234)
out\dexter.exe tests\exc.exe -s .rdata -m bin -native -o tests\out\secrip_bin.asm -q
C:\Nasm\nasm.exe -f bin -o tests\out\secrip_bin.exe tests\out\secrip_bin.asm
fc /b tests\exc.exe tests\out\secrip_bin.exe                      rem 0 diffs
tests\run_tests.bat                                               rem 376/376 OK
tests\run_slow.bat                                               rem 7/7 OK
```

## 6. Limite honesto + armadilhas (CTX / `PE_NOTES §22`)

- **Limite honesto:** `-s <seção>` que **exclui a seção do entrypoint** +
  `-r` (rebuild via link) segue impossível — o `global label_<entry>` do
  cabeçalho referencia símbolo não definido → `LNK2001`/`exit 5`. Já falhava
  antes (no nasm); agora falha no link, honestamente. `-s .text -r` linka OK.
- **Armadilha de ambiente:** o `nasm` do `PATH` aqui é o **2.16.01 do
  Strawberry** (`C:\Strawberry\c\bin\nasm.exe`), não o do projeto
  (`C:\Nasm\nasm.exe`, **3.01**). Com o 2.16 o mesmo `.asm` acusa **19
  `mismatch in operand sizes` falsos** → quase conclusão errada. Sempre usar
  `C:\Nasm\nasm.exe`.

## 7. Retomada

- Fila do `marco.md` §8: **esgotada** (só resta fidelidade de PE grande,
  D-19). Próximos candidatos: R-5.4 win64 de PE MS real (D-19) ou `-emit`
  restante (R-6.5).

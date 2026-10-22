# ADR 0004 — Recusa honesta do `win64 -native -r` com EH C++ do GCC (D-19 fatia 2c-2)

- **Data:** 2026-10-22
- **Status:** aceito
- **Contexto:** D-19 fatia 2c (o `link.exe` reordena/funde seções), D-19
  fatia 2c-3 (tail de `.data`) e R-5.4 (SEH/unwind reemitido).
- **Requisito:** não entregar um `.exe` win64 reconstruído que carrega mas
  falha em tempo de execução por causa de tabelas de exceção C++ do GCC.

## Contexto

O `win64 -native -r` reconstrói `.text`, `.idata`, `.pdata` e `.xdata` de
forma simbólica. Para PE MSVC (`notepad.exe`) e para os fixtures simples, o
link recalcula as relocações e o `.exe` funciona.

O fixture `tests/exc.exe` (MinGW-w64 `g++`) usa `__gxx_personality_seh0` e um
LSDA com **encodings posicionais** (`pcrel`) e seções COFF `/NNN`. Esses
campos não têm relocação entre seções no COFF: quando o `link.exe` move a
seção alvo, o deslocamento relativo continua apontando para o layout antigo.
O resultado medido é `0xC0000005` dentro de `libstdc++-6.dll`, com `.text`
exato e `.xdata` byte-idêntico (D-19 2c, `PE_NOTES §27/§28`).

Corrigir de verdade exige uma das duas rotas:

1. **recusar** `-native -r` no modo link quando a personalidade C++ do GCC
   for detectada, recomendando `-m bin` (layout preservado, já exit 42);
2. **pós-patch** de todos os campos pcrel do LSDA — exige parser de DWARF EH
   (LSDA, action table, type table), reescrita após o link e novo gate de
   comportamento.

A rota 2 é grande, depende de reimplementar o unwinder do GCC e não cabe no
fecho da fatia 2.

## Decisão

Adotar a rota 1, com escopo explícito:

1. Detectar, **na import table já parseada**, as personalidades
   `__gxx_personality_{v0,seh0,sj0}` e `__gcc_personality_{v0,seh0,sj0}`.
2. Se `-native` **e** `-r` estiverem ativos **e** o modo não for `-m bin`,
   retornar **exit 4** antes de gerar/rebuildar, com mensagem em inglês
   citando `pcrel` e o caminho `-m bin`.
3. `-native` sem `-r` continua permitido (geração/auditoria/nasm).
4. `-m bin -native -r` continua permitido e é o caminho fiel (exit 42).
5. A detecção usa os imports; `-no-imports` a desativa (limite documentado).

## Alternativas descartadas

- **Deixar rebuildar e avisar:** entrega um `.exe` que carrega e falha em
  runtime; viola a regra 1.1/1.6 (não retornar sucesso falso).
- **Pós-patch do LSDA agora:** escopo de outra fase; sem parser DWARF EH não
  há como garantir todos os campos (action/type tables e `/NNN`).
- **Recusar todo `-native -r`:** bloquearia `var64`/`notepad`, que funcionam.
- **Scan bruto dos bytes do arquivo:** `ld.lld.exe` contém os nomes das
  personalidades em strings, mas não as importa; recusaria um PE válido.

## Consequências

- `tests/exc.exe` deixa de ser o fixture de rebuild win64; o caminho fiel
  documentado é `-m bin -native`. Os gates de link/`DataDirectories`/import
  table no win64 passam a usar `var64.exe` (PE real, 5 dirs) e
  `notepad.exe` (PE MSVC real, auditorias `rip_audit`/`ptr_audit`).
- O parser de imports continua testado em `exc` (69 imports, geração pura).
- Limite honesto: `-no-imports` impede a detecção; um usuário que combine
  `-no-imports -native -r` com GCC C++ assume o risco.
- Quando a rota 2 for implementada, a recusa vira o fallback seguro para
  personalidades não reconhecidas.

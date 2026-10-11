@echo off
rem =====================================================================
rem Dexter/tests/run_tests.bat — suíte de regressão (round-trip + negativos)
rem Uso: tests\run_tests.bat
rem Requer: out\dexter.exe (build.bat), C:\Nasm\nasm.exe, tests\hello.asm
rem Códigos: 0 tudo OK; 1 alguma falha. Nunca executa binários suspeitos
rem sem timeout: usa timeout.exe (sinaliza falha se travar).
rem REGRA (2026-10-07, D-12): checar saída do dexter SEMPRE com
rem `if !errorlevel! NEQ 0` (delayed). `if errorlevel 1` IGNORA crash
rem (AV = -1073741819, negativo: falso "OK" + testes seguintes pulados
rem em silêncio via `if exist`). findstr/fc retornam 0/1 (imunes).
rem =====================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set PASS=0
set FAIL=0
set DX=out\dexter.exe

if not exist "%DX%" (
    echo FALHA: %DX% nao existe. Rode build.bat primeiro.
    exit /b 1
)
if not exist tests\out mkdir tests\out
rem limpa artefatos obsoletos (evita falso-positivo com .out antigos)
del /q tests\out\* 2>nul
del /q tests\hello.exe 2>nul

echo === [0] integridade do corpus ===
findstr /c:"FONTE SAGRADA DO CORPUS" tests\hello.asm >nul 2>&1
if errorlevel 1 (
    echo FALHA: tests\hello.asm foi sobrescrito - restaure o arquivo.
    exit /b 1
)
echo   OK: corpus integro
echo === [0b] sistema de versao ===
if not exist version.bin ( echo "  FALHA: version.bin ausente" & set /a FAIL+=1 ) else ( echo "  OK: version.bin existe" & set /a PASS+=1 )
if not exist obj\version.inc ( echo "  FALHA: obj\version.inc ausente" & set /a FAIL+=1 ) else ( echo "  OK: obj\version.inc existe" & set /a PASS+=1 )

echo === [1] build golden hello.exe ===
if exist "C:\Nasm\nasm.exe" ( set NASM=C:\Nasm\nasm.exe ) else ( set NASM=nasm.exe )
"%NASM%" -f win64 -o tests\out\hello_g.obj tests\hello.asm
if errorlevel 1 ( echo "  FALHA: nasm hello" & set /a FAIL+=1 ) else ( echo "  OK: nasm hello" & set /a PASS+=1 )
set KLIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64\kernel32.lib
if exist tests\out\hello_g.obj (
    "C:\Nasm\link.exe" /nologo /subsystem:console /entry:main /out:tests\hello.exe tests\out\hello_g.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link hello" & set /a FAIL+=1 ) else ( echo "  OK: link hello" & set /a PASS+=1 )
)
if not exist tests\hello.exe (
    echo FATAL: tests\hello.exe nao foi construido; abortando testes dependentes.
    exit /b 1
)

echo === [2] CLI basica ===
"%DX%" -h >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -h" & set /a FAIL+=1 ) else ( echo "  OK: -h" & set /a PASS+=1 )
"%DX%" -ver > tests\out\ver.txt 2>&1
if errorlevel 1 ( echo "  FALHA: -ver" & set /a FAIL+=1 ) else ( echo "  OK: -ver" & set /a PASS+=1 )
findstr /c:"LabsObjects All rights reserved" tests\out\ver.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -ver sem copyright" & set /a FAIL+=1 ) else ( echo "  OK: -ver com copyright" & set /a PASS+=1 )
findstr /c:"Version 1.2." tests\out\ver.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -ver sem versao 1.2.x" & set /a FAIL+=1 ) else ( echo "  OK: -ver 1.2.x" & set /a PASS+=1 )
"%DX%" > tests\out\banner.txt 2>&1
if errorlevel 1 ( echo "  FALHA: sem args deveria retornar 0" & set /a FAIL+=1 ) else ( echo "  OK: sem args retorna 0" & set /a PASS+=1 )
findstr /c:"LabsObjects All rights reserved" tests\out\banner.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: banner sem copyright" & set /a FAIL+=1 ) else ( echo "  OK: banner com copyright" & set /a PASS+=1 )
findstr /c:"Uso:" tests\out\banner.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: banner sem opcoes" & set /a FAIL+=1 ) else ( echo "  OK: banner com opcoes" & set /a PASS+=1 )
"%DX%" --bogus -q >nul 2>&1
if not errorlevel 1 ( echo "  FALHA: --bogus deveria retornar 1" & set /a FAIL+=1 ) else ( echo "  OK: --bogus retorna 1" & set /a PASS+=1 )

echo === [3] negativos (PE invalido - 3 - ===
"%DX%" tests\var32.exe -o tests\out\neg.asm -q >nul 2>&1
if errorlevel 3 ( echo "  OK: var32 rejeitado (3)" & set /a PASS+=1 ) else ( echo "  FALHA: var32 deveria retornar 3" & set /a FAIL+=1 )
"%DX%" tests\for.exe -o tests\out\neg2.asm -q >nul 2>&1
if errorlevel 3 ( echo "  OK: for.exe (magic 0) rejeitado (3)" & set /a PASS+=1 ) else ( echo "  FALHA: for.exe deveria retornar 3" & set /a FAIL+=1 )
"%DX%" tests\link.exe -o tests\out\neg3.asm -q >nul 2>&1
if errorlevel 3 ( echo "  OK: link.exe (32-bit) rejeitado (3)" & set /a PASS+=1 ) else ( echo "  FALHA: link.exe deveria retornar 3" & set /a FAIL+=1 )

echo === [4] generate win64 (hello) ===
"%DX%" tests\hello.exe -o tests\out\hello.asm -q
if errorlevel 1 ( echo "  FALHA: generate hello" & set /a FAIL+=1 ) else ( echo "  OK: generate hello" & set /a PASS+=1 )
if not exist tests\out\hello.asm ( echo "  FALHA: hello.asm nao criado" & set /a FAIL+=1 ) else ( echo "  OK: hello.asm existe" & set /a PASS+=1 )

echo === [5] round-trip win64 (hello - rebuild - executa - ===
"%DX%" tests\hello.exe -o tests\out\hello.asm -r -O tests\out\hello_rt.exe -q
if errorlevel 1 ( echo "  FALHA: rebuild hello" & set /a FAIL+=1 ) else ( echo "  OK: rebuild hello" & set /a PASS+=1 )
if exist tests\out\hello_rt.exe (
    tests\out\hello_rt.exe > tests\out\hello_rt.out 2>&1
    findstr /c:"hi" tests\out\hello_rt.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: hello_rt nao imprime 'hi'" & set /a FAIL+=1 ) else ( echo "  OK: hello_rt imprime 'hi'" & set /a PASS+=1 )
) else (
    echo "  FALHA: hello_rt.exe nao criado" & set /a FAIL+=1
)

echo === [6] round-trip binario (var64 - byte-identico - executa - ===
"%DX%" tests\var64.exe -o tests\out\var64_bin.asm -m bin -r -O tests\out\var64_bin.exe -q
if errorlevel 1 ( echo "  FALHA: rebuild bin var64" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin var64" & set /a PASS+=1 )
if exist tests\out\var64_bin.exe (
    fc /b tests\var64.exe tests\out\var64_bin.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: var64_bin difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: var64_bin byte-identico" & set /a PASS+=1 )
    tests\out\var64_bin.exe > tests\out\var64_bin.out 2>&1
    tests\var64.exe > tests\out\var64_orig.out 2>&1
    fc tests\out\var64_orig.out tests\out\var64_bin.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: comportamento identico" & set /a PASS+=1 )
) else (
    echo "  FALHA: var64_bin.exe nao criado" & set /a FAIL+=1
)

echo === [6b] round-trip binario (gcc 15.2.0 - byte-identico - --version)
"%DX%" tests\gcc.exe -o tests\out\gcc_bin.asm -m bin -r -O tests\out\gcc_bin.exe -q
if errorlevel 1 ( echo "  FALHA: rebuild bin gcc" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin gcc" & set /a PASS+=1 )
if exist tests\out\gcc_bin.exe (
    fc /b tests\gcc.exe tests\out\gcc_bin.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: gcc_bin difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: gcc_bin byte-identico" & set /a PASS+=1 )
    mkdir %TEMP%\dexter_gcctest >nul 2>&1
    copy /y tests\out\gcc_bin.exe %TEMP%\dexter_gcctest\gcc.exe >nul 2>&1
    %TEMP%\dexter_gcctest\gcc.exe --version > tests\out\gcc_bin.out 2>&1
    tests\gcc.exe --version > tests\out\gcc_orig.out 2>&1
    fc tests\out\gcc_orig.out tests\out\gcc_bin.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: --version difere" & set /a FAIL+=1 ) else ( echo "  OK: --version identico" & set /a PASS+=1 )
) else (
    echo "  FALHA: gcc_bin.exe nao criado" & set /a FAIL+=1
)

echo === [6c] 32-bit extras (rejeicao limpa - exit 3)
for %%X in (Calculator Case Char color Color2 Contador) do (
    "%DX%" tests\%%X.exe -o tests\out\neg_%%X.asm -q >nul 2>&1
    if !errorlevel! EQU 3 ( echo "  OK: %%X rejeitado -3-" & set /a PASS+=1 ) else ( echo "  FALHA: %%X retornou !errorlevel!" & set /a FAIL+=1 )
)

echo === [6d] ld.lld 68MB (dump rapido; round-trip completo em run_slow.bat)
"%DX%" tests\ld.lld.exe -o tests\out\ldlld.asm -v > tests\out\ldlld_v.log 2>&1
if errorlevel 1 ( echo "  FALHA: dump ld.lld" & set /a FAIL+=1 ) else ( echo "  OK: dump ld.lld" & set /a PASS+=1 )
findstr /c:"Sections: 9" tests\out\ldlld_v.log >nul 2>&1
if errorlevel 1 ( echo "  FALHA: 9 secoes esperadas" & set /a FAIL+=1 ) else ( echo "  OK: 9 secoes" & set /a PASS+=1 )

echo === [7] flags (fumaca: exit 0 + .asm gerado) ===
"%DX%" tests\hello.exe -o tests\out\f_hex.asm -hex -q
if errorlevel 1 ( echo "  FALHA: -hex" & set /a FAIL+=1 ) else ( echo "  OK: -hex" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\f_np.asm -nop-pad -q
if errorlevel 1 ( echo "  FALHA: -nop-pad" & set /a FAIL+=1 ) else ( echo "  OK: -nop-pad" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\f_s.asm -s .data -q
if errorlevel 1 ( echo "  FALHA: -s" & set /a FAIL+=1 ) else ( echo "  OK: -s" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\f_se.asm -start 0x1000 -end 0x1010 -q
if errorlevel 1 ( echo "  FALHA: -start/-end" & set /a FAIL+=1 ) else ( echo "  OK: -start/-end" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\f_ss.asm -strings -q
if errorlevel 1 ( echo "  FALHA: -strings" & set /a FAIL+=1 ) else ( echo "  OK: -strings" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\f_norel.asm -no-relocs -q
if errorlevel 1 ( echo "  FALHA: -no-relocs" & set /a FAIL+=1 ) else ( echo "  OK: -no-relocs" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\f_noimp.asm -no-imports -q
if errorlevel 1 ( echo "  FALHA: -no-imports" & set /a FAIL+=1 ) else ( echo "  OK: -no-imports" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\f_vv.asm -vv -q
if errorlevel 1 ( echo "  FALHA: -vv" & set /a FAIL+=1 ) else ( echo "  OK: -vv" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\f_bin.asm -m bin -q
if errorlevel 1 ( echo "  FALHA: -m bin generate" & set /a FAIL+=1 ) else ( echo "  OK: -m bin generate" & set /a PASS+=1 )

echo === [8] lexer (tokens golden tests\hello.asm) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\lex_check.obj tests\lex_check.asm
if errorlevel 1 ( echo "  FALHA: nasm lex_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm lex_check" & set /a PASS+=1 )
if exist tests\out\lex_check.obj (
    "C:\Nasm\link.exe" /nologo /subsystem:console /entry:main /out:tests\out\lex_check.exe tests\out\lex_check.obj obj\lexer.obj obj\opcode_tbl.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link lex_check" & set /a FAIL+=1 ) else ( echo "  OK: link lex_check" & set /a PASS+=1 )
)
if exist tests\out\lex_check.exe (
    tests\out\lex_check.exe > tests\out\lex.out 2>&1
    if errorlevel 1 ( echo "  FALHA: lex_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: lex_check exit 0" & set /a PASS+=1 )
    findstr /c:"LEX total=164 eol=35 label=1 ident=48 reg=20 num=15 str=1 lbr=6 rbr=6 comma=16 plus=5 minus=2 colon=0 star=0 slash=0 comment=9 unknowns=0" tests\out\lex.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: golden lexer" & set /a FAIL+=1 ) else ( echo "  OK: golden lexer" & set /a PASS+=1 )
)

echo === [9] parser AST (golden tests\hello.asm + tests\loop.asm) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\ast_check.obj tests\ast_check.asm
if errorlevel 1 ( echo "  FALHA: nasm ast_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm ast_check" & set /a PASS+=1 )
if exist tests\out\ast_check.obj (
    "C:\Nasm\link.exe" /nologo /subsystem:console /entry:main /out:tests\out\ast_check.exe tests\out\ast_check.obj obj\parser.obj obj\ast.obj obj\lexer.obj obj\memory.obj obj\string.obj obj\console.obj obj\opcode_tbl.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link ast_check" & set /a FAIL+=1 ) else ( echo "  OK: link ast_check" & set /a PASS+=1 )
)
if exist tests\out\ast_check.exe (
    tests\out\ast_check.exe tests\hello.asm > tests\out\ast.out 2>&1
    if errorlevel 1 ( echo "  FALHA: ast_check hello exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: ast_check hello exit 0" & set /a PASS+=1 )
    findstr /c:"AST funcs=1 blocks=1 instrs=18 succs=3 db=1 equ=1 dir=8" tests\out\ast.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: golden AST hello" & set /a FAIL+=1 ) else ( echo "  OK: golden AST hello" & set /a PASS+=1 )
    tests\out\ast_check.exe tests\loop.asm > tests\out\ast_loop.out 2>&1
    if errorlevel 1 ( echo "  FALHA: ast_check loop exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: ast_check loop exit 0" & set /a PASS+=1 )
    findstr /c:"AST funcs=1 blocks=5 instrs=30 succs=9 db=2 equ=0 dir=8" tests\out\ast_loop.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: golden AST loop" & set /a FAIL+=1 ) else ( echo "  OK: golden AST loop" & set /a PASS+=1 )
)

echo === [10] -ast-dump (resumo AST do .asm gerado em stdout) ===
"%DX%" tests\hello.exe -o tests\out\adump.asm -ast-dump > tests\out\adump.out 2>&1
if errorlevel 1 ( echo "  FALHA: -ast-dump exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -ast-dump exit 0" & set /a PASS+=1 )
findstr /c:"AST funcs=" tests\out\adump.out >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem resumo AST em stdout" & set /a FAIL+=1 ) else ( echo "  OK: resumo AST em stdout" & set /a PASS+=1 )
if not exist tests\out\adump.asm ( echo "  FALHA: adump.asm nao criado" & set /a FAIL+=1 ) else ( echo "  OK: adump.asm existe" & set /a PASS+=1 )

echo === [11] lifter IR (golden craftado) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\lift_check.obj tests\lift_check.asm
if errorlevel 1 ( echo "  FALHA: nasm lift_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm lift_check" & set /a PASS+=1 )
if exist tests\out\lift_check.obj (
    "C:\Nasm\link.exe" /nologo /subsystem:console /entry:main /out:tests\out\lift_check.exe tests\out\lift_check.obj obj\lift.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link lift_check" & set /a FAIL+=1 ) else ( echo "  OK: link lift_check" & set /a PASS+=1 )
)
if exist tests\out\lift_check.exe (
    tests\out\lift_check.exe > tests\out\lift.out 2>&1
    if errorlevel 1 ( echo "  FALHA: lift_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: lift_check exit 0" & set /a PASS+=1 )
    findstr /c:"LIFT db=1 instr=3 call=3 callimp=1 jmp=1 jmpimp=1 branch=1 ret=1" tests\out\lift.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: golden LIFT" & set /a FAIL+=1 ) else ( echo "  OK: golden LIFT" & set /a PASS+=1 )
    findstr /c:"TKIND none=4 code=3 data=2 import=3" tests\out\lift.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: golden TKIND" & set /a FAIL+=1 ) else ( echo "  OK: golden TKIND" & set /a PASS+=1 )
)

echo === [12] codegen (golden textual + rollback) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\codegen_check.obj tests\codegen_check.asm
if errorlevel 1 ( echo "  FALHA: nasm codegen_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm codegen_check" & set /a PASS+=1 )
if exist tests\out\codegen_check.obj (
    "C:\Nasm\link.exe" /nologo /subsystem:console /entry:main /out:tests\out\codegen_check.exe tests\out\codegen_check.obj obj\codegen.obj obj\emit_nasm.obj obj\asm_buffer.obj obj\labels.obj obj\memory.obj obj\string.obj obj\opcode_tbl.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link codegen_check" & set /a FAIL+=1 ) else ( echo "  OK: link codegen_check" & set /a PASS+=1 )
)
if exist tests\out\codegen_check.exe (
    tests\out\codegen_check.exe > tests\out\codegen.out 2>&1
    if errorlevel 1 ( echo "  FALHA: codegen_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: codegen_check exit 0" & set /a PASS+=1 )
    findstr /c:"label_140001000:" tests\out\codegen.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem label no texto" & set /a FAIL+=1 ) else ( echo "  OK: label no texto" & set /a PASS+=1 )
    findstr /c:"mov rax, rbx" tests\out\codegen.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem mov no texto" & set /a FAIL+=1 ) else ( echo "  OK: mov no texto" & set /a PASS+=1 )
    findstr /c:"call [rel __imp_KERNEL32_dll_ExitProcess]" tests\out\codegen.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem call imp no texto" & set /a FAIL+=1 ) else ( echo "  OK: call imp no texto" & set /a PASS+=1 )
    findstr /c:"jmp [rel __imp_KERNEL32_dll_ExitProcess]" tests\out\codegen.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem jmp imp no texto" & set /a FAIL+=1 ) else ( echo "  OK: jmp imp no texto" & set /a PASS+=1 )
)

echo === [12b] R-labels nativos (refs RIP->dados viram label) ===
"%DX%" tests\hello.exe -o tests\out\nat_hello.asm -native -q
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native hello" & set /a FAIL+=1 ) else ( echo "  OK: generate -native hello" & set /a PASS+=1 )
findstr /c:"[rel label_" tests\out\nat_hello.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem ref RIP nativa" & set /a FAIL+=1 ) else ( echo "  OK: ref RIP nativa" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\nat_hello.asm -r -O tests\out\nat_hello.exe -native -q
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native hello" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native hello" & set /a PASS+=1 )
if exist tests\out\nat_hello.exe (
    tests\out\nat_hello.exe > tests\out\nat_hello.out 2>&1
    findstr /c:"hi" tests\out\nat_hello.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: nat_hello nao imprime hi" & set /a FAIL+=1 ) else ( echo "  OK: nat_hello imprime hi" & set /a PASS+=1 )
)
"%DX%" tests\loop.exe -o tests\out\nat_loop.asm -r -O tests\out\nat_loop.exe -native -q
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native loop" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native loop" & set /a PASS+=1 )
if exist tests\out\nat_loop.exe (
    tests\out\nat_loop.exe > tests\out\nat_loop.out 2>&1
    findstr /c:"55" tests\out\nat_loop.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: nat_loop nao imprime 55" & set /a FAIL+=1 ) else ( echo "  OK: nat_loop imprime 55" & set /a PASS+=1 )
)
"%DX%" tests\tiny.exe -o tests\out\nat_tiny.asm -r -O tests\out\nat_tiny.exe -native -q
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native tiny" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native tiny" & set /a PASS+=1 )
if exist tests\out\nat_tiny.exe (
    tests\out\nat_tiny.exe >nul 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: nat_tiny exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: nat_tiny exit!=42" & set /a FAIL+=1 )
)
"%DX%" tests\strings.exe -o tests\out\nat_strings.asm -r -O tests\out\nat_strings.exe -native -strings -q
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native -strings" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native -strings" & set /a PASS+=1 )
if exist tests\out\nat_strings.exe (
    tests\strings.exe > tests\out\nat_strings_orig.out 2>&1
    tests\out\nat_strings.exe > tests\out\nat_strings_rt.out 2>&1
    fc tests\out\nat_strings_orig.out tests\out\nat_strings_rt.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: comportamento identico" & set /a PASS+=1 )
)

echo === [13] rewrite IAT (call [rel __imp_X] nativo) ===
"%DX%" tests\hello.exe -o tests\out\iat_hello.asm -native -q
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native hello" & set /a FAIL+=1 ) else ( echo "  OK: generate -native hello" & set /a PASS+=1 )
findstr /c:"jmp [rel __imp_" tests\out\iat_hello.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem jmp __imp_ (thunks do hello)" & set /a FAIL+=1 ) else ( echo "  OK: jmp __imp_ presente" & set /a PASS+=1 )
findstr /c:"__imp_KERNEL32_dll_ExitProcess:" tests\out\iat_hello.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem label __imp_" & set /a FAIL+=1 ) else ( echo "  OK: label __imp_ definido" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\iat_hello.asm -r -O tests\out\iat_hello.exe -native -q
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild IAT hello" & set /a FAIL+=1 ) else ( echo "  OK: rebuild IAT hello" & set /a PASS+=1 )
if exist tests\out\iat_hello.exe (
    tests\out\iat_hello.exe > tests\out\iat_hello.out 2>&1
    findstr /c:"hi" tests\out\iat_hello.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: iat_hello nao imprime hi" & set /a FAIL+=1 ) else ( echo "  OK: iat_hello imprime hi" & set /a PASS+=1 )
)
"%DX%" tests\var64.exe -o tests\out\iat_var64.asm -native -q
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native var64" & set /a FAIL+=1 ) else ( echo "  OK: generate -native var64" & set /a PASS+=1 )
findstr /c:"call [rel __imp_KERNEL32_dll_LoadLibraryA]" tests\out\iat_var64.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem call __imp_ em var64" & set /a FAIL+=1 ) else ( echo "  OK: call __imp_ em var64" & set /a PASS+=1 )
findstr /c:"__imp_KERNEL32_dll_LoadLibraryA" tests\out\iat_var64.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem __imp_ em var64 (14 imports)" & set /a FAIL+=1 ) else ( echo "  OK: __imp_ em var64" & set /a PASS+=1 )
"%DX%" tests\no_relocs.exe -o tests\out\iat_norelocs.asm -r -O tests\out\iat_norelocs.exe -native -q
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild IAT no_relocs" & set /a FAIL+=1 ) else ( echo "  OK: rebuild IAT no_relocs" & set /a PASS+=1 )
if exist tests\out\iat_norelocs.exe (
    tests\out\iat_norelocs.exe > tests\out\iat_norelocs_rt.out 2>&1
    tests\no_relocs.exe > tests\out\iat_norelocs_orig.out 2>&1
    fc tests\out\iat_norelocs_orig.out tests\out\iat_norelocs_rt.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: comportamento identico" & set /a PASS+=1 )
)

echo === [14] imp label-at-slot (driver imp_check: HIT+MISS) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\imp_check.obj tests\imp_check.asm
if errorlevel 1 ( echo "  FALHA: nasm imp_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm imp_check" & set /a PASS+=1 )
if exist tests\out\imp_check.obj (
    "C:\Nasm\link.exe" /nologo /subsystem:console /entry:main /out:tests\out\imp_check.exe tests\out\imp_check.obj obj\rebuild.obj obj\asm_buffer.obj obj\memory.obj obj\string.obj obj\hash.obj obj\emit_nasm.obj obj\opcode_tbl.obj obj\decoder.obj obj\prefixes.obj obj\modrm.obj obj\operands.obj obj\semantics.obj obj\symbols.obj obj\labels.obj obj\strings.obj obj\file_read.obj obj\file_write.obj obj\mmap.obj obj\console.obj obj\pe_load.obj obj\pe_sections.obj obj\pe_imports.obj obj\pe_exports.obj obj\pe_relocs.obj obj\rva.obj obj\lexer.obj obj\parser.obj obj\ast.obj obj\lift.obj obj\codegen.obj obj\log.obj obj\parse_args.obj obj\help.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link imp_check" & set /a FAIL+=1 ) else ( echo "  OK: link imp_check" & set /a PASS+=1 )
)
if exist tests\out\imp_check.exe (
    tests\out\imp_check.exe > tests\out\imp.out 2>&1
    if errorlevel 1 ( echo "  FALHA: imp_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: imp_check exit 0" & set /a PASS+=1 )
    findstr /c:"__imp_KERNEL32_dll_ExitProcess:" tests\out\imp.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem label HIT" & set /a FAIL+=1 ) else ( echo "  OK: label HIT" & set /a PASS+=1 )
)

echo === [15] symtab (driver sym_check: golden ordenado) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\sym_check.obj tests\sym_check.asm
if errorlevel 1 ( echo "  FALHA: nasm sym_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm sym_check" & set /a PASS+=1 )
if exist tests\out\sym_check.obj (
    "C:\Nasm\link.exe" /nologo /subsystem:console /entry:main /out:tests\out\sym_check.exe tests\out\sym_check.obj obj\symbols.obj obj\memory.obj obj\string.obj obj\hash.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link sym_check" & set /a FAIL+=1 ) else ( echo "  OK: link sym_check" & set /a PASS+=1 )
)
if exist tests\out\sym_check.exe (
    tests\out\sym_check.exe > tests\out\sym.out 2>&1
    if errorlevel 1 ( echo "  FALHA: sym_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: sym_check exit 0" & set /a PASS+=1 )
    findstr /c:"SYM n=5 v=1000 1500 2000 2A00 3100" tests\out\sym.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: golden SYM" & set /a FAIL+=1 ) else ( echo "  OK: golden SYM" & set /a PASS+=1 )
)

echo === [16] -overview (texto + -json, inspect-only) ===
"%DX%" tests\hello.exe -overview > tests\out\ov.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -overview exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -overview exit 0" & set /a PASS+=1 )
findstr /c:"ImageBase:" tests\out\ov.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem ImageBase" & set /a FAIL+=1 ) else ( echo "  OK: ImageBase" & set /a PASS+=1 )
findstr /c:"KERNEL32" tests\out\ov.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem imports no texto" & set /a FAIL+=1 ) else ( echo "  OK: imports no texto" & set /a PASS+=1 )
"%DX%" tests\hello.exe -overview -json > tests\out\ovj.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -overview -json exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -overview -json exit 0" & set /a PASS+=1 )
findstr /c:"\"image_base\":\"0x140000000\"" tests\out\ovj.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem image_base no json" & set /a FAIL+=1 ) else ( echo "  OK: image_base no json" & set /a PASS+=1 )
findstr /c:"\"func\":\"ExitProcess\"" tests\out\ovj.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem func no json" & set /a FAIL+=1 ) else ( echo "  OK: func no json" & set /a PASS+=1 )
"%DX%" tests\hello.exe -overview -q > tests\out\ovq.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -overview -q exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -overview -q exit 0" & set /a PASS+=1 )
findstr /c:"ImageBase:" tests\out\ovq.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -q suprimiu overview" & set /a FAIL+=1 ) else ( echo "  OK: -q nao suprime" & set /a PASS+=1 )
"%DX%" tests\hello.exe -overview -o tests\out\should_not_exist.asm -q >nul 2>&1
if exist tests\out\should_not_exist.asm ( echo "  FALHA: overview escreveu .asm" & set /a FAIL+=1 ) else ( echo "  OK: inspect-only" & set /a PASS+=1 )
"%DX%" tests\var64.exe -overview -json -q > tests\out\ovv.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: overview var64 exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: overview var64 exit 0" & set /a PASS+=1 )
findstr /c:"\"imports_count\":14" tests\out\ovv.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: imports_count!=14" & set /a FAIL+=1 ) else ( echo "  OK: imports_count=14" & set /a PASS+=1 )

echo.
echo =====================================================
echo Passaram: %PASS%   Falharam: %FAIL%
echo =====================================================
if %FAIL% neq 0 exit /b 1
exit /b 0

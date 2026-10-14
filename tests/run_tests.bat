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
set X86LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x86\kernel32.lib
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

echo === [3] negativos (PE invalido - 3 - + x32 valido - 0 - ===
"%DX%" tests\var32.exe -o tests\out\neg.asm -q >nul 2>&1
if !errorlevel! EQU 0 ( echo "  OK: var32 x32 aceito (0)" & set /a PASS+=1 ) else ( echo "  FALHA: var32 deveria retornar 0" & set /a FAIL+=1 )
powershell -NoProfile -Command "$b=[IO.File]::ReadAllBytes('tests\hello.exe'); $b[0]=0x00; $b[1]=0x00; [IO.File]::WriteAllBytes('tests\out\corrupt_mz.exe', $b)"
"%DX%" tests\out\corrupt_mz.exe -o tests\out\neg2.asm -q >nul 2>&1
if errorlevel 3 ( echo "  OK: magic 0 rejeitado (3)" & set /a PASS+=1 ) else ( echo "  FALHA: magic 0 deveria retornar 3" & set /a FAIL+=1 )
"%DX%" tests\link.exe -o tests\out\neg3.asm -q >nul 2>&1
if !errorlevel! EQU 0 ( echo "  OK: link.exe x32 aceito (0)" & set /a PASS+=1 ) else ( echo "  FALHA: link.exe deveria retornar 0" & set /a FAIL+=1 )

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

echo === [6c] 32-bit extras (x32 validos: generate 0 + bits 32)
for %%X in (Calculator Case Char color Color2 Contador) do (
    "%DX%" tests\%%X.exe -o tests\out\x32_%%X.asm -q >nul 2>&1
    if !errorlevel! EQU 0 ( echo "  OK: %%X x32 aceito (0)" & set /a PASS+=1 ) else ( echo "  FALHA: %%X retornou !errorlevel!" & set /a FAIL+=1 )
)
findstr /c:"bits 32" tests\out\x32_Calculator.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: x32 sem bits 32" & set /a FAIL+=1 ) else ( echo "  OK: x32 com bits 32" & set /a PASS+=1 )

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

echo === [17] -func/-xrefs/-trace (navegacao, inspect-only) ===
"%DX%" tests\hello.exe -func 0x140001000 > tests\out\fn.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -func exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -func exit 0" & set /a PASS+=1 )
findstr /c:"Function 0x140001000" tests\out\fn.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem Function" & set /a FAIL+=1 ) else ( echo "  OK: Function" & set /a PASS+=1 )
findstr /c:"calls" tests\out\fn.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem calls" & set /a FAIL+=1 ) else ( echo "  OK: calls" & set /a PASS+=1 )
"%DX%" tests\hello.exe -func 0x140001000 -json -q > tests\out\fnj.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -func -json exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -func -json exit 0" & set /a PASS+=1 )
findstr /c:"\"entry\":\"0x140001000\"" tests\out\fnj.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem entry no json" & set /a FAIL+=1 ) else ( echo "  OK: entry no json" & set /a PASS+=1 )
"%DX%" tests\hello.exe -func 0x1 -q > tests\out\fnnf.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -func invalido exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -func invalido exit 0" & set /a PASS+=1 )
findstr /c:"not found" tests\out\fnnf.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem not-found" & set /a FAIL+=1 ) else ( echo "  OK: not-found honesto" & set /a PASS+=1 )
"%DX%" tests\hello.exe -xrefs 0x140002010 > tests\out\xr.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -xrefs exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -xrefs exit 0" & set /a PASS+=1 )
findstr /c:"jmp" tests\out\xr.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem ref jmp" & set /a FAIL+=1 ) else ( echo "  OK: ref jmp" & set /a PASS+=1 )
"%DX%" tests\hello.exe -xrefs 0x140002010 -json -q > tests\out\xrj.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -xrefs -json exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -xrefs -json exit 0" & set /a PASS+=1 )
findstr /c:"\"kind\":\"jmp\"" tests\out\xrj.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem kind jmp" & set /a FAIL+=1 ) else ( echo "  OK: kind jmp" & set /a PASS+=1 )
"%DX%" tests\hello.exe -xrefs 0x1 -json -q > tests\out\xre.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -xrefs vazio exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -xrefs vazio exit 0" & set /a PASS+=1 )
findstr /c:"\"total\":0" tests\out\xre.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: total!=0" & set /a FAIL+=1 ) else ( echo "  OK: total 0" & set /a PASS+=1 )
"%DX%" tests\hello.exe -trace 0x140001000 > tests\out\tr.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -trace exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -trace exit 0" & set /a PASS+=1 )
findstr /c:"--call-->" tests\out\tr.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem aresta call" & set /a FAIL+=1 ) else ( echo "  OK: aresta call" & set /a PASS+=1 )
"%DX%" tests\hello.exe -trace 0x140001000 -json -q > tests\out\trj.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -trace -json exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -trace -json exit 0" & set /a PASS+=1 )
findstr /c:"\"chain\"" tests\out\trj.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem chain no json" & set /a FAIL+=1 ) else ( echo "  OK: chain no json" & set /a PASS+=1 )
"%DX%" tests\hello.exe -func 0x140001000 -o tests\out\should_not2.asm -q >nul 2>&1
if exist tests\out\should_not2.asm ( echo "  FALHA: query escreveu .asm" & set /a FAIL+=1 ) else ( echo "  OK: query inspect-only" & set /a PASS+=1 )

echo === [18] -rsrc (inventario de recursos PE) ===
"%DX%" tests\gcc.exe -rsrc -q > tests\out\rsrc.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -rsrc gcc exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -rsrc gcc exit 0" & set /a PASS+=1 )
findstr /c:"/24/1/1033" tests\out\rsrc.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem manifest 24/1/1033" & set /a FAIL+=1 ) else ( echo "  OK: manifest 24/1/1033" & set /a PASS+=1 )
findstr /c:"size=0x147" tests\out\rsrc.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem size 147" & set /a FAIL+=1 ) else ( echo "  OK: size 147" & set /a PASS+=1 )
"%DX%" tests\gcc.exe -rsrc -json -q > tests\out\rsrcj.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -rsrc -json exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -rsrc -json exit 0" & set /a PASS+=1 )
findstr /c:"\"type\":24" tests\out\rsrcj.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem type 24" & set /a FAIL+=1 ) else ( echo "  OK: type 24" & set /a PASS+=1 )
findstr /c:"\"size\":\"0x147\"" tests\out\rsrcj.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem size no json" & set /a FAIL+=1 ) else ( echo "  OK: size no json" & set /a PASS+=1 )
"%DX%" tests\hello.exe -rsrc -q > tests\out\rsrce.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -rsrc vazio exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -rsrc vazio exit 0" & set /a PASS+=1 )
findstr /c:"Resources: 0" tests\out\rsrce.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem inventario vazio" & set /a FAIL+=1 ) else ( echo "  OK: inventario vazio" & set /a PASS+=1 )
"%DX%" tests\hello.exe -rsrc -json -q > tests\out\rsrcej.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -rsrc -json vazio exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -rsrc -json vazio exit 0" & set /a PASS+=1 )
findstr /c:"\"count\":0" tests\out\rsrcej.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: count!=0" & set /a FAIL+=1 ) else ( echo "  OK: count 0" & set /a PASS+=1 )
"%DX%" tests\ld.lld.exe -rsrc -q > tests\out\rsrcld.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -rsrc ld.lld exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -rsrc ld.lld exit 0" & set /a PASS+=1 )
findstr /c:"/16/1/1033" tests\out\rsrcld.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem version 16/1/1033" & set /a FAIL+=1 ) else ( echo "  OK: version 16/1/1033" & set /a PASS+=1 )
powershell -NoProfile -Command "$b=[IO.File]::ReadAllBytes('tests\gcc.exe'); [IO.File]::WriteAllBytes('tests\out\corrupt_rsrc.exe', $b); $b[0x1F184C]=0x00; $b[0x1F184D]=0xFF; $b[0x1F184E]=0xFF; $b[0x1F184F]=0xFF; [IO.File]::WriteAllBytes('tests\out\corrupt_rsrc.exe', $b)"
"%DX%" tests\out\corrupt_rsrc.exe -rsrc -q > tests\out\corrupt.out 2>&1
if !errorlevel! EQU 3 ( echo "  OK: size gigante rejeitado (3)" & set /a PASS+=1 ) else ( echo "  FALHA: deveria retornar 3" & set /a FAIL+=1 )
findstr /c:"resource" tests\out\corrupt.out >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem motivo resource" & set /a FAIL+=1 ) else ( echo "  OK: motivo resource" & set /a PASS+=1 )
powershell -NoProfile -Command "$b=[IO.File]::ReadAllBytes('tests\gcc.exe'); $b[0x1F180E]=99; [IO.File]::WriteAllBytes('tests\out\corrupt_rsrc2.exe', $b)"
"%DX%" tests\out\corrupt_rsrc2.exe -rsrc -q > tests\out\corrupt2.out 2>&1
if !errorlevel! EQU 3 ( echo "  OK: count inflado rejeitado (3)" & set /a PASS+=1 ) else ( echo "  FALHA: deveria retornar 3" & set /a FAIL+=1 )
"%DX%" tests\gcc.exe -rsrc -o tests\out\should_not3.asm -q >nul 2>&1
if exist tests\out\should_not3.asm ( echo "  FALHA: rsrc escreveu .asm" & set /a FAIL+=1 ) else ( echo "  OK: rsrc inspect-only" & set /a PASS+=1 )

echo === [19] -snapshot/-compare (fingerprint FNV-1a + diff) ===
"%DX%" tests\hello.exe -snapshot tests\out\snap.json -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -snapshot exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -snapshot exit 0" & set /a PASS+=1 )
if not exist tests\out\snap.json ( echo "  FALHA: snap.json nao criado" & set /a FAIL+=1 ) else ( echo "  OK: snap.json existe" & set /a PASS+=1 )
findstr /c:"\"fnv1a\":\"0x" tests\out\snap.json >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem fnv1a" & set /a FAIL+=1 ) else ( echo "  OK: fnv1a" & set /a PASS+=1 )
findstr /c:"\"size\":" tests\out\snap.json >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem size" & set /a FAIL+=1 ) else ( echo "  OK: size" & set /a PASS+=1 )
"%DX%" tests\hello.exe -compare tests\hello.exe > tests\out\cmp_self.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -compare self exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -compare self exit 0" & set /a PASS+=1 )
findstr /c:"identical" tests\out\cmp_self.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: self nao identical" & set /a FAIL+=1 ) else ( echo "  OK: self identical" & set /a PASS+=1 )
"%DX%" tests\hello.exe -compare tests\var64.exe -q > tests\out\cmp_diff.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -compare diff exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -compare diff exit 0" & set /a PASS+=1 )
findstr /c:"different" tests\out\cmp_diff.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem different" & set /a FAIL+=1 ) else ( echo "  OK: different" & set /a PASS+=1 )
"%DX%" tests\hello.exe -compare tests\hello.exe -json -q > tests\out\cmpj_self.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -compare -json exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -compare -json exit 0" & set /a PASS+=1 )
findstr /c:"\"identical\":true" tests\out\cmpj_self.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: identical!=true" & set /a FAIL+=1 ) else ( echo "  OK: identical true" & set /a PASS+=1 )
"%DX%" tests\hello.exe -compare tests\var64.exe -json -q > tests\out\cmpj_diff.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -compare diff -json exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -compare diff -json exit 0" & set /a PASS+=1 )
findstr /c:"\"identical\":false" tests\out\cmpj_diff.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: identical!=false" & set /a FAIL+=1 ) else ( echo "  OK: identical false" & set /a PASS+=1 )
"%DX%" tests\hello.exe -compare tests\missing.exe -q >nul 2>&1
if !errorlevel! EQU 2 ( echo "  OK: segundo ausente (2)" & set /a PASS+=1 ) else ( echo "  FALHA: deveria retornar 2" & set /a FAIL+=1 )
"%DX%" tests\hello.exe -compare tests\out\corrupt_mz.exe -q >nul 2>&1
if !errorlevel! EQU 3 ( echo "  OK: segundo invalido (3)" & set /a PASS+=1 ) else ( echo "  FALHA: deveria retornar 3" & set /a FAIL+=1 )
"%DX%" tests\hello.exe -snapshot tests\out\snap2.json -o tests\out\should_not5.asm -q >nul 2>&1
if exist tests\out\should_not5.asm ( echo "  FALHA: query escreveu .asm" & set /a FAIL+=1 ) else ( echo "  OK: inspect-only" & set /a PASS+=1 )

echo === [20] --doctor (toolchain + versao, inspect-only) ===
"%DX%" tests\hello.exe --doctor > tests\out\doctor.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: --doctor exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: --doctor exit 0" & set /a PASS+=1 )
findstr /c:"Doctor:" tests\out\doctor.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem Doctor:" & set /a FAIL+=1 ) else ( echo "  OK: Doctor:" & set /a PASS+=1 )
findstr /c:"nasm:" tests\out\doctor.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem nasm:" & set /a FAIL+=1 ) else ( echo "  OK: nasm:" & set /a PASS+=1 )
findstr /c:"link:" tests\out\doctor.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem link:" & set /a FAIL+=1 ) else ( echo "  OK: link:" & set /a PASS+=1 )
findstr /c:"kernel32: ok" tests\out\doctor.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem kernel32" & set /a FAIL+=1 ) else ( echo "  OK: kernel32: ok" & set /a PASS+=1 )
"%DX%" tests\hello.exe -doctor -q > tests\out\doctorq.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -doctor -q exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -doctor -q exit 0" & set /a PASS+=1 )
findstr /c:"Doctor:" tests\out\doctorq.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -q suprimiu doctor" & set /a FAIL+=1 ) else ( echo "  OK: -q nao suprime" & set /a PASS+=1 )
"%DX%" tests\hello.exe --doctor -o tests\out\should_not6.asm -q >nul 2>&1
if exist tests\out\should_not6.asm ( echo "  FALHA: doctor escreveu .asm" & set /a FAIL+=1 ) else ( echo "  OK: inspect-only" & set /a PASS+=1 )

echo === [21] -strings refs (dq pointer p/ R em -native) ===
"%DX%" tests\strings.exe -o tests\out\strptr.asm -native -strings -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate strptr exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: generate strptr exit 0" & set /a PASS+=1 )
findstr /c:"dq label_" tests\out\strptr.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem dq label_" & set /a FAIL+=1 ) else ( echo "  OK: dq label_" & set /a PASS+=1 )
"%DX%" tests\strings.exe -o tests\out\strptr.asm -r -O tests\out\strptr_rt.exe -native -strings -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild strptr exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: rebuild strptr exit 0" & set /a PASS+=1 )
tests\out\strptr_rt.exe > tests\out\strptr_new.txt 2>&1
tests\strings.exe > tests\out\strptr_orig.txt 2>&1
fc /b tests\out\strptr_orig.txt tests\out\strptr_new.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: comportamento identico" & set /a PASS+=1 )
"%DX%" tests\strings.exe -o tests\out\strptr_db.asm -strings -q >nul 2>&1
findstr /c:"dq label_" tests\out\strptr_db.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: default sem dq (db fiel)" & set /a PASS+=1 ) else ( echo "  FALHA: default com dq label_" & set /a FAIL+=1 )

echo === [22] fuzz PE (nunca crash/hang, so 0-3/5) ===
python tests\fuzz_pe.py --cases 20 --seed 7 > tests\out\fuzz22.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: fuzz exit!=0 (ver tests\out\fuzz22.txt)" & set /a FAIL+=1 ) else ( echo "  OK: fuzz exit 0" & set /a PASS+=1 )
findstr /c:"crashes=0" tests\out\fuzz22.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem crashes=0" & set /a FAIL+=1 ) else ( echo "  OK: crashes=0" & set /a PASS+=1 )

echo === [23] -emit db-native (R-6.5 resto) ===
"%DX%" tests\hello.exe -o tests\out\emit_nat.asm -emit native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -emit native exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -emit native exit 0" & set /a PASS+=1 )
findstr /c:"jmp [rel __imp_" tests\out\emit_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -emit native sem jmp __imp_" & set /a FAIL+=1 ) else ( echo "  OK: -emit native nativo" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\emit_db.asm -emit db -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -emit db exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: -emit db exit 0" & set /a PASS+=1 )
findstr /c:"__imp_" tests\out\emit_db.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: -emit db sem __imp_ (db fiel)" & set /a PASS+=1 ) else ( echo "  FALHA: -emit db com __imp_" & set /a FAIL+=1 )
"%DX%" tests\hello.exe -o NUL -emit bogus -q >nul 2>&1
if !errorlevel! EQU 1 ( echo "  OK: -emit bogus retorna 1" & set /a PASS+=1 ) else ( echo "  FALHA: deveria retornar 1" & set /a FAIL+=1 )
"%DX%" tests\hello.exe -o NUL -emit -q >nul 2>&1
if !errorlevel! EQU 1 ( echo "  OK: -emit sem valor retorna 1" & set /a PASS+=1 ) else ( echo "  FALHA: deveria retornar 1" & set /a FAIL+=1 )
"%DX%" tests\hello.exe -o tests\out\emit_lw1.asm -native -emit db -q >nul 2>&1
findstr /c:"__imp_" tests\out\emit_lw1.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: last-wins (-emit db vence)" & set /a PASS+=1 ) else ( echo "  FALHA: last-wins quebrado" & set /a FAIL+=1 )
"%DX%" tests\hello.exe -o tests\out\emit_lw2.asm -emit db -native -q >nul 2>&1
findstr /c:"jmp [rel __imp_" tests\out\emit_lw2.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: last-wins quebrado" & set /a FAIL+=1 ) else ( echo "  OK: last-wins (-native vence)" & set /a PASS+=1 )

echo === [24] goldens com-sem flag (modo saida nao altera .asm) ===
"%DX%" tests\hello.exe -o tests\out\flag_base.asm >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: baseline exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: baseline exit 0" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\flag_q.asm -q >nul 2>&1
fc /b tests\out\flag_base.asm tests\out\flag_q.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -q altera .asm" & set /a FAIL+=1 ) else ( echo "  OK: -q byte-identico" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\flag_v.asm -v >tests\out\flag_v.txt 2>&1
fc /b tests\out\flag_base.asm tests\out\flag_v.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -v altera .asm" & set /a FAIL+=1 ) else ( echo "  OK: -v byte-identico" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\flag_vv.asm -vv >tests\out\flag_vv.txt 2>&1
fc /b tests\out\flag_base.asm tests\out\flag_vv.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -vv altera .asm" & set /a FAIL+=1 ) else ( echo "  OK: -vv byte-identico" & set /a PASS+=1 )

echo === [25] -start+-end combinados (D-6, walker honra ambos) ===
"%DX%" tests\hello.exe -o tests\out\rng_combo.asm -start 0x1000 -end 0x1010 -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: combo exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: combo exit 0" & set /a PASS+=1 )
fc /b tests\out\flag_base.asm tests\out\rng_combo.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: combo difere do full (range honrado)" & set /a PASS+=1 ) else ( echo "  FALHA: combo igual ao full (-end ignorado)" & set /a FAIL+=1 )
"%DX%" tests\hello.exe -o tests\out\rng_combo.asm -r -O tests\out\rng_rt.exe -start 0x1000 -end 0x1010 -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild combo exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: rebuild combo exit 0" & set /a PASS+=1 )
tests\out\rng_rt.exe > tests\out\rng_new.txt 2>&1
tests\hello.exe > tests\out\rng_orig.txt 2>&1
fc /b tests\out\rng_orig.txt tests\out\rng_new.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: comportamento identico" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\rng_scombo.asm -s .text -start 0x1000 -end 0x1010 -q >nul 2>&1
fc /b tests\out\rng_combo.asm tests\out\rng_scombo.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -s muda o range" & set /a FAIL+=1 ) else ( echo "  OK: -s consistente" & set /a PASS+=1 )

echo === [26] -no-imports x -native (D-5: fallback db seguro) ===
"%DX%" tests\hello.exe -o tests\out\ni_nat.asm -no-imports -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: combo exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: combo exit 0" & set /a PASS+=1 )
findstr /c:"__imp_" tests\out\ni_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: sem __imp_ (fallback db)" & set /a PASS+=1 ) else ( echo "  FALHA: __imp_ sem imports" & set /a FAIL+=1 )
"%DX%" tests\hello.exe -o tests\out\ni_nat.asm -r -O tests\out\ni_rt.exe -no-imports -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: rebuild exit 0" & set /a PASS+=1 )
tests\out\ni_rt.exe > tests\out\ni_new.txt 2>&1
tests\hello.exe > tests\out\ni_orig.txt 2>&1
fc /b tests\out\ni_orig.txt tests\out\ni_new.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: comportamento identico" & set /a PASS+=1 )

echo === [27] jump table absoluta (jtable switch + jmp rax) ===
"%NASM%" -f win64 -o tests\out\jtable.obj tests\jtable.asm
if errorlevel 1 ( echo "  FALHA: nasm jtable" & set /a FAIL+=1 ) else ( echo "  OK: nasm jtable" & set /a PASS+=1 )
if exist tests\out\jtable.obj (
    "C:\Nasm\link.exe" /nologo /subsystem:console /entry:main /out:tests\jtable.exe tests\out\jtable.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link jtable" & set /a FAIL+=1 ) else ( echo "  OK: link jtable" & set /a PASS+=1 )
)
tests\jtable.exe > tests\out\jt_orig.txt 2>&1
findstr /c:"2" tests\out\jt_orig.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: jtable nao imprime 2" & set /a FAIL+=1 ) else ( echo "  OK: jtable imprime 2" & set /a PASS+=1 )
"%DX%" tests\jtable.exe -o tests\out\jt.asm -r -O tests\out\jt_rt.exe -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native jtable" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native jtable" & set /a PASS+=1 )
if exist tests\out\jt_rt.exe (
    tests\out\jt_rt.exe > tests\out\jt_new.txt 2>&1
    fc /b tests\out\jt_orig.txt tests\out\jt_new.txt >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: comportamento identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem jt_rt.exe" & set /a FAIL+=1 )
findstr /c:"lea rax, [rel label_" tests\out\jt.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: base da tabela sem label" & set /a FAIL+=1 ) else ( echo "  OK: base da tabela rotulada" & set /a PASS+=1 )
"%DX%" tests\jtable.exe -o tests\out\jt_db.asm -r -O tests\out\jt_dbrt.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild db jtable" & set /a FAIL+=1 ) else ( echo "  OK: rebuild db jtable" & set /a PASS+=1 )
if exist tests\out\jt_dbrt.exe (
    tests\out\jt_dbrt.exe > tests\out\jt_dbnew.txt 2>&1
    fc /b tests\out\jt_orig.txt tests\out\jt_dbnew.txt >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: db comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: db comportamento identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem jt_dbrt.exe" & set /a FAIL+=1 )

echo === [28] D bitmap: entradas da jump-table p/ codigo viram dq label_ ===
"%DX%" tests\jtable.exe -o tests\out\jt_d.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native jtable" & set /a FAIL+=1 ) else ( echo "  OK: generate -native jtable" & set /a PASS+=1 )
findstr /c:"dq label_" tests\out\jt_d.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: entradas da tabela sem dq label_" & set /a FAIL+=1 ) else ( echo "  OK: entradas da tabela com dq label_" & set /a PASS+=1 )
"%DX%" tests\jtable.exe -o tests\out\jt_d.asm -r -O tests\out\jt_drt.exe -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native jtable dq" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native jtable dq" & set /a PASS+=1 )
if exist tests\out\jt_drt.exe (
    tests\out\jt_drt.exe > tests\out\jt_dnew.txt 2>&1
    fc /b tests\out\jt_orig.txt tests\out\jt_dnew.txt >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: dq comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: dq comportamento identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem jt_drt.exe" & set /a FAIL+=1 )
"%DX%" tests\jtable.exe -o tests\out\jt_dfilter.asm -s .rdata -native -q >nul 2>&1
findstr /c:"dq label_" tests\out\jt_dfilter.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: com -s .rdata sem dq (codigo fora do range)" & set /a PASS+=1 ) else ( echo "  FALHA: dq com codigo nao emitido" & set /a FAIL+=1 )

echo === [29] native montavel em PE real (var64: disp sempre com 0x) ===
"%DX%" tests\var64.exe -o tests\out\v64nat.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native var64" & set /a FAIL+=1 ) else ( echo "  OK: generate -native var64" & set /a PASS+=1 )
findstr /c:"mov " tests\out\v64nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem mnemonicos nativos" & set /a FAIL+=1 ) else ( echo "  OK: mnemonicos nativos" & set /a PASS+=1 )
"%NASM%" -f win64 -o tests\out\v64nat.obj tests\out\v64nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm var64 -native" & set /a FAIL+=1 ) else ( echo "  OK: nasm var64 -native" & set /a PASS+=1 )

echo === [30] x32: detectar + desmontar (db fiel, sem -native) ===
"%DX%" tests\var32.exe -overview -q > tests\out\ov32.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -overview x32" & set /a FAIL+=1 ) else ( echo "  OK: -overview x32" & set /a PASS+=1 )
findstr /c:"ImageBase: 0x400000" tests\out\ov32.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: base x32" & set /a FAIL+=1 ) else ( echo "  OK: base x32" & set /a PASS+=1 )
"%DX%" tests\Calculator.exe -o tests\out\calc32.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate x32" & set /a FAIL+=1 ) else ( echo "  OK: generate x32" & set /a PASS+=1 )
findstr /c:"bits 32" tests\out\calc32.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem bits 32" & set /a FAIL+=1 ) else ( echo "  OK: bits 32" & set /a PASS+=1 )
findstr /c:"default rel" tests\out\calc32.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: sem default rel (x32)" & set /a PASS+=1 ) else ( echo "  FALHA: default rel em x32" & set /a FAIL+=1 )
"%DX%" tests\Calculator.exe -o tests\out\calc32n.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -native x32" & set /a FAIL+=1 ) else ( echo "  OK: -native x32 aceito (D1)" & set /a PASS+=1 )
findstr /c:"bits 32" tests\out\calc32n.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -native sem bits 32" & set /a FAIL+=1 ) else ( echo "  OK: -native com bits 32" & set /a PASS+=1 )
"%NASM%" -f win32 -o tests\out\calc32n.obj tests\out\calc32n.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm -native x32" & set /a FAIL+=1 ) else ( echo "  OK: nasm -native x32" & set /a PASS+=1 )

echo === [31] rebuild x32 (tiny32 exit 42, Fase C) ===
"%NASM%" -f win32 -o tests\out\tiny32.obj tests\tiny32.asm
if errorlevel 1 ( echo "  FALHA: nasm tiny32" & set /a FAIL+=1 ) else ( echo "  OK: nasm tiny32" & set /a PASS+=1 )
if exist tests\out\tiny32.obj (
    "C:\Nasm\link.exe" /nologo /nodefaultlib /subsystem:console /entry:start /out:tests\tiny32.exe tests\out\tiny32.obj "%X86LIB%"
    if errorlevel 1 ( echo "  FALHA: link tiny32" & set /a FAIL+=1 ) else ( echo "  OK: link tiny32" & set /a PASS+=1 )
)
tests\tiny32.exe >nul 2>&1
if !errorlevel! EQU 42 ( echo "  OK: tiny32 exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: tiny32 exit!=42" & set /a FAIL+=1 )
"%DX%" tests\tiny32.exe -o tests\out\t32.asm -r -O tests\out\t32rt.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild x32 tiny32" & set /a FAIL+=1 ) else ( echo "  OK: rebuild x32 tiny32" & set /a PASS+=1 )
if exist tests\out\t32rt.exe (
    tests\out\t32rt.exe >nul 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: rt exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: rt exit!=42" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem t32rt.exe" & set /a FAIL+=1 )

echo === [32] native x32 (tiny32 exit 42, Fase D1) ===
"%DX%" tests\tiny32.exe -o tests\out\t32n.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native x32" & set /a FAIL+=1 ) else ( echo "  OK: generate -native x32" & set /a PASS+=1 )
findstr /c:"push " tests\out\t32n.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem mnemonicos nativos x32" & set /a FAIL+=1 ) else ( echo "  OK: mnemonicos nativos x32" & set /a PASS+=1 )
"%DX%" tests\tiny32.exe -o tests\out\t32n.asm -r -O tests\out\t32nrt.exe -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native x32" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native x32" & set /a PASS+=1 )
if exist tests\out\t32nrt.exe (
    tests\out\t32nrt.exe >nul 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: rt-native exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: rt-native exit!=42" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem t32nrt.exe" & set /a FAIL+=1 )

echo.
echo =====================================================
echo Passaram: %PASS%   Falharam: %FAIL%
echo =====================================================
if %FAIL% neq 0 exit /b 1
exit /b 0

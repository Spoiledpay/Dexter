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
rem Guarda todos os fontes sagrados (nao so hello): qualquer .asm gerado
rem por engano em cima de um fonte do corpus (ex.: `dexter x.exe -v` usa
rem o default <input>.asm) e detectado antes de rodar a suite.
for %%A in (absidx hello jtable loop memsz no_relocs sibabs strings taildata tiny tiny32 vex) do (
    findstr /c:"FONTE SAGRADA DO CORPUS" "tests\%%A.asm" >nul 2>&1
    if errorlevel 1 (
        echo FALHA: tests\%%A.asm foi sobrescrito - restaure o arquivo.
        exit /b 1
    )
)
echo   OK: corpus integro
echo === [0b] sistema de versao ===
if not exist version.bin ( echo "  FALHA: version.bin ausente" & set /a FAIL+=1 ) else ( echo "  OK: version.bin existe" & set /a PASS+=1 )
if not exist obj\version.inc ( echo "  FALHA: obj\version.inc ausente" & set /a FAIL+=1 ) else ( echo "  OK: obj\version.inc existe" & set /a PASS+=1 )

echo === [1] build golden hello.exe ===
rem Toolchain portavel: C:\Nasm (instalacao local) ou PATH/MSVC (CI).
if exist "C:\Nasm\nasm.exe" ( set NASM=C:\Nasm\nasm.exe ) else ( set NASM=nasm.exe )
if exist "C:\Nasm\link.exe" ( set LINKER=C:\Nasm\link.exe ) else ( set LINKER=link.exe )
set KLIB=
if defined SDKLIBDIR if exist "%SDKLIBDIR%\kernel32.lib" set "KLIB=%SDKLIBDIR%\kernel32.lib"
if not defined KLIB if exist "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64\kernel32.lib" set "KLIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64\kernel32.lib"
if not defined KLIB (
    for /f "delims=" %%D in ('dir /b /ad "C:\Program Files (x86)\Windows Kits\10\Lib" 2^>nul') do (
        if exist "C:\Program Files (x86)\Windows Kits\10\Lib\%%D\um\x64\kernel32.lib" set "KLIB=C:\Program Files (x86)\Windows Kits\10\Lib\%%D\um\x64\kernel32.lib"
    )
)
if not defined KLIB set KLIB=kernel32.lib
set X86LIB=
if not defined X86LIB if exist "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x86\kernel32.lib" set "X86LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x86\kernel32.lib"
if not defined X86LIB (
    for /f "delims=" %%D in ('dir /b /ad "C:\Program Files (x86)\Windows Kits\10\Lib" 2^>nul') do (
        if exist "C:\Program Files (x86)\Windows Kits\10\Lib\%%D\um\x86\kernel32.lib" set "X86LIB=C:\Program Files (x86)\Windows Kits\10\Lib\%%D\um\x86\kernel32.lib"
    )
)
if not defined X86LIB set X86LIB=kernel32.lib
"%NASM%" -f win64 -o tests\out\hello_g.obj tests\hello.asm
if errorlevel 1 ( echo "  FALHA: nasm hello" & set /a FAIL+=1 ) else ( echo "  OK: nasm hello" & set /a PASS+=1 )
if exist tests\out\hello_g.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\hello.exe tests\out\hello_g.obj "%KLIB%"
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

if defined DEXTER_SKIP_LARGE goto :ci_skip_6b
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
:ci_skip_6b

echo === [6c] 32-bit extras (x32 validos: generate 0 + bits 32)
for %%X in (Calculator Case Char color Color2 Contador) do (
    "%DX%" tests\%%X.exe -o tests\out\x32_%%X.asm -q >nul 2>&1
    if !errorlevel! EQU 0 ( echo "  OK: %%X x32 aceito (0)" & set /a PASS+=1 ) else ( echo "  FALHA: %%X retornou !errorlevel!" & set /a FAIL+=1 )
)
findstr /c:"bits 32" tests\out\x32_Calculator.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: x32 sem bits 32" & set /a FAIL+=1 ) else ( echo "  OK: x32 com bits 32" & set /a PASS+=1 )

if defined DEXTER_SKIP_LARGE goto :ci_skip_6d
echo === [6d] ld.lld 68MB (dump rapido; round-trip completo em run_slow.bat)
"%DX%" tests\ld.lld.exe -o tests\out\ldlld.asm -v > tests\out\ldlld_v.log 2>&1
if errorlevel 1 ( echo "  FALHA: dump ld.lld" & set /a FAIL+=1 ) else ( echo "  OK: dump ld.lld" & set /a PASS+=1 )
findstr /c:"Sections: 9" tests\out\ldlld_v.log >nul 2>&1
if errorlevel 1 ( echo "  FALHA: 9 secoes esperadas" & set /a FAIL+=1 ) else ( echo "  OK: 9 secoes" & set /a PASS+=1 )
:ci_skip_6d

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
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\lex_check.exe tests\out\lex_check.obj obj\lexer.obj obj\opcode_tbl.obj "%KLIB%"
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
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\ast_check.exe tests\out\ast_check.obj obj\parser.obj obj\ast.obj obj\lexer.obj obj\memory.obj obj\string.obj obj\console.obj obj\opcode_tbl.obj "%KLIB%"
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
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\lift_check.exe tests\out\lift_check.obj obj\lift.obj "%KLIB%"
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
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\codegen_check.exe tests\out\codegen_check.obj obj\codegen.obj obj\emit_nasm.obj obj\asm_buffer.obj obj\labels.obj obj\memory.obj obj\string.obj obj\opcode_tbl.obj "%KLIB%"
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

echo === [14] imp label-at-slot (driver imp_check: HIT/dup/MISS) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\imp_check.obj tests\imp_check.asm
if errorlevel 1 ( echo "  FALHA: nasm imp_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm imp_check" & set /a PASS+=1 )
if exist tests\out\imp_check.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\imp_check.exe tests\out\imp_check.obj obj\rebuild.obj obj\asm_buffer.obj obj\memory.obj obj\string.obj obj\hash.obj obj\emit_nasm.obj obj\opcode_tbl.obj obj\decoder.obj obj\prefixes.obj obj\modrm.obj obj\operands.obj obj\semantics.obj obj\x87.obj obj\symbols.obj obj\labels.obj obj\strings.obj obj\file_read.obj obj\file_write.obj obj\mmap.obj obj\console.obj obj\pe_load.obj obj\pe_sections.obj obj\pe_imports.obj obj\pe_exports.obj obj\pe_relocs.obj obj\rva.obj obj\pe_unwind.obj obj\lexer.obj obj\parser.obj obj\ast.obj obj\lift.obj obj\codegen.obj obj\log.obj obj\parse_args.obj obj\help.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link imp_check" & set /a FAIL+=1 ) else ( echo "  OK: link imp_check" & set /a PASS+=1 )
)
if exist tests\out\imp_check.exe (
    tests\out\imp_check.exe > tests\out\imp.out 2>&1
    if errorlevel 1 ( echo "  FALHA: imp_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: imp_check exit 0" & set /a PASS+=1 )
    findstr /c:"__imp_KERNEL32_dll_ExitProcess:" tests\out\imp.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem label HIT" & set /a FAIL+=1 ) else ( echo "  OK: label HIT" & set /a PASS+=1 )
    findstr /c:"__imp_KERNEL32_dll_ExitProcess_2008:" tests\out\imp.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem sufixo no duplicado" & set /a FAIL+=1 ) else ( echo "  OK: duplicado com sufixo _rva" & set /a PASS+=1 )
    findstr /c:"__imp_KERNEL32_dll_WriteFile:" tests\out\imp.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem label do nome unico" & set /a FAIL+=1 ) else ( echo "  OK: nome unico puro" & set /a PASS+=1 )
)

echo === [15] symtab (driver sym_check: golden ordenado) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\sym_check.obj tests\sym_check.asm
if errorlevel 1 ( echo "  FALHA: nasm sym_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm sym_check" & set /a PASS+=1 )
if exist tests\out\sym_check.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\sym_check.exe tests\out\sym_check.obj obj\symbols.obj obj\memory.obj obj\string.obj obj\hash.obj "%KLIB%"
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
findstr /c:"\"imports_count\":62" tests\out\ovv.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: imports_count!=62" & set /a FAIL+=1 ) else ( echo "  OK: imports_count=62" & set /a PASS+=1 )

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

if defined DEXTER_SKIP_LARGE goto :ci_skip_18
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
:ci_skip_18

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
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\jtable.exe tests\out\jtable.obj "%KLIB%"
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
    "%LINKER%" /nologo /nodefaultlib /subsystem:console /entry:start /out:tests\tiny32.exe tests\out\tiny32.obj "%X86LIB%"
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

echo === [33] IAT absoluta x32 (jmp [__imp_X], Fase D2) ===
"%DX%" tests\tiny32.exe -o tests\out\i32.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native x32 IAT" & set /a FAIL+=1 ) else ( echo "  OK: generate -native x32 IAT" & set /a PASS+=1 )
findstr /c:"jmp [__imp_" tests\out\i32.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem jmp [__imp_]" & set /a FAIL+=1 ) else ( echo "  OK: jmp [__imp_]" & set /a PASS+=1 )
findstr /c:"__imp_KERNEL32_dll_ExitProcess:" tests\out\i32.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem label __imp_" & set /a FAIL+=1 ) else ( echo "  OK: label __imp_" & set /a PASS+=1 )
findstr /c:"[rel __imp_" tests\out\i32.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: sem forma rel em x32 (absoluto)" & set /a PASS+=1 ) else ( echo "  FALHA: forma rel em x32" & set /a FAIL+=1 )
"%DX%" tests\tiny32.exe -o tests\out\i32.asm -r -O tests\out\i32rt.exe -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native x32 IAT" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native x32 IAT" & set /a PASS+=1 )
if exist tests\out\i32rt.exe (
    tests\out\i32rt.exe >nul 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: rt-native exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: rt-native exit!=42" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem i32rt.exe" & set /a FAIL+=1 )

echo === [34] prefixo de tamanho em refs RIP (movzx/cmp, gcc-native) ===
"%NASM%" -f win64 -o tests\out\memsz.obj tests\memsz.asm
if errorlevel 1 ( echo "  FALHA: nasm memsz" & set /a FAIL+=1 ) else ( echo "  OK: nasm memsz" & set /a PASS+=1 )
if exist tests\out\memsz.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\memsz.exe tests\out\memsz.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link memsz" & set /a FAIL+=1 ) else ( echo "  OK: link memsz" & set /a PASS+=1 )
)
"%DX%" tests\out\memsz.exe -o tests\out\memsz_nat.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native memsz" & set /a FAIL+=1 ) else ( echo "  OK: generate -native memsz" & set /a PASS+=1 )
findstr /c:"movzx eax, byte [rel " tests\out\memsz_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem movzx byte" & set /a FAIL+=1 ) else ( echo "  OK: movzx byte" & set /a PASS+=1 )
findstr /c:"movzx ecx, word [rel " tests\out\memsz_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem movzx word" & set /a FAIL+=1 ) else ( echo "  OK: movzx word" & set /a PASS+=1 )
findstr /c:"cmp byte [rel " tests\out\memsz_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem cmp byte" & set /a FAIL+=1 ) else ( echo "  OK: cmp byte" & set /a PASS+=1 )
"%NASM%" -f win64 -o tests\out\memsz_nat.obj tests\out\memsz_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm memsz -native" & set /a FAIL+=1 ) else ( echo "  OK: nasm memsz -native" & set /a PASS+=1 )

echo === [35] bss nobits (R-8.1: resb + labels, var64 behavior) ===
"%DX%" tests\var64.exe -o tests\out\v64bss.asm -native -r -O tests\out\v64bss.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native var64" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native var64" & set /a PASS+=1 )
findstr /c:"resb 0x" tests\out\v64bss.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem resb na .bss" & set /a FAIL+=1 ) else ( echo "  OK: resb na .bss" & set /a PASS+=1 )
findstr /c:"label_1400110" tests\out\v64bss.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem labels na .bss" & set /a FAIL+=1 ) else ( echo "  OK: labels na .bss" & set /a PASS+=1 )
if exist tests\out\v64bss.exe (
    "%NASM%" -f win64 -o tests\out\v64bss.obj tests\out\v64bss.asm >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: nasm v64bss" & set /a FAIL+=1 ) else ( echo "  OK: nasm v64bss" & set /a PASS+=1 )
    findstr /c:"dq label_140011" tests\out\v64bss.asm >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sem dq p/ .bss" & set /a FAIL+=1 ) else ( echo "  OK: dq p/ .bss" & set /a PASS+=1 )
) else ( echo "  FALHA: sem v64bss.exe" & set /a FAIL+=1 )
if defined DEXTER_SKIP_LARGE goto :ci_skip_gccbss
"%DX%" tests\gcc.exe -o tests\out\gccbss.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native gcc" & set /a FAIL+=1 ) else ( echo "  OK: generate -native gcc" & set /a PASS+=1 )
findstr /c:"resb 0x" tests\out\gccbss.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem resb no gcc" & set /a FAIL+=1 ) else ( echo "  OK: resb no gcc" & set /a PASS+=1 )
:ci_skip_gccbss

echo === [36] bin nativo em PE simples (R-8.2 f1) ===
"%DX%" tests\hello.exe -o tests\out\hello_nb.asm -m bin -native -r -O tests\out\hello_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native hello" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native hello" & set /a PASS+=1 )
fc /b tests\hello.exe tests\out\hello_nb.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: hello_nb difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: hello_nb byte-identico" & set /a PASS+=1 )
rem R-5.3 F1: import NATIVO no bin (sem K, o bin cairia silenciosamente
rem em db e continuaria byte-identico — por isso o gate explicito).
findstr /c:"[rel __imp_" tests\out\hello_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: import nao-nativo no bin" & set /a FAIL+=1 ) else ( echo "  OK: import nativo (bin __imp_)" & set /a PASS+=1 )
findstr /r /c:"__imp_.* + 0x" tests\out\hello_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem correcao de delta K" & set /a FAIL+=1 ) else ( echo "  OK: correcao de delta K (bin)" & set /a PASS+=1 )
findstr /r /c:"^    mov " tests\out\hello_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem mnemonicos nativos" & set /a FAIL+=1 ) else ( echo "  OK: mnemonicos nativos" & set /a PASS+=1 )
"%DX%" tests\hello.exe -o tests\out\hello_nb_ast.asm -m bin -native -ast-dump -q > tests\out\nb_ast.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: ast-dump bin-native" & set /a FAIL+=1 ) else ( echo "  OK: ast-dump bin-native" & set /a PASS+=1 )
findstr /c:"instrs=0 " tests\out\nb_ast.out >nul 2>&1
if errorlevel 1 ( echo "  OK: AST com instrs reais" & set /a PASS+=1 ) else ( echo "  FALHA: AST sem instrs" & set /a FAIL+=1 )
"%DX%" tests\tiny.exe -o tests\out\tiny_nb.asm -m bin -native -r -O tests\out\tiny_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native tiny" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native tiny" & set /a PASS+=1 )
if exist tests\out\tiny_nb.exe (
    tests\out\tiny_nb.exe >nul 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: tiny_nb exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: tiny_nb exit!=42" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem tiny_nb.exe" & set /a FAIL+=1 )

echo === [37] bin nativo var64 (R-8.2 f2: byte-identico + comportamento) ===
"%DX%" tests\var64.exe -o tests\out\var64_nb.asm -m bin -native -r -O tests\out\var64_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native var64" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native var64" & set /a PASS+=1 )
if exist tests\out\var64_nb.exe (
    fc /b tests\var64.exe tests\out\var64_nb.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: var64_nb difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: var64_nb byte-identico" & set /a PASS+=1 )
    rem R-5.3 F1: import nativo tambem no var64 (call [rel __imp_ + 0x6600]).
    findstr /c:"[rel __imp_" tests\out\var64_nb.asm >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: var64 import nao-nativo no bin" & set /a FAIL+=1 ) else ( echo "  OK: var64 import nativo (bin)" & set /a PASS+=1 )
    tests\out\var64_nb.exe > tests\out\var64_nb.out 2>&1
    tests\var64.exe > tests\out\var64_orig2.out 2>&1
    fc tests\out\var64_orig2.out tests\out\var64_nb.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: comportamento identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem var64_nb.exe" & set /a FAIL+=1 )

echo === [38] matriz bin-native pequenos (R-8.2 f2+) ===
"%DX%" tests\loop.exe -o tests\out\loop_nb.asm -m bin -native -r -O tests\out\loop_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native loop" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native loop" & set /a PASS+=1 )
fc /b tests\loop.exe tests\out\loop_nb.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: loop_nb difere" & set /a FAIL+=1 ) else ( echo "  OK: loop_nb byte-identico" & set /a PASS+=1 )
if exist tests\out\loop_nb.exe (
    tests\out\loop_nb.exe > tests\out\loop_nb.out 2>&1
    tests\loop.exe > tests\out\loop_orig.out 2>&1
    fc tests\out\loop_orig.out tests\out\loop_nb.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: loop comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: loop comportamento identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem loop_nb.exe" & set /a FAIL+=1 )
"%DX%" tests\strings.exe -o tests\out\strings_nb.asm -m bin -native -r -O tests\out\strings_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native strings" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native strings" & set /a PASS+=1 )
fc /b tests\strings.exe tests\out\strings_nb.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: strings_nb difere" & set /a FAIL+=1 ) else ( echo "  OK: strings_nb byte-identico" & set /a PASS+=1 )
if exist tests\out\strings_nb.exe (
    tests\out\strings_nb.exe > tests\out\strings_nb.out 2>&1
    tests\strings.exe > tests\out\strings_orig.out 2>&1
    fc tests\out\strings_orig.out tests\out\strings_nb.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: strings comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: strings comportamento identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem strings_nb.exe" & set /a FAIL+=1 )
"%DX%" tests\no_relocs.exe -o tests\out\norelocs_nb.asm -m bin -native -r -O tests\out\norelocs_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native no_relocs" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native no_relocs" & set /a PASS+=1 )
fc /b tests\no_relocs.exe tests\out\norelocs_nb.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: norelocs_nb difere" & set /a FAIL+=1 ) else ( echo "  OK: norelocs_nb byte-identico" & set /a PASS+=1 )
if exist tests\out\norelocs_nb.exe (
    tests\out\norelocs_nb.exe > tests\out\norelocs_nb.out 2>&1
    tests\no_relocs.exe > tests\out\norelocs_orig.out 2>&1
    fc tests\out\norelocs_orig.out tests\out\norelocs_nb.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: no_relocs comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: no_relocs comportamento identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem norelocs_nb.exe" & set /a FAIL+=1 )
"%DX%" tests\jtable.exe -o tests\out\jt_nb.asm -m bin -native -r -O tests\out\jt_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native jtable" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native jtable" & set /a PASS+=1 )
fc /b tests\jtable.exe tests\out\jt_nb.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: jt_nb difere" & set /a FAIL+=1 ) else ( echo "  OK: jt_nb byte-identico" & set /a PASS+=1 )
if exist tests\out\jt_nb.exe (
    tests\out\jt_nb.exe > tests\out\jt_nb.out 2>&1
    tests\jtable.exe > tests\out\jt_orig.out 2>&1
    fc tests\out\jt_orig.out tests\out\jt_nb.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: jtable comportamento difere" & set /a FAIL+=1 ) else ( echo "  OK: jtable comportamento identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem jt_nb.exe" & set /a FAIL+=1 )
"%DX%" tests\t32.exe -o tests\out\t32_nb.asm -m bin -native -r -O tests\out\t32_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native t32" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native t32" & set /a PASS+=1 )
fc /b tests\t32.exe tests\out\t32_nb.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: t32_nb difere" & set /a FAIL+=1 ) else ( echo "  OK: t32_nb byte-identico" & set /a PASS+=1 )
if exist tests\out\t32_nb.exe (
    tests\t32.exe >nul 2>&1
    set T32E1=!errorlevel!
    tests\out\t32_nb.exe >nul 2>&1
    if !errorlevel! EQU !T32E1! ( echo "  OK: t32 exit igual ao original" & set /a PASS+=1 ) else ( echo "  FALHA: t32 exit difere" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem t32_nb.exe" & set /a FAIL+=1 )

echo === [39] VEX/EVEX/x87/3DNow! (R-2.7: limites + mnemonicos) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\x87_check.obj tests\x87_check.asm
if errorlevel 1 ( echo "  FALHA: nasm x87_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm x87_check" & set /a PASS+=1 )
if exist tests\out\x87_check.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\x87_check.exe tests\out\x87_check.obj obj\x87.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link x87_check" & set /a FAIL+=1 ) else ( echo "  OK: link x87_check" & set /a PASS+=1 )
)
if exist tests\out\x87_check.exe (
    tests\out\x87_check.exe > tests\out\x87.out 2>&1
    if !errorlevel! NEQ 0 ( echo "  FALHA: x87_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: x87_check exit 0" & set /a PASS+=1 )
    findstr /c:"op=216 n=256 h=576891333" tests\out\x87.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: x87 D8 golden" & set /a FAIL+=1 ) else ( echo "  OK: x87 D8 golden" & set /a PASS+=1 )
    findstr /c:"op=217 n=220 h=592770159" tests\out\x87.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: x87 D9 golden" & set /a FAIL+=1 ) else ( echo "  OK: x87 D9 golden" & set /a PASS+=1 )
    findstr /c:"op=218 n=225 h=4014298225" tests\out\x87.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: x87 DA golden" & set /a FAIL+=1 ) else ( echo "  OK: x87 DA golden" & set /a PASS+=1 )
    findstr /c:"op=219 n=197 h=975159937" tests\out\x87.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: x87 DB golden" & set /a FAIL+=1 ) else ( echo "  OK: x87 DB golden" & set /a PASS+=1 )
    findstr /c:"op=220 n=240 h=1122928381" tests\out\x87.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: x87 DC golden" & set /a FAIL+=1 ) else ( echo "  OK: x87 DC golden" & set /a PASS+=1 )
    findstr /c:"op=221 n=208 h=3807924869" tests\out\x87.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: x87 DD golden" & set /a FAIL+=1 ) else ( echo "  OK: x87 DD golden" & set /a PASS+=1 )
    findstr /c:"op=222 n=241 h=1839814490" tests\out\x87.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: x87 DE golden" & set /a FAIL+=1 ) else ( echo "  OK: x87 DE golden" & set /a PASS+=1 )
    findstr /c:"op=223 n=217 h=1567726076" tests\out\x87.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: x87 DF golden" & set /a FAIL+=1 ) else ( echo "  OK: x87 DF golden" & set /a PASS+=1 )
) else ( echo "  FALHA: sem x87_check.exe" & set /a FAIL+=1 )
"%NASM%" -f win64 -o tests\out\vex.obj tests\vex.asm
if errorlevel 1 ( echo "  FALHA: nasm vex" & set /a FAIL+=1 ) else ( echo "  OK: nasm vex" & set /a PASS+=1 )
if exist tests\out\vex.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\vex.exe tests\out\vex.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link vex" & set /a FAIL+=1 ) else ( echo "  OK: link vex" & set /a PASS+=1 )
)
tests\vex.exe >nul 2>&1
if !errorlevel! EQU 42 ( echo "  OK: vex exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: vex exit!=42" & set /a FAIL+=1 )
"%DX%" tests\vex.exe -o tests\out\vex_nb.asm -m bin -native -r -O tests\out\vex_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native vex" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native vex" & set /a PASS+=1 )
findstr /c:"; vex" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem rotulo vex" & set /a FAIL+=1 ) else ( echo "  OK: rotulo vex" & set /a PASS+=1 )
findstr /c:"; evex" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem rotulo evex" & set /a FAIL+=1 ) else ( echo "  OK: rotulo evex" & set /a PASS+=1 )
findstr /c:"; 3dnow" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem rotulo 3dnow" & set /a FAIL+=1 ) else ( echo "  OK: rotulo 3dnow" & set /a PASS+=1 )
findstr /c:"; fld" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem x87 real (fld)" & set /a FAIL+=1 ) else ( echo "  OK: x87 real (fld)" & set /a PASS+=1 )
findstr /c:"; fstp" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem x87 real (fstp)" & set /a FAIL+=1 ) else ( echo "  OK: x87 real (fstp)" & set /a PASS+=1 )
findstr /c:"; fninit" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem x87 real (fninit)" & set /a FAIL+=1 ) else ( echo "  OK: x87 real (fninit)" & set /a PASS+=1 )
rem limites byte-a-byte: cada instrucao VEX/EVEX/3DNow numa unica linha db
findstr /c:"db 0xC5, 0xE8, 0x58, 0xCB" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: VEX2 (vaddps) partido" & set /a FAIL+=1 ) else ( echo "  OK: limite VEX2" & set /a PASS+=1 )
findstr /c:"db 0xC5, 0xF8, 0x77" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: VEX2 sem modrm (vzeroupper) partido" & set /a FAIL+=1 ) else ( echo "  OK: limite VEX2 sem modrm" & set /a PASS+=1 )
findstr /c:"db 0xC4, 0xE2, 0x75, 0xA8, 0xC2" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: VEX3 0F38 partido" & set /a FAIL+=1 ) else ( echo "  OK: limite VEX3 0F38" & set /a PASS+=1 )
findstr /c:"db 0xC4, 0xE3, 0x7D, 0x04, 0xC1, 0x1B" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: VEX3 0F3A (imm) partido" & set /a FAIL+=1 ) else ( echo "  OK: limite VEX3 0F3A" & set /a PASS+=1 )
findstr /c:"db 0x62, 0xF1, 0x7C, 0x48, 0x10, 0x00" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: EVEX partido" & set /a FAIL+=1 ) else ( echo "  OK: limite EVEX" & set /a PASS+=1 )
findstr /c:"db 0x0F, 0x0F, 0xC1, 0x9E" tests\out\vex_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: 3DNow sem byte-sufixo" & set /a FAIL+=1 ) else ( echo "  OK: limite 3DNow (sufixo)" & set /a PASS+=1 )
if exist tests\out\vex_nb.exe (
    fc /b tests\vex.exe tests\out\vex_nb.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: vex_nb difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: vex_nb byte-identico" & set /a PASS+=1 )
    tests\out\vex_nb.exe >nul 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: vex_nb exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: vex_nb exit!=42" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem vex_nb.exe" & set /a FAIL+=1 )

echo === [40] SEH/unwind F1: parser .pdata/.xdata (R-5.4) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\unwind_check.obj tests\unwind_check.asm
if errorlevel 1 ( echo "  FALHA: nasm unwind_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm unwind_check" & set /a PASS+=1 )
if exist tests\out\unwind_check.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\unwind_check.exe tests\out\unwind_check.obj obj\pe_unwind.obj obj\pe_sections.obj obj\rva.obj obj\string.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link unwind_check" & set /a FAIL+=1 ) else ( echo "  OK: link unwind_check" & set /a PASS+=1 )
)
if exist tests\out\unwind_check.exe (
    tests\out\unwind_check.exe > tests\out\unwind.out 2>&1
    if !errorlevel! NEQ 0 ( echo "  FALHA: unwind_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: unwind_check exit 0" & set /a PASS+=1 )
    findstr /c:"UNWIND OK count=2" tests\out\unwind.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: golden unwind" & set /a FAIL+=1 ) else ( echo "  OK: golden unwind" & set /a PASS+=1 )
) else ( echo "  FALHA: sem unwind_check.exe" & set /a FAIL+=1 )

echo === [41] SEH F2: .pdata/.xdata simbolicos win64 (R-5.4) ===
"%DX%" tests\var64.exe -o tests\out\v64eh.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native var64" & set /a FAIL+=1 ) else ( echo "  OK: generate -native var64" & set /a PASS+=1 )
findstr /c:"section .pdata rdata" tests\out\v64eh.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem section .pdata" & set /a FAIL+=1 ) else ( echo "  OK: section .pdata" & set /a PASS+=1 )
findstr /c:"wrt ..imagebase" tests\out\v64eh.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: .pdata nao-simbolica" & set /a FAIL+=1 ) else ( echo "  OK: .pdata simbolica (wrt ..imagebase)" & set /a PASS+=1 )
findstr /c:"section .xdata rdata" tests\out\v64eh.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem section .xdata" & set /a FAIL+=1 ) else ( echo "  OK: section .xdata" & set /a PASS+=1 )
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\v64eh.obj tests\out\v64eh.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm v64eh" & set /a FAIL+=1 ) else ( echo "  OK: nasm v64eh" & set /a PASS+=1 )
"%DX%" tests\var64.exe -o tests\out\v64eh.asm -native -r -O tests\out\v64eh.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native var64 (link)" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native var64 (link)" & set /a PASS+=1 )
if exist tests\out\v64eh.exe (
    python tests\pe_exc_dir.py tests\out\v64eh.exe > tests\out\exc.txt 2>&1
    if !errorlevel! NEQ 0 ( echo "  FALHA: EXCEPTION_DIRECTORY invalido" & set /a FAIL+=1 ) else ( echo "  OK: EXCEPTION_DIRECTORY valido" & set /a PASS+=1 )
) else ( echo "  FALHA: sem v64eh.exe" & set /a FAIL+=1 )

echo === [42] SEH F3: .pdata/.xdata simbolicos em bin (R-5.4) ===
"%DX%" tests\var64.exe -o tests\out\v64f3.asm -m bin -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate bin-native var64" & set /a FAIL+=1 ) else ( echo "  OK: generate bin-native var64" & set /a PASS+=1 )
findstr /c:"dd label_140001000 + 0x" tests\out\v64f3.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: .pdata bin nao-simbolica" & set /a FAIL+=1 ) else ( echo "  OK: .pdata bin simbolica (label + C)" & set /a PASS+=1 )
"%NASM%" -f bin -o tests\out\v64f3.exe tests\out\v64f3.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm -f bin v64f3" & set /a FAIL+=1 ) else ( echo "  OK: nasm -f bin v64f3" & set /a PASS+=1 )
fc /b tests\var64.exe tests\out\v64f3.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: v64f3 difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: bin simbolico byte-identico" & set /a PASS+=1 )

echo === [43] SEH F4: excecao real C++ + fuzz unwind (R-5.4) ===
rem Fixture tests\exc.exe (MinGW-w64 g++ -O1): lanca/captura excecao com
rem __CxxFrameHandler3 real (117 RUNTIME_FUNCTION, flags EHANDLER/UHANDLER).
rem Prova: -m bin -native byte-identico E o reconstruido roda throw/catch
rem (exit 42). Sem o unwind reemitido correto, o desenrolar dos destrutores
rem nao fecharia e a saida nao seria 42.
if not exist tests\exc.exe ( echo "  FALHA: tests\exc.exe ausente" & set /a FAIL+=1 )
"%DX%" tests\exc.exe -o tests\out\exc_nb.asm -m bin -native -r -O tests\out\exc_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native exc" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native exc" & set /a PASS+=1 )
if exist tests\out\exc_nb.exe (
    fc /b tests\exc.exe tests\out\exc_nb.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: exc_nb difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: exc_nb byte-identico" & set /a PASS+=1 )
    tests\out\exc_nb.exe > tests\out\exc_nb.out 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: exc_nb exit 42 (throw/catch real)" & set /a PASS+=1 ) else ( echo "  FALHA: exc_nb exit!=42" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem exc_nb.exe" & set /a FAIL+=1 )
findstr /c:"dd label_" tests\out\exc_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: unwind nao-simbolico (sem dd label_)" & set /a FAIL+=1 ) else ( echo "  OK: unwind simbolico (.pdata/.xdata)" & set /a PASS+=1 )
python tests\fuzz_pe.py --input tests\exc.exe --cases 20 --seed 7 > tests\out\fuzz_exc.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: fuzz unwind (win64)" & set /a FAIL+=1 ) else ( echo "  OK: fuzz .pdata/.xdata (win64)" & set /a PASS+=1 )
python tests\fuzz_pe.py --input tests\exc.exe --cases 20 --seed 7 --bin-native > tests\out\fuzz_exc_bn.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: fuzz unwind (bin-native)" & set /a FAIL+=1 ) else ( echo "  OK: fuzz .pdata/.xdata (bin-native)" & set /a PASS+=1 )

echo === [44] strpool dedicado (D-3) ===
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\strpool_check.obj tests\strpool_check.asm
if errorlevel 1 ( echo "  FALHA: nasm strpool_check" & set /a FAIL+=1 ) else ( echo "  OK: nasm strpool_check" & set /a PASS+=1 )
if exist tests\out\strpool_check.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\strpool_check.exe tests\out\strpool_check.obj obj\strings.obj obj\asm_buffer.obj obj\string.obj obj\memory.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link strpool_check" & set /a FAIL+=1 ) else ( echo "  OK: link strpool_check" & set /a PASS+=1 )
)
if exist tests\out\strpool_check.exe (
    tests\out\strpool_check.exe > tests\out\strpool.out 2>&1
    if !errorlevel! NEQ 0 ( echo "  FALHA: strpool_check exit!=0" & set /a FAIL+=1 ) else ( echo "  OK: strpool_check exit 0" & set /a PASS+=1 )
    findstr /c:"STRPOOL o=0 6 B len=11" tests\out\strpool.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: golden strpool" & set /a FAIL+=1 ) else ( echo "  OK: golden strpool" & set /a PASS+=1 )
) else ( echo "  FALHA: sem strpool_check.exe" & set /a FAIL+=1 )

echo === [45] descritores de import simbolicos (R-5.3 F2) ===
rem Oraculo (tests\pe_impdesc.py): cada IMAGE_IMPORT_DESCRIPTOR vira label_ + 5
rem `dd`; campos RVA (OFT/Name/FT) rotulaveis saem `dd label_ + C` e o alvo
rem ganha label; os .asm sao byte-identicos (fc ja checado em [36]/[37]/[43]).
python tests\pe_impdesc.py tests\hello.exe tests\out\hello_nb.asm > tests\out\impdesc_hello.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: descritores import (hello)" & type tests\out\impdesc_hello.out & set /a FAIL+=1 ) else ( echo "  OK: descritores import (hello)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\var64.exe tests\out\var64_nb.asm > tests\out\impdesc_var64.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: descritores import (var64)" & type tests\out\impdesc_var64.out & set /a FAIL+=1 ) else ( echo "  OK: descritores import (var64)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\exc.exe tests\out\exc_nb.asm > tests\out\impdesc_exc.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: descritores import (exc)" & type tests\out\impdesc_exc.out & set /a FAIL+=1 ) else ( echo "  OK: descritores import (exc)" & set /a PASS+=1 )

echo === [46] notepad.exe real (MS; UNWIND_INFO em .rdata) ===
rem Fixture tests\notepad.exe (MS x64, 8 secoes, 315 imports): SEM secao
rem .xdata — o MS link funde o unwind no .rdata. Exercita o UNWIND_INFO
rem reemitido em QUALQUER secao (R-5.4; antes: label indefinido no nasm).
rem Prova: -m bin E -m bin -native byte-identicos + descritores + unwind.
if not exist tests\notepad.exe ( echo "  FALHA: tests\notepad.exe ausente" & set /a FAIL+=1 )
"%DX%" tests\notepad.exe -o tests\out\notepad_bin.asm -m bin -r -O tests\out\notepad_bin.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -m bin notepad" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -m bin notepad" & set /a PASS+=1 )
if exist tests\out\notepad_bin.exe (
    fc /b tests\notepad.exe tests\out\notepad_bin.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: notepad -m bin difere" & set /a FAIL+=1 ) else ( echo "  OK: notepad -m bin byte-identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem notepad_bin.exe" & set /a FAIL+=1 )
"%DX%" tests\notepad.exe -o tests\out\notepad_nb.asm -m bin -native -r -O tests\out\notepad_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -m bin -native notepad nao compila" & set /a FAIL+=1 ) else ( echo "  OK: -m bin -native notepad compila" & set /a PASS+=1 )
if exist tests\out\notepad_nb.exe (
    fc /b tests\notepad.exe tests\out\notepad_nb.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: notepad -m bin -native difere" & set /a FAIL+=1 ) else ( echo "  OK: notepad -m bin -native byte-identico (D-20)" & set /a PASS+=1 )
) else ( echo "  FALHA: sem notepad_nb.exe" & set /a FAIL+=1 )
findstr /c:"dd label_" tests\out\notepad_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: notepad unwind nao-simbolico" & set /a FAIL+=1 ) else ( echo "  OK: notepad unwind simbolico (.rdata)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\notepad.exe tests\out\notepad_nb.asm > tests\out\impdesc_notepad.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: descritores import (notepad)" & type tests\out\impdesc_notepad.out & set /a FAIL+=1 ) else ( echo "  OK: descritores import (notepad)" & set /a PASS+=1 )

echo === [47] thunks ILT/IAT simbolicos (R-5.3 F3) ===
rem Oraculo: entradas nao-nulas de OFT(ILT)/FT(IAT) viram `dq label_<hint/name>
rem + C`; ordinal/bound -> `dq 0x<v>` cru; o alvo ganha `label_`. Os .asm ja
rem sao byte-identicos (fc em [36]/[37]/[43]/[46]).
findstr /c:"dq label_140002186 + 0x1A00" tests\out\hello_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: thunk ILT/IAT nao-simbolico (hello)" & set /a FAIL+=1 ) else ( echo "  OK: thunk ILT/IAT simbolico (hello)" & set /a PASS+=1 )
findstr /c:"label_140002178:" tests\out\hello_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: label do hint/name ausente (hello)" & set /a FAIL+=1 ) else ( echo "  OK: label do hint/name emitido (hello)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\hello.exe tests\out\hello_nb.asm > tests\out\impthunk_hello.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: thunks (hello)" & type tests\out\impthunk_hello.out & set /a FAIL+=1 ) else ( echo "  OK: thunks conferidos (hello)" & set /a PASS+=1 )
findstr /c:"thunks=6 sym=6 raw=0 hint=6 nomes=1 ruins=0" tests\out\impthunk_hello.out >nul 2>&1
if errorlevel 1 ( echo "  FALHA: golden thunks hello" & type tests\out\impthunk_hello.out & set /a FAIL+=1 ) else ( echo "  OK: golden thunks hello (6/6/0)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\var64.exe tests\out\var64_nb.asm > tests\out\impthunk_var64.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: thunks (var64)" & type tests\out\impthunk_var64.out & set /a FAIL+=1 ) else ( echo "  OK: thunks conferidos (var64)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\notepad.exe tests\out\notepad_nb.asm > tests\out\impthunk_notepad.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: thunks (notepad)" & type tests\out\impthunk_notepad.out & set /a FAIL+=1 ) else ( echo "  OK: thunks conferidos (notepad)" & set /a PASS+=1 )
findstr /c:"thunks=630 sym=620 raw=10 hint=620 nomes=50 ruins=0" tests\out\impthunk_notepad.out >nul 2>&1
if errorlevel 1 ( echo "  FALHA: golden thunks notepad (bound->raw)" & type tests\out\impthunk_notepad.out & set /a FAIL+=1 ) else ( echo "  OK: golden thunks notepad (620 sym + 10 raw)" & set /a PASS+=1 )

echo === [48] hint/name + nomes de DLL simbolicos (R-5.3 F4) ===
rem Oraculo: cada IMAGE_IMPORT_BY_NAME sai `dw <hint>` + `db "<nome>", 0` e o
rem Name do descritor sai `db "<dll>", 0`; bytes identicos (fc ja checado).
findstr /c:"dw 0x186" tests\out\hello_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: hint/name nao-simbolico (hello)" & set /a FAIL+=1 ) else ( echo "  OK: hint/name simbolico (hello)" & set /a PASS+=1 )
findstr /c:"KERNEL32.dll" tests\out\hello_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nome de DLL nao-simbolico (hello)" & set /a FAIL+=1 ) else ( echo "  OK: nome de DLL simbolico (hello)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\hello.exe tests\out\hello_nb.asm > tests\out\impname_hello.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: hint/name (hello)" & type tests\out\impname_hello.out & set /a FAIL+=1 ) else ( echo "  OK: hint/name conferidos (hello)" & set /a PASS+=1 )
findstr /c:"hint=6 nomes=1 ruins=0" tests\out\impname_hello.out >nul 2>&1
if errorlevel 1 ( echo "  FALHA: golden hint/name hello" & type tests\out\impname_hello.out & set /a FAIL+=1 ) else ( echo "  OK: golden hint/name hello (6/1)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\exc.exe tests\out\exc_nb.asm > tests\out\impname_exc.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: hint/name (exc)" & type tests\out\impname_exc.out & set /a FAIL+=1 ) else ( echo "  OK: hint/name conferidos (exc)" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\notepad.exe tests\out\notepad_nb.asm > tests\out\impname_notepad.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: hint/name (notepad)" & type tests\out\impname_notepad.out & set /a FAIL+=1 ) else ( echo "  OK: hint/name conferidos (notepad)" & set /a PASS+=1 )
findstr /c:"hint=620 nomes=50 ruins=0" tests\out\impname_notepad.out >nul 2>&1
if errorlevel 1 ( echo "  FALHA: golden hint/name notepad" & type tests\out\impname_notepad.out & set /a FAIL+=1 ) else ( echo "  OK: golden hint/name notepad (620/50)" & set /a PASS+=1 )

echo === [49] SIB-abs com indice (loads indexados; R-5.4) ===
rem Fixture tests\sibabs.asm (x64): `lea [idx*scale]` (SIB base=none). Prova:
rem a emisao vira TEXTO simbolico (`nosplit`, sem o split [rax+rax] do nasm)
rem e o round-trip bin-native e byte-identico + comportamento (exit 42).
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\sibabs.obj tests\sibabs.asm
if errorlevel 1 ( echo "  FALHA: nasm sibabs" & set /a FAIL+=1 ) else ( echo "  OK: nasm sibabs" & set /a PASS+=1 )
if exist tests\out\sibabs.obj (
    "%LINKER%" /nologo /subsystem:console /entry:main /out:tests\out\sibabs.exe tests\out\sibabs.obj "%KLIB%"
    if errorlevel 1 ( echo "  FALHA: link sibabs" & set /a FAIL+=1 ) else ( echo "  OK: link sibabs" & set /a PASS+=1 )
)
if not exist tests\out\sibabs.exe ( echo "  FALHA: sem sibabs.exe" & set /a FAIL+=1 )
"%DX%" tests\out\sibabs.exe -o tests\out\sibabs_nb.asm -m bin -native -r -O tests\out\sibabs_nb.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild bin-native sibabs" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin-native sibabs" & set /a PASS+=1 )
findstr /c:"[nosplit rcx*4]" tests\out\sibabs_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: SIB-abs caiu em db" & set /a FAIL+=1 ) else ( echo "  OK: SIB-abs simbolico (nosplit)" & set /a PASS+=1 )
findstr /c:"[nosplit abs 0x8+rdx*4]" tests\out\sibabs_nb.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: SIB-abs com disp nao-simbolico" & set /a FAIL+=1 ) else ( echo "  OK: SIB-abs com disp simbolico (nosplit abs)" & set /a PASS+=1 )
if exist tests\out\sibabs_nb.exe (
    fc /b tests\out\sibabs.exe tests\out\sibabs_nb.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: sibabs difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: sibabs byte-identico" & set /a PASS+=1 )
    tests\out\sibabs_nb.exe > tests\out\sibabs_nb.out 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: sibabs_nb exit 42" & set /a PASS+=1 ) else ( echo "  FALHA: sibabs_nb exit nao e 42" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem sibabs_nb.exe" & set /a FAIL+=1 )

echo === [50] strings com CR/LF (`.str_run` + escape no qstr) ===
rem Fixture tests\strings.exe tem s1/s2/s3 com 13,10 e s2 com aspas. Prova:
rem o run vira UMA linha NASM (`db "...", 13, 10, 0`, aspas fechadas/reabertas
rem em volta dos escapes, sem `""`) e monta.
"%DX%" tests\strings.exe -o tests\out\strcrlf.asm -native -strings -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -strings (crlf)" & set /a FAIL+=1 ) else ( echo "  OK: generate -strings (crlf)" & set /a PASS+=1 )
python tests\qstr_check.py tests\out\strcrlf.asm > tests\out\qstr.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: qstr (crlf)" & type tests\out\qstr.out & set /a FAIL+=1 ) else ( echo "  OK: qstr CR/LF + aspas (linha unica)" & set /a PASS+=1 )
findstr /c:"QSTR linhas_crlf=" tests\out\qstr.out >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem resumo QSTR" & set /a FAIL+=1 ) else ( echo "  OK: resumo QSTR" & set /a PASS+=1 )
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\strcrlf.obj tests\out\strcrlf.asm > tests\out\strcrlf.err 2>&1
if errorlevel 1 ( echo "  FALHA: nasm strcrlf (ver tests\out\strcrlf.err)" & type tests\out\strcrlf.err & set /a FAIL+=1 ) else ( echo "  OK: nasm strcrlf" & set /a PASS+=1 )

echo === [51] indice simbolico x32 (tabela absoluta indexada) ===
rem Fixture tests\absidx.asm (x32): `jmp dword [jtab+eax*4]` (SIB-abs, base
rem ausente) + load indexado absoluto. O walker registra a VA da tabela no R
rem e o emissor sai `[nosplit label_<VA>+eax*4]` (antes: `0x402008` cru).
"%NASM%" -f win32 -o tests\out\absidx.obj tests\absidx.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm absidx" & set /a FAIL+=1 ) else ( echo "  OK: nasm absidx" & set /a PASS+=1 )
if exist tests\out\absidx.obj (
    "%LINKER%" /nologo /nodefaultlib /machine:x86 /subsystem:console /entry:main /out:tests\out\absidx.exe tests\out\absidx.obj "%X86LIB%" >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: link absidx" & set /a FAIL+=1 ) else ( echo "  OK: link absidx" & set /a PASS+=1 )
)
if not exist tests\out\absidx.exe ( echo "  FALHA: sem absidx.exe" & set /a FAIL+=1 )
"%DX%" tests\out\absidx.exe -o tests\out\absidx_nat.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native absidx" & set /a FAIL+=1 ) else ( echo "  OK: generate -native absidx" & set /a PASS+=1 )
findstr /c:"[nosplit label_402008+eax*4]" tests\out\absidx_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: indice nao-simbolico (jmp)" & set /a FAIL+=1 ) else ( echo "  OK: jmp [nosplit label_+idx] (simbolico)" & set /a PASS+=1 )
findstr /c:"[nosplit label_402018+edx*4]" tests\out\absidx_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: indice nao-simbolico (load)" & set /a FAIL+=1 ) else ( echo "  OK: load [nosplit label_+idx] (simbolico)" & set /a PASS+=1 )
findstr /c:"dd label_401017" tests\out\absidx_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: alvo de codigo (dd label_) ausente" & set /a FAIL+=1 ) else ( echo "  OK: tabela x32 com dd label_ (jump-to-code)" & set /a PASS+=1 )
"%DX%" tests\out\absidx.exe -o tests\out\absidx_rt.asm -native -r -O tests\out\absidx_rt.exe -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native absidx" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native absidx" & set /a PASS+=1 )
if exist tests\out\absidx_rt.exe (
    tests\out\absidx_rt.exe >nul 2>&1
    if !errorlevel! EQU 42 ( echo "  OK: absidx_rt exit 42 (switch tabela)" & set /a PASS+=1 ) else ( echo "  FALHA: absidx_rt exit nao e 42" & set /a FAIL+=1 )
) else ( echo "  FALHA: sem absidx_rt.exe" & set /a FAIL+=1 )

echo === [52] -s com SEH simbolico (D-17: nunca simbolo indefinido) ===
rem Fixture tests\exc.exe (x64, .pdata/.xdata reais, multiplas secoes).
rem Com `-s <secao>`, as demais secoes viram `db` sem label por-VA; a
rem reemissao simbolica da .pdata/.xdata NAO pode referenciar VA fora do
rem conjunto percorrido (senao nasm acusa `symbol not defined`). Sem `-s`
rem o mesmo binario monta 0 erros (controle implicito em [43]).
"%DX%" tests\exc.exe -s .rdata -o tests\out\secrip_rdata.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -s .rdata" & set /a FAIL+=1 ) else ( echo "  OK: generate -s .rdata" & set /a PASS+=1 )
"%NASM%" -f win64 -o tests\out\secrip_rdata.obj tests\out\secrip_rdata.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm -s .rdata (simbolo indefinido)" & set /a FAIL+=1 ) else ( echo "  OK: nasm -s .rdata (0 erros)" & set /a PASS+=1 )
"%DX%" tests\exc.exe -s .text -o tests\out\secrip_text.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -s .text" & set /a FAIL+=1 ) else ( echo "  OK: generate -s .text" & set /a PASS+=1 )
"%NASM%" -f win64 -o tests\out\secrip_text.obj tests\out\secrip_text.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm -s .text" & set /a FAIL+=1 ) else ( echo "  OK: nasm -s .text (0 erros)" & set /a PASS+=1 )
rem caminho byte-fiel: as secoes nao filtradas viram db (fc /b = 0)
"%DX%" tests\exc.exe -s .rdata -m bin -native -o tests\out\secrip_bin.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -s .rdata -m bin" & set /a FAIL+=1 ) else ( echo "  OK: generate -s .rdata -m bin" & set /a PASS+=1 )
"%NASM%" -f bin -o tests\out\secrip_bin.exe tests\out\secrip_bin.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm -s .rdata -m bin" & set /a FAIL+=1 ) else ( echo "  OK: nasm -s .rdata -m bin" & set /a PASS+=1 )
fc /b tests\exc.exe tests\out\secrip_bin.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -s .rdata -m bin difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: -s .rdata -m bin byte-identico" & set /a PASS+=1 )

echo === [53] D-19 fatia 1: unwind simbolico em QUALQUER secao (win64) ===
rem notepad.exe (MS link x64): o link funde o .xdata na .rdata e a .pdata
rem aponta p/ UNWIND_INFO dentro da .rdata (193 alvos distintos / 386 refs).
rem Sem "R-5.4 estendido" no caminho win64 o nasm acusa 386
rem `symbol label_14002Fxxx not defined`. Com o fix: 0 erros.
"%DX%" tests\notepad.exe -native -o tests\out\np_nat.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate -native notepad" & set /a FAIL+=1 ) else ( echo "  OK: generate -native notepad" & set /a PASS+=1 )
"%NASM%" -f win64 -o tests\out\np_nat.obj tests\out\np_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: nasm notepad -native (simbolo indefinido)" & set /a FAIL+=1 ) else ( echo "  OK: nasm notepad -native (0 erros)" & set /a PASS+=1 )
findstr /c:"wrt ..imagebase" tests\out\np_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem RVA simbolica (wrt ..imagebase)" & set /a FAIL+=1 ) else ( echo "  OK: RVA simbolica presente" & set /a PASS+=1 )
rem controle: x64 simples (hello) segue montando com -native
"%DX%" tests\hello.exe -native -o tests\out\np_hello.asm -q >nul 2>&1
"%NASM%" -f win64 -o tests\out\np_hello.obj tests\out\np_hello.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: regressao hello -native" & set /a FAIL+=1 ) else ( echo "  OK: hello -native segue 0 erros" & set /a PASS+=1 )
rem controle: caminho byte-fiel (-m bin) do notepad segue identico
"%DX%" tests\notepad.exe -m bin -native -o tests\out\np_bin.asm -q >nul 2>&1
"%NASM%" -f bin -o tests\out\np_bin.exe tests\out\np_bin.asm >nul 2>&1
fc /b tests\notepad.exe tests\out\np_bin.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: notepad -m bin -native difere" & set /a FAIL+=1 ) else ( echo "  OK: notepad -m bin -native byte-identico" & set /a PASS+=1 )

echo === [54] D-19 fatia 2a: DataDirectories remapeados por (secao, offset) ===
rem O link.exe reordena/funde secoes; dex_patch_dirs tem de remapear a RVA
rem de cada dir p/ a secao HOMONIMA da rebuildada (a RVA crua apontava p/ a
rem secao errada e o loader dava 0xC000007B).
rem D-19 2c-2: `exc` (EH C++ GCC pcrel) recusa -native -r; o proxy de PE
rem real com o link win64 e o var64 (5 dirs, inclusive TLS/IAT).
"%DX%" tests\var64.exe -native -r -O tests\out\var_dirs.exe -o tests\out\var_dirs.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native var64" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native var64" & set /a PASS+=1 )
python tests\pe_dirs.py tests\var64.exe tests\out\var_dirs.exe > tests\out\pe_dirs.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: DataDirectories nao remapeados" & type tests\out\pe_dirs.out & set /a FAIL+=1 ) else ( echo "  OK: dirs var64 por (secao,offset)" & set /a PASS+=1 )
"%DX%" tests\hello.exe -native -r -O tests\out\hello_dirs.exe -o tests\out\hello_dirs.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild hello" & set /a FAIL+=1 ) else ( echo "  OK: rebuild hello" & set /a PASS+=1 )
python tests\pe_dirs.py tests\hello.exe tests\out\hello_dirs.exe >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: dirs hello" & set /a FAIL+=1 ) else ( echo "  OK: dirs hello" & set /a PASS+=1 )

echo === [55] rebuild -s: entry label sempre definido (D-22) ===
rem Com -s <secao> != secao do entry, a secao do entry sai como dados e o
rem label_<entry> nunca era definido -> link falhava com LNK2001/exit 5.
rem O gerador fecha o .asm com `label_<entry> equ label_<secVA> + delta`.
"%DX%" tests\var64.exe -s .rdata -native -r -O tests\out\sr_nat.exe -o tests\out\sr_nat.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -s .rdata -native (LNK2001)" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -s .rdata -native" & set /a PASS+=1 )
findstr /c:" equ label_" tests\out\sr_nat.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: entry sem equ" & set /a FAIL+=1 ) else ( echo "  OK: entry via equ" & set /a PASS+=1 )
"%DX%" tests\var64.exe -s .rdata -r -O tests\out\sr_db.exe -o tests\out\sr_db.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -s .rdata (db)" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -s .rdata (db)" & set /a PASS+=1 )
"%DX%" tests\var64.exe -s .text -native -r -O tests\out\sr_txt.exe -o tests\out\sr_txt.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -s .text -native" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -s .text -native" & set /a PASS+=1 )
findstr /c:" equ label_" tests\out\sr_txt.asm >nul 2>&1
if errorlevel 1 ( echo "  OK: sem equ redundante (-s .text)" & set /a PASS+=1 ) else ( echo "  FALHA: equ redundante (-s .text)" & set /a FAIL+=1 )
rem x32: delta 0 nao pode gerar `equ label_X equ label_X` circular
"%DX%" tests\tiny32.exe -s .rdata -r -O tests\out\sr32.exe -o tests\out\sr32.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild x32 -s .rdata" & set /a FAIL+=1 ) else ( echo "  OK: rebuild x32 -s .rdata" & set /a PASS+=1 )

echo === [56] D-19 fatia 2b: import table simbolica no win64 -native ===
rem A .idata do win64 saia db cru com RVAs do layout antigo (OFT/Name/FT);
rem agora descritores/thunks/hint/name saem simbolicos (`wrt ..imagebase`) e
rem o link recalcula as RVAs. O oraculo pe_impdesc.py ganhou o modo win64.
rem Regressao do parser: imports_count do exc = 69 (antes 1; di volátil).
"%DX%" tests\exc.exe -o tests\out\imp64.asm -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate exc -native" & set /a FAIL+=1 ) else ( echo "  OK: generate exc -native" & set /a PASS+=1 )
python tests\pe_impdesc.py tests\exc.exe tests\out\imp64.asm win64 > tests\out\imp64.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: tabela de imports win64 nao simbolica" & type tests\out\imp64.out & set /a FAIL+=1 ) else ( echo "  OK: import table win64 simbolica" & set /a PASS+=1 )
findstr /c:"ruins=0" tests\out\imp64.out >nul 2>&1
if errorlevel 1 ( echo "  FALHA: ruins!=0 (impdesc win64)" & set /a FAIL+=1 ) else ( echo "  OK: impdesc win64 ruins=0" & set /a PASS+=1 )
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\imp64.obj tests\out\imp64.asm > tests\out\imp64.err 2>&1
if errorlevel 1 ( echo "  FALHA: nasm import win64" & type tests\out\imp64.err & set /a FAIL+=1 ) else ( echo "  OK: nasm import win64 (0 erros)" & set /a PASS+=1 )
"%DX%" tests\exc.exe -overview -json -q > tests\out\exc_ov.txt 2>&1
findstr /c:"\"imports_count\":69" tests\out\exc_ov.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: imports_count do exc original != 69" & set /a FAIL+=1 ) else ( echo "  OK: parser imports do exc = 69" & set /a PASS+=1 )
rem 2c-2: `exc` nao pode ser rebuildado no win64; o link da import table
rem simbolica e provado no var64 (62 imports) e no notepad (315, secao [46]).
"%DX%" tests\var64.exe -native -r -O tests\out\imp64.exe -o tests\out\imp64r.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native var64 (2b)" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native var64 (2b)" & set /a PASS+=1 )
"%DX%" tests\out\imp64.exe -overview -json -q > tests\out\imp64_ov.txt 2>&1
findstr /c:"\"imports_count\":62" tests\out\imp64_ov.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: imports_count do rebuildado != 62" & set /a FAIL+=1 ) else ( echo "  OK: imports do rebuildado = 62" & set /a PASS+=1 )
python tests\pe_dirs.py tests\var64.exe tests\out\imp64.exe > tests\out\imp64_dirs.out 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: dirs pos-2b" & type tests\out\imp64_dirs.out & set /a FAIL+=1 ) else ( echo "  OK: dirs pos-2b (5/5)" & set /a PASS+=1 )
"%DX%" tests\hello.exe -native -r -O tests\out\hi64.exe -o tests\out\hi64.asm -q >nul 2>&1
tests\out\hi64.exe > tests\out\hi64.txt 2>&1
findstr /c:"hi" tests\out\hi64.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: hello -native pos-2b" & set /a FAIL+=1 ) else ( echo "  OK: hello -native pos-2b (hi)" & set /a PASS+=1 )
"%DX%" tests\exc.exe -m bin -native -o tests\out\imp64b.asm -q >nul 2>&1
python tests\pe_impdesc.py tests\exc.exe tests\out\imp64b.asm >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -m bin -native regrediu" & set /a FAIL+=1 ) else ( echo "  OK: -m bin -native intacto" & set /a PASS+=1 )

echo === [57] D-19 fatia 2c: disp32 RIP relocavel + recusa 2c-2 + bss nobits ===
rem 2c-2: tabelas EH C++ do GCC sao pcrel; o link muda as secoes e nao ha
rem relocacao entre secoes -> `-native -r` no win64 e RECUSADO (exit 4).
rem A geracao pura continua (auditoria/nasm) e o caminho fiel e `-m bin`.
"%DX%" tests\exc.exe -o tests\out\d19c.asm -native -r -O tests\out\d19c.exe -q > tests\out\d19c.err 2>&1
if !errorlevel! NEQ 4 ( echo "  FALHA: exc -native -r deveria recusar (4)" & type tests\out\d19c.err & set /a FAIL+=1 ) else ( echo "  OK: exc -native -r recusado (4)" & set /a PASS+=1 )
findstr /c:"pcrel" tests\out\d19c.err >nul 2>&1
if errorlevel 1 ( echo "  FALHA: recusa 2c-2 sem mensagem pcrel" & set /a FAIL+=1 ) else ( echo "  OK: mensagem de recusa 2c-2" & set /a PASS+=1 )
"%DX%" tests\exc.exe -o tests\out\d19c.asm -native -q > tests\out\d19c_gen.err 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate exc -native (2c)" & set /a FAIL+=1 ) else ( echo "  OK: generate exc -native (2c)" & set /a PASS+=1 )
findstr /c:"dd label_" tests\out\d19c.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: sem dd label_ (kind 5 nao emitiu)" & set /a FAIL+=1 ) else ( echo "  OK: disp32 RIP relocavel (dd label_ - $ - 4)" & set /a PASS+=1 )
findstr /c:"section .bss bss" tests\out\d19c.asm >nul 2>&1
if errorlevel 1 ( echo "  FALHA: .bss nao saiu nobits" & set /a FAIL+=1 ) else ( echo "  OK: .bss nobits (CNT_UNINIT)" & set /a PASS+=1 )
"%NASM%" -f win64 -I obj\ -I include\ -o tests\out\d19c.obj tests\out\d19c.asm > tests\out\d19c_n.err 2>&1
if errorlevel 1 ( echo "  FALHA: nasm exc 2c" & type tests\out\d19c_n.err & set /a FAIL+=1 ) else ( echo "  OK: nasm exc 2c (0 erros)" & set /a PASS+=1 )
findstr /c:"zeroing" tests\out\d19c_n.err >nul 2>&1
if not errorlevel 1 ( echo "  FALHA: nasm -w+zeroing em .bss" & set /a FAIL+=1 ) else ( echo "  OK: sem aviso de zeroing" & set /a PASS+=1 )
python tests\label_drift.py tests\out\d19c.asm tests\exc.exe > tests\out\d19c_drift.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: deriva de comprimento (exc)" & type tests\out\d19c_drift.txt & set /a FAIL+=1 ) else ( echo "  OK: comprimentos exatos (exc)" & set /a PASS+=1 )
rem 2c-3: `.data` vsize>raw -> tail zerado com labels; auditorias do notepad.
"%DX%" tests\notepad.exe -native -r -O tests\out\d19n.exe -o tests\out\d19n.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native notepad (2c)" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native notepad (2c)" & set /a PASS+=1 )
python tests\rip_audit.py tests\out\d19n.asm tests\notepad.exe tests\out\d19n.exe > tests\out\d19n_rip.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: disp32 congelado (notepad)" & type tests\out\d19n_rip.txt & set /a FAIL+=1 ) else ( echo "  OK: nenhum disp32 congelado (notepad)" & set /a PASS+=1 )
findstr /c:"OK: nenhuma referencia RIP-relative congelada" tests\out\d19n_rip.txt >nul 2>&1
if errorlevel 1 ( echo "  FALHA: ainda ha refs sem label no notepad (2c-3)" & type tests\out\d19n_rip.txt & set /a FAIL+=1 ) else ( echo "  OK: notepad sem refs pendentes (sem_label=0)" & set /a PASS+=1 )
python tests\ptr_audit.py tests\notepad.exe tests\out\d19n.exe > tests\out\d19n_ptr.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: ponteiro de dados congelado (notepad)" & type tests\out\d19n_ptr.txt & set /a FAIL+=1 ) else ( echo "  OK: ponteiros de dados (notepad)" & set /a PASS+=1 )
"%DX%" tests\var64.exe -native -r -O tests\out\d19v.exe -o tests\out\d19v.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native var64 (2c)" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native var64 (2c)" & set /a PASS+=1 )
tests\out\d19v.exe > nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: comportamento var64 (era 0)" & set /a FAIL+=1 ) else ( echo "  OK: var64 win64 reconstruido roda (exit 0)" & set /a PASS+=1 )

echo === [58] D-19 fatia 2c-3: .data com vsize>raw (tail zerado + labels) ===
rem Fixture controlado: tests\taildata.asm tem m1/m2 em .data; o patch reduz
rem SizeOfRawData para 0x400 (loader zera o tail). O original patchado sai 42;
rem o rebuildado tem de sair 42 tambem e manter vsize/raw e os labels do tail.
"%NASM%" -f win64 -o tests\out\taildata.obj tests\taildata.asm > tests\out\taildata_n.err 2>&1
if errorlevel 1 ( echo "  FALHA: nasm taildata" & type tests\out\taildata_n.err & set /a FAIL+=1 ) else ( echo "  OK: nasm taildata" & set /a PASS+=1 )
"%LINKER%" /nologo /nodefaultlib /subsystem:console /entry:start /out:tests\out\taildata_orig.exe tests\out\taildata.obj "%KLIB%" > tests\out\taildata_l.err 2>&1
if errorlevel 1 ( echo "  FALHA: link taildata" & type tests\out\taildata_l.err & set /a FAIL+=1 ) else ( echo "  OK: link taildata" & set /a PASS+=1 )
python tests\taildata_patch.py tests\out\taildata_orig.exe tests\out\taildata.exe > tests\out\taildata_patch.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: patch taildata" & type tests\out\taildata_patch.txt & set /a FAIL+=1 ) else ( echo "  OK: patch .data raw=0x400" & set /a PASS+=1 )
tests\out\taildata.exe > nul 2>&1
if !errorlevel! NEQ 42 ( echo "  FALHA: fixture original deveria sair 42 (tail zerado)" & set /a FAIL+=1 ) else ( echo "  OK: original patchado sai 42" & set /a PASS+=1 )
"%DX%" tests\out\taildata.exe -native -r -O tests\out\taildata_re.exe -o tests\out\taildata_re.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: rebuild -native taildata" & set /a FAIL+=1 ) else ( echo "  OK: rebuild -native taildata" & set /a PASS+=1 )
tests\out\taildata_re.exe > nul 2>&1
if !errorlevel! NEQ 42 ( echo "  FALHA: rebuildado deveria sair 42" & set /a FAIL+=1 ) else ( echo "  OK: rebuildado sai 42" & set /a PASS+=1 )
python tests\taildata_check.py tests\out\taildata_re.asm tests\out\taildata.exe tests\out\taildata_re.exe > tests\out\taildata_check.txt 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: tail .data nao emitido/simbolico" & type tests\out\taildata_check.txt & set /a FAIL+=1 ) else ( echo "  OK: tail .data emitido com labels" & set /a PASS+=1 )
"%DX%" tests\out\taildata.exe -m bin -native -r -O tests\out\taildata_bin.exe -o tests\out\taildata_bin.asm -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: -m bin taildata" & set /a FAIL+=1 ) else ( echo "  OK: -m bin taildata" & set /a PASS+=1 )
fc /b tests\out\taildata.exe tests\out\taildata_bin.exe >nul 2>&1
if errorlevel 1 ( echo "  FALHA: -m bin taildata difere" & set /a FAIL+=1 ) else ( echo "  OK: -m bin taildata byte-identico" & set /a PASS+=1 )

echo.
echo =====================================================
echo Passaram: %PASS%   Falharam: %FAIL%
echo =====================================================
if %FAIL% neq 0 exit /b 1
exit /b 0

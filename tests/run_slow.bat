@echo off
rem =====================================================================
rem Dexter/tests/run_slow.bat — testes LENTOS (binários grandes, minutos)
rem Uso: tests\run_slow.bat
rem Requer: out\dexter.exe (build.bat). Gera ~450MB de .asm temporário.
rem NÃO faz parte da suíte rápida (run_tests.bat).
rem =====================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set PASS=0
set FAIL=0
set DX=out\dexter.exe
if exist "C:\Nasm\nasm.exe" ( set NASM=C:\Nasm\nasm.exe ) else ( set NASM=nasm.exe )

if not exist "%DX%" (
    echo FALHA: %DX% nao existe. Rode build.bat primeiro.
    exit /b 1
)
if not exist tests\out mkdir tests\out

echo === [S1] ld.lld 68MB: round-trip binario byte-identico ===
"%DX%" tests\ld.lld.exe -o tests\out\ldlld_bin.asm -m bin -r -O tests\out\ldlld_bin.exe -q
if errorlevel 1 ( echo "  FALHA: rebuild bin ld.lld" & set /a FAIL+=1 ) else ( echo "  OK: rebuild bin ld.lld" & set /a PASS+=1 )
if exist tests\out\ldlld_bin.exe (
    fc /b tests\ld.lld.exe tests\out\ldlld_bin.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: ldlld_bin difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: ldlld_bin byte-identico" & set /a PASS+=1 )
    mkdir %TEMP%\dexter_lldtest >nul 2>&1
    copy /y tests\out\ldlld_bin.exe %TEMP%\dexter_lldtest\ld.lld.exe >nul 2>&1
    %TEMP%\dexter_lldtest\ld.lld.exe --version > tests\out\ldlld_bin.out 2>&1
    tests\ld.lld.exe --version > tests\out\ldlld_orig.out 2>&1
    fc tests\out\ldlld_orig.out tests\out\ldlld_bin.out >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: --version difere" & set /a FAIL+=1 ) else ( echo "  OK: --version identico" & set /a PASS+=1 )
) else (
    echo "  FALHA: ldlld_bin.exe nao criado" & set /a FAIL+=1
)

echo === [S2] gcc 2MB: -m bin -native byte-identico + comportamento ===
"%DX%" tests\gcc.exe -o tests\out\gcc_nb.asm -m bin -native -q >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: generate bin-native gcc" & set /a FAIL+=1 ) else ( echo "  OK: generate bin-native gcc" & set /a PASS+=1 )
"%NASM%" -f bin -o tests\out\gcc_nb.exe tests\out\gcc_nb.asm >nul 2>&1
if !errorlevel! NEQ 0 ( echo "  FALHA: nasm gcc_nb" & set /a FAIL+=1 ) else ( echo "  OK: nasm gcc_nb" & set /a PASS+=1 )
if exist tests\out\gcc_nb.exe (
    fc /b tests\gcc.exe tests\out\gcc_nb.exe >nul 2>&1
    if errorlevel 1 ( echo "  FALHA: gcc_nb difere byte a byte" & set /a FAIL+=1 ) else ( echo "  OK: gcc_nb byte-identico" & set /a PASS+=1 )
) else ( echo "  FALHA: sem gcc_nb.exe" & set /a FAIL+=1 )
if exist "C:\gcc\bin\gcc.exe" if exist tests\out\gcc_nb.exe (
    if not exist tests\out\f3 mkdir tests\out\f3
    copy /y "C:\gcc\bin\gcc.exe" tests\out\f3\gcc_backup.exe >nul 2>&1
    copy /y tests\out\gcc_nb.exe "C:\gcc\bin\gcc.exe" >nul 2>&1
    "C:\gcc\bin\gcc.exe" tests\hello_f3.c -o tests\out\f3\hello_f3.exe >nul 2>&1
    set CMPOK=1
    if errorlevel 1 set CMPOK=0
    copy /y tests\out\f3\gcc_backup.exe "C:\gcc\bin\gcc.exe" >nul 2>&1
    if "!CMPOK!"=="1" (
        tests\out\f3\hello_f3.exe > tests\out\f3\hello_f3.out 2>&1
        findstr /c:"hi" tests\out\f3\hello_f3.out >nul 2>&1
        if errorlevel 1 ( echo "  FALHA: gcc rebuild nao imprime hi" & set /a FAIL+=1 ) else ( echo "  OK: gcc rebuild compila hello.c e imprime hi" & set /a PASS+=1 )
    ) else ( echo "  FALHA: gcc rebuild nao compilou" & set /a FAIL+=1 )
)

echo.
echo =====================================================
echo Lentos - Passaram: %PASS%  Falharam: %FAIL%
echo =====================================================
if %FAIL% neq 0 exit /b 1
exit /b 0

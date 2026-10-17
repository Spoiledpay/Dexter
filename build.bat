@echo off
rem =====================================================================
rem Dexter/build.bat — assembla src/*.asm -> obj/*.obj -> out/dexter.exe
rem Requisitos: nasm.exe (C:\Nasm ou PATH) + link.exe (C:\Nasm ou MSVC)
rem Uso: build.bat
rem =====================================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

if not exist out mkdir out
if not exist obj mkdir obj

rem ---- localizar nasm ----
set NASM=
if exist "C:\Nasm\nasm.exe" set NASM=C:\Nasm\nasm.exe
if not defined NASM where nasm.exe >nul 2>&1 && set NASM=nasm.exe
if not defined NASM (
    echo ERRO: nasm.exe nao encontrado ^(nem em C:\Nasm nem no PATH^)
    exit /b 1
)

rem ---- localizar link ----
set LINKER=
if exist "C:\Nasm\link.exe" set LINKER=C:\Nasm\link.exe
if not defined LINKER where link.exe >nul 2>&1 && set LINKER=link.exe
if not defined LINKER (
    echo ERRO: link.exe nao encontrado
    exit /b 1
)

rem ---- localizar kernel32.lib (SDK; override via env SDKLIBDIR) ----
set KLIB=
if defined SDKLIBDIR (
    if exist "%SDKLIBDIR%\kernel32.lib" set KLIB=%SDKLIBDIR%\kernel32.lib
)
if not defined KLIB if exist "C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64\kernel32.lib" set "KLIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64\kernel32.lib"
if not defined KLIB (
    for /f "delims=" %%D in ('dir /b /ad "C:\Program Files (x86)\Windows Kits\10\Lib" 2^>nul') do (
        if exist "C:\Program Files (x86)\Windows Kits\10\Lib\%%D\um\x64\kernel32.lib" set "KLIB=C:\Program Files (x86)\Windows Kits\10\Lib\%%D\um\x64\kernel32.lib"
    )
)
if not defined KLIB (
    echo ERRO: kernel32.lib nao encontrado ^(defina SDKLIBDIR^)
    exit /b 1
)
echo [lib] %KLIB%

echo [0/3] Versao...
powershell -NoProfile -ExecutionPolicy Bypass -File tools\bump_version.ps1
if errorlevel 1 (
    echo FALHA no versionamento ^(tools\bump_version.ps1^)
    exit /b 1
)
if not exist obj\version.inc (
    echo ERRO: obj\version.inc nao gerado
    exit /b 1
)

set SRC=src\main.asm src\cli\parse_args.asm src\cli\help.asm src\io\file_read.asm src\io\file_write.asm src\io\mmap.asm src\io\console.asm src\pe\pe_load.asm src\pe\pe_sections.asm src\pe\pe_imports.asm src\pe\pe_exports.asm src\pe\pe_relocs.asm src\pe\rva.asm src\pe\pe_resources.asm src\pe\pe_unwind.asm src\disasm\decoder.asm src\disasm\prefixes.asm src\disasm\modrm.asm src\disasm\opcode_tbl.asm src\disasm\operands.asm src\disasm\semantics.asm src\disasm\x87.asm src\disasm\emit_nasm.asm src\gen\asm_buffer.asm src\gen\labels.asm src\gen\symbols.asm src\gen\strings.asm src\gen\rebuild.asm src\diag\overview.asm src\diag\xref.asm src\diag\func.asm src\diag\trace.asm src\diag\snapshot.asm src\diag\compare.asm src\diag\doctor.asm src\front\lexer.asm src\front\parser.asm src\front\ast.asm src\back\lift.asm src\back\codegen.asm src\util\memory.asm src\util\string.asm src\util\hash.asm src\util\log.asm

echo [1/3] Assembling with %NASM% ...
for %%F in (%SRC%) do (
    "%NASM%" -f win64 -I obj\ -I include\ -o "obj\%%~nF.obj" "%%F"
    if errorlevel 1 (
        echo BUILD FAILED: %%F
        exit /b 1
    )
)

echo [2/3] Linking...
"%LINKER%" /nologo /subsystem:console /entry:main /out:out\dexter.exe /map:out\dexter.map obj\*.obj "%KLIB%"
if errorlevel 1 (
    echo LINK FAILED
    exit /b 1
)

echo OK: out\dexter.exe

rem ---- CTX (diario de contexto): proveniencia + indice (best-effort) ----
rem A ferramenta ctx esta no PATH. Ver skill.md secao "CTX". Nao falha o build.
where ctx >nul 2>nul
if not errorlevel 1 (
    if not exist .ctx.yaml ctx init --offline >nul 2>nul
    ctx scan --offline >nul 2>nul
    ctx build record out\dexter.exe >nul 2>nul
    echo [ctx] proveniencia + indice atualizados ^(ctx build record / ctx scan^)
)

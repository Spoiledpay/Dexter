@echo off
rem Dexter/clean.bat — remove artefatos de build
cd /d "%~dp0"
if exist obj rmdir /s /q obj
if exist out rmdir /s /q out
if exist tests\out rmdir /s /q tests\out
mkdir obj
mkdir out
mkdir tests\out
echo Limpo.

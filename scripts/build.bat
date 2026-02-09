@echo off
REM fstCC Bootstrap Build Script for Windows
REM Run from build/ subfolder

echo === fstCC Bootstrap Build Process ===

echo Stage 0: Building Assembly Compiler...
REM Assemble the assembly compiler (from parent directory)
nasm -f win64 ..\fstccV001.s -o fstccV001.obj
link fstccV001.obj /OUT:fstcc_asm.exe

echo Stage 1: Building C Compiler with Assembly Compiler...
REM Use assembly compiler to compile C compiler
fstcc_asm.exe ..\fstccV001.c fstccV001_asm.s

echo Stage 2: Assembling C Compiler...
REM Assemble the C compiler
nasm -f win64 fstccV001_asm.s -o fstccV001_c.obj
link fstccV001_c.obj /OUT:fstcc_c.exe

echo Stage 3: Self-Hosting Test...
REM Use C compiler to compile itself
fstcc_c.exe ..\fstccV001.c fstccV001_self.s

echo Bootstrap Complete!
echo Files created in build/ directory:
echo   fstcc_asm.exe    - Assembly compiler
echo   fstcc_c.exe      - C compiler
echo   fstccV001_asm.s  - Assembly output from C compiler
echo   fstccV001_self.s - Self-compiled output

pause

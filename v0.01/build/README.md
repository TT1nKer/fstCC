# fstCC Build Scripts

This folder contains build scripts for the fstCC bootstrap compiler.

## Files

- `build.bat` - Windows batch script
- `build.sh` - Linux shell script  
- `build_wsl.sh` - WSL shell script

## Usage

### Windows Native
```cmd
cd build
build.bat
```

### Linux/WSL
```bash
cd build
chmod +x build.sh
./build.sh
```

### WSL
```bash
cd build
chmod +x build_wsl.sh
./build_wsl.sh
```

## Bootstrap Process

1. **Stage 0**: Assemble `../fstccV001.s` → `fstcc_asm`
2. **Stage 1**: Use assembly compiler to compile `../fstccV001.c` → `fstcc_c`
3. **Stage 2**: Use C compiler to compile itself (self-hosting test)

## Output Files

All generated files are created in the `build/` directory:
- `fstcc_asm` - Assembly compiler executable
- `fstcc_c` - C compiler executable
- `fstccV001_asm.s` - Assembly output from C compiler
- `fstccV001_self.s` - Self-compiled output

## Requirements

### Windows
- NASM (Netwide Assembler)
- Microsoft Linker (Visual Studio Build Tools)

### Linux/WSL
- NASM: `sudo apt install nasm`
- GNU Linker (ld) - usually included

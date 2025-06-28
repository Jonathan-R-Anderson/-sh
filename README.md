# Minimal D Utilities for Internet Computer

This repository now provides only a few small utilities that can be compiled with **`-betterC`**. Modules which relied on the D runtime have been removed so the remaining programs are portable and do not require druntime support.

## Utilities

- `src/cpio.d` – parses and extracts `cpio` archives using `core.stdc` functions
- `src/false.d` – exits with a failure status

## Building

Use `ldc2` (or another D compiler) with `-betterC` and `--nodefaultlib`. Specify a target triple as required by the [`internetcomputer`](https://github.com/Jonathan-R-Anderson/internetcomputer) environment:

```bash
ldc2 -betterC --nodefaultlib -mtriple=<target> -I=. src/cpio.d -of=cpio
ldc2 -betterC --nodefaultlib -mtriple=<target> -I=. src/false.d -of=false
```

Replace `<target>` with the appropriate architecture triple.

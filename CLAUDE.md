# CLAUDE.md - TLSF-BSD Development Guide

This file provides build, test, and configuration context for AI coding assistants and automation reviewers (such as Claude Code, Cursor, and Cubic).

## Build and Test Commands

### Windows (MSVC)
* **Base Build & Run**:
  `cl.exe /Iinclude /O2 /W3 /std:c11 /DTLSF_ENABLE_ASSERT /DTLSF_ENABLE_CHECK tests\bench.c src\tlsf.c /Fe:bench_tlsf.exe && .\bench_tlsf.exe`
* **Modern Intrinsics Build & Structural Tests (x64)**:
  `cl.exe /Iinclude /O2 /W3 /arch:AVX2 /std:c11 /DTLSF_ENABLE_ASSERT /DTLSF_ENABLE_CHECK /DTLSF_MSVC_MODERN_INTRINSICS tests\test.c tests\test_thread.c src\tlsf.c /Fe:test_tlsf_x64.exe && .\test_tlsf_x64.exe`
* **Modern Intrinsics Build & Structural Tests (x86 32-bit)**:
  Requires initializing the x86 environment via `vcvars32.bat` first, then running:
  `cl.exe /Iinclude /O2 /W3 /arch:AVX2 /std:c11 /DTLSF_ENABLE_ASSERT /DTLSF_ENABLE_CHECK /DTLSF_MSVC_MODERN_INTRINSICS tests\test.c tests\test_thread.c src\tlsf.c /Fe:test_tlsf_x86.exe && .\test_tlsf_x86.exe`

### POSIX (GCC / Clang)
* **Standard Build & Run**:
  `gcc -Iinclude -O2 -Wall -std=c11 tests/test.c src/tlsf.c -o test_tlsf && ./test_tlsf`
* **Hardware Bit-Scan Build**:
  `gcc -Iinclude -O2 -Wall -std=c11 -mlzcnt -mbmi tests/test.c src/tlsf.c -o test_tlsf && ./test_tlsf`

---

## Compile Flags

* `TLSF_ENABLE_ASSERT`: Enables runtime internal invariant checks.
* `TLSF_ENABLE_CHECK`: Enables exhaustive memory pool structural validation via `tlsf_check()`.
* `TLSF_MSVC_MODERN_INTRINSICS`: Switches internal log2floor/bitmap_ffs bit-scan binning operations to modern hardware intrinsics (`__lzcnt`, `__tzcnt`) under MSVC.
  * **Default Status**: `Undefined` (Off). Must be explicitly declared.
  * **Target Toolchains**: Supports both MSVC `x64` (`_M_X64`) and `x86` (`_M_IX86`). Requires MSVC 2019 (v16.6) or newer.
  * **MSVC Requirements**: Must be compiled with `/arch:AVX2` or higher to safely emit targeted bit manipulation instructions.
  * **GCC/Clang Equivalent**: The exact same performance and hardware-generation effect is achieved natively on GCC/Clang via standard builtins (`__builtin_clz` / `__builtin_ctz`) **only if** compiled with specific hardware enablement flags: `-mlzcnt -mbmi` (or broadly via `-mavx2` / `-march=native`). Without these flags, GCC defaults to emitting slower legacy `bsr`/`bsf` instructions.
  * **Hardware Vector Modification**: **Warning! This flag alters target hardware requirements.** The resulting object files will require x86 CPUs with native **LZCNT** and **BMI1** extensions (Intel Haswell+, AMD Bulldozer+). Executing a binary built with this path on older CPUs will cause an immediate `Illegal Instruction` crash.
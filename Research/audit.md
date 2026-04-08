# Audit: swift-source

## Legacy — Consolidated 2026-04-08

### From: swift-institute/Research/platform-compliance-audit.md (2026-03-19)

**Skill**: platform — [PLAT-ARCH-001-010], [PATTERN-001], [PATTERN-004a], [PATTERN-005]

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| C-7 | CRITICAL | [PLAT-ARCH-008] | Source.Loader.swift:6-12 | Imports Darwin/Glibc/Musl for `open(2)`, `fstat(2)`, `read(2)` — POSIX file loading. Fix: Replace with `import Kernel`; Kernel already provides file descriptor operations. | OPEN — Phase 1 quick win |

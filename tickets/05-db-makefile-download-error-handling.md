# db/Makefile: curl | tar pipelines hide download failures

**File:** `db/Makefile:82` (`$(TZCODE)/Makefile` rule) and the `tzdata%` rule
**Severity:** low-medium (build tooling)

## Problem
`curl ... | tar xzf -` has no pipefail, so a failed curl is only noticed if tar happens to fail.
- In `$(TZCODE)/Makefile`, if the tzcode tarball downloads but the tzdata tarball fails, the target file already
  exists. The next `make` treats it as up to date and builds zic/zdump in an incomplete tree.
- In `tzdata%`, bsdtar can exit 0 on empty input. That leaves an empty `tzdataX/` and a confusing
  "No rule to make target tzdataX/africa" error.

## Suggested fix
Download to temp files with `curl -fsSL -o`, check each step, extract, and only then create the target
(or remove the directory on any failure). Alternatively, run the recipe under `set -o pipefail` (`SHELL := bash`).

## Acceptance
- [ ] A failed download leaves no target file behind and fails the make run with a clear message.

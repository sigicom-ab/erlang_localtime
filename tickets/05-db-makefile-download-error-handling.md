# db/Makefile: curl | tar pipelines hide download failures

**File:** `db/Makefile:81-92` (`$(TZCODE)/Makefile` rule) and `db/Makefile:97-106` (`tzdata%` rule)
**Severity:** low-medium (build tooling)

## Problem
`curl ... | tar xzf -` has no pipefail, so a failed curl is only noticed if tar happens to fail.
- In `$(TZCODE)/Makefile`, if the tzcode tarball downloads but the tzdata tarball fails, the target file already
  exists. The next `make` treats it as up to date and builds zic/zdump in an incomplete tree.
- In `tzdata%`, bsdtar can exit 0 on empty input. That leaves an empty `tzdataX/` and a confusing
  "No rule to make target tzdataX/africa" error.
- In `tzdata%`, an interrupt (Ctrl-C) during the download also leaves an empty `tzdataX/`. The target is a
  directory, and make does not delete a directory on an interrupt. The next `make` treats it as up to date.

## Suggested fix
Download to temp files with `curl -fsSL -o`, check each step, extract, and only then create the target
(or remove the directory on any failure). Alternatively, run the recipe under `set -o pipefail` (`SHELL := bash`).

## Fix
- Both rules download each tarball with `curl -fsSL -o` to a temporary file. They check each step and
  remove the partial tree and the temporary files on any failure.
- `$(TZCODE)/Makefile` removes `$(TZCODE)` before it starts. It also checks that `Makefile` and `africa` exist.
- `tzdata%` unpacks into `tzdataX.tmp/` and renames it to `tzdataX/` as the last step. Thus the target
  directory exists only when it is complete, also after an interrupt.

## Acceptance
- [x] A failed download leaves no target file behind and fails the make run with a clear message.
- [x] An interrupt during the `tzdata%` download leaves no `tzdataX/` directory behind.

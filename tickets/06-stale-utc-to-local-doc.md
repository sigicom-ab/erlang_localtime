# Stale utc_to_local/2 doc comment

**File:** `src/localtime.erl:26`
**Severity:** low (docs)
**Status:** fixed.

## Problem
The doc comment still says utc_to_local returns `LocalDateTime | [LocalDateTime, DstLocalDateTime] | {error, ErrDescr}`.
It now always returns a single datetime (see the README "Changes since the 2015g database" section).

## Fix
Change it to `LocalDateTime | {error, ErrDescr}`. Remove the `DstLocalDateTime` line (`src/localtime.erl:30`).

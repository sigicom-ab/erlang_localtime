# Dead list-handling branches in local_to_local / local_to_local_dst

**File:** `src/localtime.erl:67-75` and `:82-90`
**Severity:** low (cleanup)
**Status:** fixed.

## Problem
Both functions still match `utc_to_local/2`'s result against a two-element list. `utc_to_local/2` no longer returns
a list, so these `case LocalDateTime2 of [_, _] -> ...` branches are dead and suggest it can still return an ambiguous result.

## Fix
Return `utc_to_local(UtcDateTime, TimezoneTo)` directly from the first `case`. Remove the `LocalDateTime2` variable and
the second `case`.
Keep the list branches of the first `case`: `local_to_utc/2` still returns two candidates in an overlap.

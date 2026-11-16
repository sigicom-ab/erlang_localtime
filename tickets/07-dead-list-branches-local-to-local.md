# Dead list-handling branches in local_to_local / local_to_local_dst

**File:** `src/localtime.erl:77` and `:98`
**Severity:** low (cleanup)

## Problem
Both functions still match `utc_to_local/2`'s result against a two-element list. `utc_to_local/2` no longer returns
a list, so these `case LocalDateTime2 of [_, _] -> ...` branches are dead and suggest it can still return an ambiguous result.

## Fix
Assign `LocalDateTime2 = utc_to_local(UtcDateTime, TimezoneTo)` and return it directly; remove the second `case`.

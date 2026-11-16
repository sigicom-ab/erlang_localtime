# localtime_dst with a caller-supplied TZ tuple still applies database exceptions

**File:** `src/localtime_dst.erl:65` (`utc_offset/2`, `local_offsets/2`)
**Severity:** medium (correctness / API semantics)

## Problem
When the caller passes a TZ tuple, `exception/2` and `exception_offsets/1` look up `?tz_exceptions` by the tuple's
name (element 1). The result therefore depends on the committed history, not only on the rule the caller supplied.

## Scenario
`check(DT, {"Asia/Gaza", ..., custom rule})` for a 2014 date returns the committed Gaza history.
The hand-built Gaza and Damascus tuples in `check_test` pass only because that history happens to match.
A custom tuple that reuses a real zone name gets unrelated offsets as extra candidates.

## Suggested fix
Apply exceptions only when the zone is looked up by name (the string path of `check/2` and `localtime:*`), or pass
the exception list in explicitly. A bare tuple should mean "this rule only".

## Acceptance
- [ ] With a custom tuple, `check/2` results depend only on that tuple.
- [ ] `check_test` uses names that do not collide with real zones, or asserts the new behaviour.

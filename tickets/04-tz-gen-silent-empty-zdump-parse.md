# tz_gen: a zdump parse failure silently produces a database with no exceptions

**File:** `db/tz_gen.erl:336` (`zdump_timelines/5`), plus `timeline_diff([], _, _)`
**Severity:** medium (silent data loss in the generated output)
**Status:** fixed.

## Problem
zdump output is split on single spaces, and the zone name is recovered with `string:prefix(Path, Dir)`.
If parsing fails for every line (for example, the repo path contains a space), every zone gets an empty timeline.
`timeline_diff([], _, _)` treats an empty timeline as "the footer is exact".

## Scenario
Clone into `/Users/x/My Projects/erlang_localtime` and run `make -C db`. The generated `tz_database.hrl` has an empty
`?tz_exceptions`, nothing is reported, and the exit status is 0. All pre-2026 history is wrong.

## Suggested fix
- Fail if `Parsed` is empty, or if any zone whose footer has a DST rule has an empty timeline.
- Parse zdump lines robustly: split the path off by matching the known `Dir ++ Name` prefix
  before tokenizing the rest.

Note: a zone with no transitions (for example `Etc/UTC`) has a valid empty timeline. Do not reject it.

Note: convert `Dir` with `unicode:characters_to_binary/1`, not `list_to_binary/1`. `Dir` is a list of
codepoints, and zdump prints the path as UTF-8 bytes. With `list_to_binary/1`, a path such as `Ångström`
fails with `function_clause`, and a path such as `日本` fails with `badarg`.

## Acceptance
- [x] The generator exits nonzero instead of writing an exception-less database when zdump output cannot be parsed.

# list_timezones/0 returns abbreviations, not zone names

**File:** `src/localtime.erl:155-156`
**Severity:** low (API correctness; pre-existing, the line was rewritten on this branch)

## Problem
`list_timezones/0` returns the keys of `?tz_index`, which are abbreviations (`"CET"`, `"-03"`, `"+0530"`, ...), not
the zone names in `?tz_database`. With IANA's numeric abbreviations, most of the list is now offsets.

## Suggested fix
`lists:sort(maps:keys(?tz_database))`, or add `list_abbreviations/0` if the abbreviation list is still wanted.
Mention the change in the README "Changes since the 2015g database" section.

## Acceptance
- [ ] `list_timezones()` contains `"Europe/Stockholm"` and every `?tz_database` key.
- [ ] Test added.

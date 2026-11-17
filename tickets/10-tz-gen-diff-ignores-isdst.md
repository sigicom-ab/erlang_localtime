# timeline_diff ignores isdst differences between zdump and the yearly rule

**File:** `db/tz_gen.erl:420` (`timeline_diff/3`)
**Severity:** low-medium (correctness of the DST flag)
**Status:** fixed (2026-11-17).

## Problem
A piece becomes an exception only if `{Off, Abbr} =/= {POff, PAbbr}`. When zdump's isdst differs from the
rule's DST state but the offset and abbreviation match, no exception is emitted. The library then reports the
rule's DST flag for that period.

## Scenario
A historical period has the same offset and abbreviation as the current rule's standard (or DST) state but the
opposite isdst, for example a numeric abbreviation used once as standard time and later as DST. In that period
`check/2` returns `is_in_dst` / `is_not_in_dst` the wrong way round. `dst_flag_in_exception_periods_test_` only covers
periods that already differ in offset or abbreviation.

Known instance: Europe/Dublin (and Eire) in summer 1970 and summer 1971. IST was all-year standard time, but the rule
calls IST daylight time, so `check({{1970,7,15},{12,0,0}}, "Europe/Dublin")` returns `is_in_dst`, while January 1970
returns `is_not_in_dst` (after ticket 09).

## Suggested fix
Give predicted timelines a DST flag (`rule_transitions/3` knows which transition is `dst` and which is `std`). Then
compare `{Off, Abbr, IsDst}`, taking negative DST into account (see ticket 09).

## Acceptance
- [x] Count how many periods in 2026f differ only in isdst (none is fine, but measure it).
- [x] The generator emits exceptions for isdst-only differences, or a test asserts that 2026f has none.

## Fix
Predicted timelines carry a DST flag (`rule_transitions/3` marks the start transition `true`, the end `false`;
fixed-offset zones are `false`), and `timeline_diff/3` compares the whole `{Off, Abbr, IsDst}` state against zdump's
state after `dst_flags/2`.

Measured on 2026f (window 1970-2046, generated 2026-11-13), against the database before this fix: 69 zones change,
500 periods added, 66 removed (414 zones still carry exceptions).
- 58 zones gain isdst-only periods. Most are numeric abbreviations that were DST once and are standard time now
  (Argentina, Paraguay, Chile, Falklands, Russia, the Caucasus and Central Asia; e.g. Buenos Aires -03 in 1999-2000).
- Europe/London (and its Links) and Europe/Dublin/Eire: the all-year standard BST/IST of 1968-10-27 .. 1971-10-31
  becomes one period each, replacing the winter-only pieces. Dublin's summers 1970 and 1971 are no longer DST.
- America/Scoresbysund: the Sept-Oct gaps of 1981-2023, when it was on -01 standard time and the rule calls -01
  DST, are now covered.

## Decision: negative DST in zones without a negative footer
Comparing the flag exposed zones whose zdump history has negative DST but whose current footer does not. Decision:
DST is never behind the standard time next to it, in any zone. `dst_flags/2` now runs for every zone: an isdst=1
state that is lower than each of its isdst=0 neighbours is standard time. Only zones with a negative footer
(Dublin) also turn the higher state between two such states into DST.
- Africa/Casablanca, Africa/El_Aaiun: Ramadan +00 in 2019-2026 stays `is_not_in_dst` (as before this ticket), so
  no new periods.
- Africa/Windhoek: winter WAT 1994-2017 (24 existing periods) flips from `true` to `false`.
- "Each neighbour" rather than "either neighbour": America/Nome's BDT in summer 1983 (BST -11 -> BDT -10 -> YST -09)
  stays ordinary DST.

Tests: `dst_flag_in_exception_periods_test_` pins Dublin/Eire 1970-71 summers and 1971-10-31 01:30, Casablanca and
El_Aaiun in Ramadan 2024, Windhoek in July 2000 and Nome in July 1983.

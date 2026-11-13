
Erlang Localtime
===


### Public exports

* `utc_to_local/2` – Converts UTC time to local according to specified Timezone
* `local_to_utc/2` – Converts local time to UTC
* `local_to_local/3` – Converts local time to local
* `tz_name/2` – Returns a timezone name (E.g. MSK, MSD, etc)
* `tz_shift/2` – Returns time difference between local datetime and GMT
* `tz_shift/3` – Returns time difference between local datetime and required timezone

### Details

#### Types
* `DateTime` = `{date(), time()}`.
* `TimeZone` = `TimeZoneFrom` = `TimeZoneTo` = `list()`, e.g. `"Europe/Moscow"`, `"America/NewYork"` or abbreviations `"MSK"`, `"MSD"`, etc.
* `ZoneName` =  `{StdAbbr :: list(), StdName :: list()}`, e.g. `{"MSK","MSK"}`
* `ZoneShift` = `{Sign :: '+' | '-', Offset :: non_neg_integer(), RemOffset :: non_neg_integer()}`

#### Dialyzer

`utc_to_local(DateTime, TimeZone) → DateTime | {error, Reason}`

`local_to_utc(DateTime, TimeZone) → DateTime | {error, Reason}`

`local_to_local(DateTime, TimeZoneFrom, TimeZoneTo) → DateTime | {error, Reason}`

`tz_name(DateTime, TimeZone) → ZoneName | {error, Reason}`

`tz_shift(DateTime, TimeZone) → 0 | ZoneShift | {error, Reason}`

`tz_shift(DateTime, TimeZoneFrom, TimeZoneTo) → 0 | ZoneShift | {error, Reason}`

#### Note

Aabbreviation is just used to find appropriate timezone name. If you want to convert `"MSK"` → `"PDT"`, but source timezone is not in daylight saving, it will be corrected by library and `"MSK"` → `"PST"` conversion will be made.

### Examples of usage

#### Converts UTC time to local one
```erlang
localtime:utc_to_local({{2010, 7, 22}, {17, 56, 23}}, "Europe/Moscow").
{{2010,10,10},{21,56,23}}
```

#### Converts local time to UTC one
```erlang
localtime:local_to_utc({{2010, 10, 10}, {21, 56, 23}}, "Europe/Moscow").
{{2010,10,10},{17,56,23}}
```

#### Converts time from one local timezone to another local one
```erlang
localtime:local_to_local({{2010, 10, 10}, {21, 56, 23}}, "Europe/Moscow", "Australia/Sydney").
{{2010,10,11},{3,56,23}}
```

#### Returns timezone name
```erlang
localtime:tz_name({{2010, 10, 10}, {21, 56, 23}}, "Europe/Moscow").
{"MSK","MSK"}

localtime:tz_name({{2010,10,11},{3,56,23}}, "Australia/Sydney").
{"EST","EST"}
```

#### Calculates time difference between UTC and local one
```erlang
localtime:tz_shift({{2013, 01, 22}, {18, 17, 00}}, "Europe/Moscow").
{'+',4,0}

localtime:tz_shift({{2013, 01, 22}, {18, 17, 00}}, "America/New York").
{'-',5,0}
```

#### Calculates time difference between two local timezones
```erlang
localtime:tz_shift({{2013, 01, 22}, {18, 17, 00}}, "America/New York", "Europe/Moscow").
{'+',9,0}
```

### Time zone database

`include/tz_database.hrl` is generated from the [IANA tz database](https://www.iana.org/time-zones)
by `db/tz_gen.erl`, and `include/tz_index.hrl` is derived from it by `src/ibuild.erl`. The release
it was generated from is recorded in the header of `include/tz_database.hrl`. To update to the
latest release (requires `curl`, a C compiler and Erlang):

```
make -C db         # fetch the latest release, build zic/zdump, compile data, generate
make               # rebuild tz_index.hrl and compile
make -C db test    # fetch the data for the committed release, run all tests
```

`make -C db` does nothing if the committed database is already at the latest release (`FORCE=1`
regenerates anyway); `make -C db TZ_VERSION=2026e` generates a specific release.

Tests of known transitions live in `test/localtime_transitions_tests.erl` and run without any
downloads; add one there whenever a rule change is worth pinning down.

Each zone is described by one yearly rule taken from the POSIX TZ string `zic` stores in the
compiled TZif file. Rule times may be negative or 24 hours or more (e.g. Asia/Jerusalem
`{4,thu,mar},{26,0}`: 02:00 on the day after the 4th Thursday). Periods where a zone does not
follow its rule (history under earlier rules, e.g. America/Winnipeg's CST/CDT before its move to
permanent −05 on 2026-11-01, or Morocco's Ramadan suspensions) are listed in `?tz_exceptions`,
covering 1970 to the generation year plus 20. Beyond that window the yearly rule applies, so
**results for dates before 1970 are unsupported**. Offsets are whole minutes; the only sub-minute
offset in the window (Africa/Monrovia, −00:44:30 until 1972) is rounded to −00:45.

#### Changes since the 2015g database

* `Etc/GMT±N` follows the IANA/POSIX sign convention: `Etc/GMT+1` is UTC−1.
* Abbreviations follow IANA, which replaced many invented ones with numeric ones
  (e.g. `"-03"` instead of `"BRT"`); the old abbreviations no longer resolve in `get_timezone/1`.
* `Canada/East-Saskatchewan` was removed upstream; use `America/Regina`.
* A zone name that is also an abbreviation (`CET`, `EET`, `EST`, `GMT`, `HST`, `MST`, `UTC`, `WET`)
  now resolves to that zone.
* `utc_to_local/2` always returns a single datetime (it used to return a list in the hour after
  a fall-back transition).

%% @author  Dmitry S. Melnikov (dmitryme@gmail.com)
%% @copyright 2010 Dmitry S. Melnikov

-module(localtime_dst).

-author("Dmitry Melnikov <dmitryme@gmail.com>").

-include("tz_database.hrl").
-include("tz_index.hrl").

-export(
   [
      check/2,
      utc_offset/2,
      local_offsets/2
   ]).

-compile([export_all]).

% A ?tz_database row (see include/tz_database.hrl).
-type tz() :: tuple().
-export_type([tz/0]).

% check(DateTime, TimeZone) -> is_in_dst | is_not_in_dst | ambiguous_time | time_not_exists
%  DateTime = DateTime(), local wall-clock time
%  TimeZone = String() | tuple()
-spec check(Datetime :: calendar:datetime(), Timezone :: tz() | string()) -> {error, unknown_tz} | time_not_exists | is_not_in_dst | is_in_dst | ambiguous_time.
check(DateTime, Timezone) when is_list(Timezone) ->
    case lists:keyfind(localtime:get_timezone(Timezone), 1, ?tz_database) of
        false ->
            {error, unknown_tz};
        TZ ->
            check(DateTime, TZ)
    end;
check(DateTime, TZ = {_, _, _, Shift, _, _, _, _, _}) ->
   case local_offsets(DateTime, TZ) of
      [] -> time_not_exists;
      [{Shift, _}] -> is_not_in_dst;
      [_] -> is_in_dst;
      [_, _ | _] -> ambiguous_time
   end.

% utc_offset(UtcDateTime, TZ) -> {OffsetMin, {Abbr, Name}}
%  The UTC offset (in minutes) and name in effect at UtcDateTime.
utc_offset(UtcDateTime, TZ = {Name, StdName, DstName, Shift, DstShift, _, _, _, _}) ->
   Utc = calendar:datetime_to_gregorian_seconds(UtcDateTime),
   case exception(Name, Utc) of
      {Offset, Abbr} ->
         {Offset, {Abbr, Abbr}};
      none when DstName =:= undef ->
         {Shift, StdName};
      none ->
         {Year, _, _} = element(1, UtcDateTime),
         Events = lists:append([transitions(TZ, Y) || Y <- [Year - 1, Year, Year + 1]]),
         case [Ev || {T, _} = Ev <- lists:sort(Events), T =< Utc] of
            [] -> {Shift, StdName};
            Past ->
               case lists:last(Past) of
                  {_, dst} -> {Shift + DstShift, DstName};
                  {_, std} -> {Shift, StdName}
               end
         end
   end.

% local_offsets(LocalDateTime, TZ) -> [{OffsetMin, {Abbr, Name}}]
%  All offsets under which LocalDateTime is a valid wall-clock time, in
%  ascending order: [] in a gap (spring forward), two entries in an overlap.
local_offsets(LocalDateTime, TZ = {Name, _, _, Shift, DstShift, _, _, _, _}) ->
   Local = calendar:datetime_to_gregorian_seconds(LocalDateTime),
   Candidates = lists:usort([Shift, Shift + DstShift | exception_offsets(Name)]),
   lists:usort(
     [Res || Offset <- Candidates,
             Res = {O, _} <- [utc_offset(calendar:gregorian_seconds_to_datetime(Local - Offset * 60), TZ)],
             O =:= Offset]).

% The UTC instants (gregorian seconds) of the DST start and end in Year.
% Start time is local standard time, end time local daylight time; hours may
% be negative or >= 24 (counted from midnight of the rule day).
transitions({_, _, _, Shift, DstShift, StartRule, StartTime, EndRule, EndTime}, Year) ->
   [{rule_seconds(StartRule, StartTime, Year) - Shift * 60, dst},
    {rule_seconds(EndRule, EndTime, Year) - (Shift + DstShift) * 60, std}].

rule_seconds(Rule, Time, Year) ->
   Days = calendar:date_to_gregorian_days({Year - 1, 12, 31}) + get_dst_day_of_year(Rule, Year),
   Days * 86400 + time_to_minutes(Time) * 60.

% Periods are {UtcStartSecs, UtcEndSecs, OffsetMin, Abbr} (gregorian seconds),
% sorted and non-overlapping, so the scan can stop at the first period that
% starts after Utc.
exception(Name, Utc) ->
   case lists:keyfind(Name, 1, ?tz_exceptions) of
      false -> none;
      {_, Periods} -> find_period(Periods, Utc)
   end.

find_period([{S, _, _, _} | _], Utc) when Utc < S -> none;
find_period([{_, E, Off, Abbr} | _], Utc) when Utc < E -> {Off, Abbr};
find_period([_ | Rest], Utc) -> find_period(Rest, Utc);
find_period([], _) -> none.

exception_offsets(Name) ->
   case lists:keyfind(Name, 1, ?tz_exceptions) of
      false -> [];
      {_, Periods} -> [Off || {_, _, Off, _} <- Periods]
   end.

get_dst_day_of_year({WeekDay,DayOfWeek,Month}, Year) when (WeekDay == last) or (WeekDay == 5) ->
   IntMonth = month_to_int(Month),
   IntDayOfWeek = day_to_int(DayOfWeek),
   get_last_dst(IntDayOfWeek, IntMonth, Year);
get_dst_day_of_year({WeekDay,DayOfWeek,Month}, Year) when (WeekDay > 0) and (WeekDay =< 4) ->
   IntMonth = month_to_int(Month),
   IntDayOfWeek = day_to_int(DayOfWeek),
   DstDays = get_day_of_year({Year, IntMonth, 1}),
   DstDayOfWeek = calendar:day_of_the_week({Year, IntMonth, 1}),
   case (DstDayOfWeek =:= IntDayOfWeek) and (WeekDay =:= 1) of
      true ->
         DstDays;
      false ->
         AdjustedDstDays =
         case IntDayOfWeek >= DstDayOfWeek of
            true ->
               DstDays + (IntDayOfWeek - DstDayOfWeek);
            false ->
               DstDays + (7 - DstDayOfWeek) + IntDayOfWeek
         end,
         AdjustedDstDays + (WeekDay - 1) * 7
      end;
get_dst_day_of_year(_, _) ->
   throw({error, wrong_week_day}).

get_last_dst(IntDayOfWeek, IntMonth, Year) ->
   MonthLastDays = calendar:date_to_gregorian_days(Year, IntMonth, 1) + calendar:last_day_of_the_month(Year, IntMonth),
   MonthLastDate = calendar:gregorian_days_to_date(MonthLastDays),
   MonthLastDayOfWeek = calendar:day_of_the_week(MonthLastDate),
   case MonthLastDayOfWeek > IntDayOfWeek of
      true ->
         MonthLastDays - (MonthLastDayOfWeek - IntDayOfWeek) - calendar:date_to_gregorian_days({Year - 1, 12, 31});
      false ->
         MonthLastDays - MonthLastDayOfWeek - (7 - IntDayOfWeek) - calendar:date_to_gregorian_days({Year - 1, 12, 31})
   end.

get_day_of_year(Date = {Year, _Month, _Day}) ->
   calendar:date_to_gregorian_days(Date) - calendar:date_to_gregorian_days({Year - 1, 12, 31}).

month_to_int(jan) -> 1;
month_to_int(feb) -> 2;
month_to_int(mar) -> 3;
month_to_int(apr) -> 4;
month_to_int(may) -> 5;
month_to_int(jun) -> 6;
month_to_int(jul) -> 7;
month_to_int(aug) -> 8;
month_to_int(sep) -> 9;
month_to_int(oct) -> 10;
month_to_int(nov) -> 11;
month_to_int(dec) -> 12.

day_to_int(mon) -> 1;
day_to_int(tue) -> 2;
day_to_int(wed) -> 3;
day_to_int(thu) -> 4;
day_to_int(fri) -> 5;
day_to_int(sat) -> 6;
day_to_int(sun) -> 7.

time_to_minutes({Hours, Minutes}) ->
   Hours * 60 + Minutes;
time_to_minutes({Hours, Minutes, _Seconds}) ->
   Hours * 60 + Minutes.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

get_day_of_year_test() ->
   ?assertEqual(62, get_dst_day_of_year({1,wed,mar}, 2010)).

check_test() ->
   Tz = {"Europe/Moscow",{"MSK","MSK"},{"MSD","MSD"},180,60,{last,sun,mar},{2,0},{last,sun,oct},{3,0}},
   ?assertEqual(is_not_in_dst, localtime_dst:check({{2010, 1, 1}, {10, 10, 0}}, Tz)),
   ?assertEqual(is_in_dst, check({{2010, 7, 8}, {10, 10, 0}}, Tz)),
   ?assertEqual(is_not_in_dst, check({{2010, 3, 28}, {1, 59, 0}}, Tz)),
   ?assertEqual(time_not_exists, check({{2010, 3, 28}, {2, 00, 0}}, Tz)),
   ?assertEqual(time_not_exists, check({{2010, 3, 28}, {2, 15, 0}}, Tz)),
   ?assertEqual(time_not_exists, check({{2010, 3, 28}, {2, 30, 0}}, Tz)),
   ?assertEqual(time_not_exists, check({{2010, 3, 28}, {2, 59, 0}}, Tz)),
   ?assertEqual(is_in_dst, check({{2010, 3, 28}, {3, 00, 0}}, Tz)),

   ?assertEqual(is_in_dst, check({{2010, 10, 31}, {1, 59, 0}}, Tz)),
   ?assertEqual(ambiguous_time, check({{2010, 10, 31}, {2, 00, 0}}, Tz)),
   ?assertEqual(ambiguous_time, check({{2010, 10, 31}, {2, 10, 0}}, Tz)),
   ?assertEqual(ambiguous_time, check({{2010, 10, 31}, {2, 30, 0}}, Tz)),
   ?assertEqual(ambiguous_time, check({{2010, 10, 31}, {2, 59, 0}}, Tz)),
   ?assertEqual(is_not_in_dst, check({{2010, 10, 31}, {3, 00, 0}}, Tz)),

   %% DST starts at hour 24; DST ends at hour 0:
   TzGaza = {"Asia/Gaza",{"EET","EET"},{"EEST","EEST"},120,60,{last,thu,mar},{24,0},{4,fri,sep},{0,0}},
   ?assertEqual(is_not_in_dst,   check({{2014, 3, 27}, {23, 59, 59}}, TzGaza)),
   ?assertEqual(time_not_exists, check({{2014, 3, 28}, { 0, 00, 00}}, TzGaza)),
   ?assertEqual(time_not_exists, check({{2014, 3, 28}, { 0, 59, 59}}, TzGaza)),
   ?assertEqual(is_in_dst,       check({{2014, 3, 28}, { 1, 00, 00}}, TzGaza)),
   ?assertEqual(is_in_dst,       check({{2014, 9, 25}, {22, 59, 59}}, TzGaza)),
   ?assertEqual(ambiguous_time,  check({{2014, 9, 25}, {23, 00, 00}}, TzGaza)),
   ?assertEqual(ambiguous_time,  check({{2014, 9, 25}, {23, 59, 59}}, TzGaza)),
   ?assertEqual(is_not_in_dst,   check({{2014, 9, 26}, { 0, 00, 00}}, TzGaza)),

   %% DST starts at hour 0; DST ends at hour 0.
   TzDamascus = {"Asia/Damascus",{"EET","EET"},{"EEST","EEST"},120,60,{last,fri,mar},{0,0},{last,fri,oct},{0,0}},
   ?assertEqual(is_not_in_dst,   check({{2014,  3, 27}, {23, 59, 59}}, TzDamascus)),
   ?assertEqual(time_not_exists, check({{2014,  3, 28}, { 0, 00, 00}}, TzDamascus)),
   ?assertEqual(time_not_exists, check({{2014,  3, 28}, { 0, 59, 59}}, TzDamascus)),
   ?assertEqual(is_in_dst,       check({{2014,  3, 28}, { 1, 00, 00}}, TzDamascus)),
   ?assertEqual(is_in_dst,       check({{2014, 10, 30}, {22, 59, 59}}, TzDamascus)),
   ?assertEqual(ambiguous_time,  check({{2014, 10, 30}, {23, 00, 00}}, TzDamascus)),
   ?assertEqual(ambiguous_time,  check({{2014, 10, 30}, {23, 59, 59}}, TzDamascus)),
   ?assertEqual(is_not_in_dst,   check({{2014, 10, 31}, { 0, 00, 00}}, TzDamascus)),

   %% DST ends before starts (southern hemisphere):
   TzMontevideo = {"America/Montevideo",{"UYT","UYT"},{"UYST","UYST"},-180,60,{1,sun,oct},{2,0},{2,sun,mar},{2,0}},
   ?assertEqual(is_in_dst,       check({{2014,  3, 09}, { 0, 59, 59}}, TzMontevideo)),
   ?assertEqual(ambiguous_time,  check({{2014,  3, 09}, { 1, 00, 00}}, TzMontevideo)),
   ?assertEqual(ambiguous_time,  check({{2014,  3, 09}, { 1, 59, 59}}, TzMontevideo)),
   ?assertEqual(is_not_in_dst,   check({{2014,  3, 09}, { 2, 00, 00}}, TzMontevideo)),
   ?assertEqual(is_not_in_dst,   check({{2014, 10, 05}, { 1, 59, 59}}, TzMontevideo)),
   ?assertEqual(time_not_exists, check({{2014, 10, 05}, { 2, 00, 00}}, TzMontevideo)),
   ?assertEqual(time_not_exists, check({{2014, 10, 05}, { 2, 59, 59}}, TzMontevideo)),
   ?assertEqual(is_in_dst,       check({{2014, 10, 05}, { 3, 00, 00}}, TzMontevideo)),

   true.

-endif.

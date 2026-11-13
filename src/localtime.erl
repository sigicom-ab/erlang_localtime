%% @author  Dmitry S. Melnikov (dmitryme@gmail.com)
%% @copyright 2010 Dmitry S. Melnikov

-module(localtime).

-author("Dmitry Melnikov <dmitryme@gmail.com>").

-include("tz_database.hrl").
-include("tz_index.hrl").

-export(
  [
     utc_to_local/2
     ,local_to_utc/2
     ,local_to_local/3
     ,local_to_local_dst/3
     ,tz_name/2
     ,tz_shift/2
     ,tz_shift/3
     ,get_timezone/1
     ,list_timezones/0
     ,adjust_datetime/2
     ,fmt_shift/1
  ]).

% utc_to_local(UtcDateTime, Timezone) -> LocalDateTime | [LocalDateTime, DstLocalDateTime] | {error, ErrDescr}
%  UtcDateTime = DateTime()
%  Timezone = String()
%  LocalDateTime = DateTime()
%  DstLocalDateTime = DateTime()
%  ErrDescr = atom(), unknown_tz
utc_to_local(UtcDateTime, Timezone) ->
   case maps:get(get_timezone(Timezone), ?tz_database, false) of
      false ->
         {error, unknown_tz};
      TzRule ->
         {Offset, _Name} = localtime_dst:utc_offset(UtcDateTime, TzRule),
         adjust_datetime(UtcDateTime, Offset)
   end.

% local_to_utc(LocalDateTime, Timezone) -> UtcDateTime | [UtcDateTime, DstUtcDateTime] | time_not_exists | {error, ErrDescr}
%  LocalDateTime = DateTime()
%  Timezone = String()
%  UtcDateTime = DateTime()
%  DstUtcDateTime = DateTime()
%  ErrDescr = atom(), unknown_tz
local_to_utc(LocalDateTime, Timezone) ->
   case maps:get(get_timezone(Timezone), ?tz_database, false) of
      false ->
         {error, unknown_tz};
      TzRule ->
         case localtime_dst:local_offsets(LocalDateTime, TzRule) of
            [] ->
               time_not_exists;
            [{Offset, _}] ->
               adjust_datetime(LocalDateTime, invert_shift(Offset));
            [{Offset1, _}, {Offset2, _} | _] ->
               [adjust_datetime(LocalDateTime, invert_shift(Offset1)),
                adjust_datetime(LocalDateTime, invert_shift(Offset2))]
         end
   end.

% local_to_local(LocalDateTime, TimezoneFrom, TimezoneTo) -> LocalDateTime | ambiguous | time_not_exists | {error, ErrDescr}
%  LocalDateTime = DateTime()
%  TimezoneFrom = String()
%  TimezoneTo = String()
%  ErrDescr = atom(), unknown_tz
local_to_local(LocalDateTime, TimezoneFrom, TimezoneTo) ->
   case local_to_utc(LocalDateTime, TimezoneFrom) of
      UtcDateTime = {{_,_,_},{_,_,_}} ->
         LocalDateTime2 = utc_to_local(UtcDateTime, TimezoneTo);
      [UtcDateTime, {{_,_,_},{_,_,_}}] ->
         LocalDateTime2 = utc_to_local(UtcDateTime, TimezoneTo);
      Res ->
         LocalDateTime2 = Res
   end,
   case LocalDateTime2 of
      [DateTimeToReturn, {{_,_,_},{_,_,_}}] ->
         DateTimeToReturn;
      Other ->
         Other
   end.

% local_to_local_dst(LocalDateTime, TimezoneFrom, TimezoneTo) -> LocalDateTime | ambiguous | time_not_exists | {error, ErrDescr}
%  LocalDateTime = DateTime()
%  TimezoneFrom = String()
%  TimezoneTo = String()
%  ErrDescr = atom(), unknown_tz
local_to_local_dst(LocalDateTime, TimezoneFrom, TimezoneTo) ->
   case local_to_utc(LocalDateTime, TimezoneFrom) of
      UtcDateTime = {{_,_,_},{_,_,_}} ->
         LocalDateTime2 = utc_to_local(UtcDateTime, TimezoneTo);
      [{{_,_,_},{_,_,_}}, UtcDateTime] ->
         LocalDateTime2 = utc_to_local(UtcDateTime, TimezoneTo);
      Res ->
         LocalDateTime2 = Res
   end,
   case LocalDateTime2 of
      [{{_,_,_},{_,_,_}}, DateTimeToReturn] ->
         DateTimeToReturn;
      Other ->
         Other
   end.

% tz_name(DateTime(), Timezone) -> {Abbr, Name} | {{StdAbbr, StdName}, {DstAbbr, DstName}} | unable_to_detect | {error, ErrDesc}
%  Timezone = String()
%  Abbr = String()
%  Name = String()
%  StdAbbr = String()
%  StdName = String()
%  DstAbbr = String()
%  DstName = String()
%  ErrDesc = atom(), unknown_tz
tz_name(LocalDateTime, Timezone) ->
   case maps:get(get_timezone(Timezone), ?tz_database, false) of
      false ->
         {error, unknown_tz};
      TzRule ->
         case localtime_dst:local_offsets(LocalDateTime, TzRule) of
            [] -> unable_to_detect;
            [{_, Name}] -> Name;
            [{_, Name1}, {_, Name2} | _] -> {Name1, Name2}
         end
   end.

% tz_shift(LocalDateTime, Timezone) ->  Shift | {Shift, DstSift} | unable_to_detect | {error, ErrDesc}
%  returns time shift from GMT
%  LocalDateTime = DateTime()
%  Timezone = String()
%  Shift = DstShift = {Sign, Hours, Minutes}
%  Sign = term(), '+', '-'
%  Hours = Minutes = Integer(),
%  {Shift, DstShift} - returns, when shift is ambiguous
%  ErrDesc = atom(), unknown_tz
tz_shift(LocalDateTime, Timezone) ->
   case maps:get(get_timezone(Timezone), ?tz_database, false) of
      false ->
         {error, unknown_tz};
      TzRule ->
         case localtime_dst:local_offsets(LocalDateTime, TzRule) of
            [] -> unable_to_detect;
            [{Offset, _}] -> fmt_min(Offset);
            [{Offset1, _}, {Offset2, _} | _] -> {fmt_min(Offset1), fmt_min(Offset2)}
         end
   end.

% the same as tz_shift/2, but calculates time difference between two local timezones
tz_shift(LocalDateTime, TimezoneFrom, TimezoneTo) ->
   F = fun() ->
      FromShift = fmt_shift(tz_shift(LocalDateTime, TimezoneFrom)),
      DateTimeTo = localtime:local_to_local(LocalDateTime, TimezoneFrom, TimezoneTo),
      ToShift = fmt_shift(tz_shift(DateTimeTo, TimezoneTo)),
      fmt_min(ToShift-FromShift)
   end,
   try F()
   catch
      _:Err ->
         Err
   end.

adjust_datetime(DateTime, Minutes) ->
   Seconds = calendar:datetime_to_gregorian_seconds(DateTime) + Minutes * 60,
   calendar:gregorian_seconds_to_datetime(Seconds).

get_timezone(TimeZone) ->
    get_timezone_inner(TimeZone).

list_timezones() ->
    dict:fetch_keys(?tz_index).

% =======================================================================
% privates
% =======================================================================

invert_shift(Minutes) ->
   -Minutes.

fmt_min(Shift) when Shift < 0 ->
   {'-', abs(Shift) div 60, abs(Shift) rem 60};
fmt_min(Shift) ->
   {'+', Shift div 60, Shift rem 60}.

fmt_shift({'+', H, M}) ->
   H * 60 + M;
fmt_shift({'-', H, M}) ->
   -(H * 60 + M);
fmt_shift(0) ->
   0;
fmt_shift(Any) ->
   throw(Any).

tr_char(String, From, To) ->
   case string:chr(String, From) of
      0 -> String; % Optimize for String does not contain From.
      _ -> tr_char(String, From, To, [])
   end.
tr_char([], _From, _To, Acc) ->
   lists:reverse(Acc);
tr_char([H|T], From, To, Acc) ->
   case H of
      From -> tr_char(T, From, To, [To|Acc]);
      _ -> tr_char(T, From, To, [H|Acc])
   end.

-define(SPACE_CHAR, 32).
get_timezone_inner(TimeZone) when is_binary(TimeZone) ->
    get_timezone_inner(erlang:binary_to_list(TimeZone));
get_timezone_inner(TimeZone) when is_list(TimeZone) ->
   TimeZoneNoSpaces = tr_char(TimeZone, ?SPACE_CHAR, $_),
   case dict:find(TimeZoneNoSpaces, ?tz_index)  of
      error ->
         TimeZoneNoSpaces;
      {ok, [TZName | _]} ->
            TZName
   end;
get_timezone_inner(_) ->
    throw({error, "Timezone should be string/binary"}).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

tr_char_test() ->
   ?assertEqual("ABCDE", tr_char("ABCDE", ?SPACE_CHAR, $_)),
   ?assertEqual("AB_DE", tr_char("AB DE", ?SPACE_CHAR, $_)),
   ?assertEqual("A_C_E", tr_char("A C E", ?SPACE_CHAR, $_)).

get_timezone_test() ->
   ?assertEqual("America/Los_Angeles", get_timezone("America/Los Angeles")).

tz_shift_test() ->
   ?assertEqual({'+',3,0}, tz_shift({{2014,1,1},{12,0,0}}, "America/Los_Angeles", "America/New_York")).

-endif. % TEST

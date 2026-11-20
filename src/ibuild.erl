%% @author  Dmitry S. Melnikov (dmitryme@gmail.com)
%% @copyright 2010 Dmitry S. Melnikov

-module(ibuild).

-export([build_index/0, main/1]).

-include("tz_database.hrl").

build_tzlist(TzName, Name, Dict) ->
   maps:update_with(Name, fun(TzNames) -> TzNames ++ [TzName] end, [TzName], Dict).

build_index() ->
   F = fun({TzName,{Name,_},{DName,_},_,_,_,_,_,_}, Acc) ->
         NewDict = build_tzlist(TzName, Name, Acc),
         build_tzlist(TzName, DName, NewDict);
      ({TzName,{Name,_},undef,_,_,_,_,_,_}, Acc) ->
         build_tzlist(TzName, Name, Acc)
   end,
   % Database order (sorted by zone name) decides which zone an abbreviation
   % resolves to, so fold over the zones sorted rather than in map order.
   Zones = [Tz || {_, Tz} <- lists:sort(maps:to_list(?tz_database))],
   I0 = lists:foldl(F, #{}, Zones),
   % An abbreviation that is also a zone name (e.g. "CET", "UTC") must resolve
   % to that zone, not to the first zone using the abbreviation.
   I = maps:map(fun(Abbr, TzNames) ->
                      case lists:member(Abbr, TzNames) of
                         true -> [Abbr | lists:delete(Abbr, TzNames)];
                         false -> TzNames
                      end
                end, I0),
   {ok, File} = file:open("tz_index.hrl", [write]),
   io:fwrite(File, "-define(tz_index, ~p).\n", [I]),
   file:close(File).

%% So this can be run from escript:
main(_Args) ->
   build_index().

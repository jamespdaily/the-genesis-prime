-module(topology_ffi).
-export([monotonic_microseconds/0, enable_scheduler_wall_time/0,
         set_high_priority/0, plain_arguments/0,
         scheduler_wall_time/0, set_schedulers_online/1, core_count/0,
         process_memory_words/1, message_queue_length/1, new_counter/0,
         increment/1, counter_value/1, put_spawn_list/2, get_spawn_list/1,
         erase_spawn_list/1, table_new/0, table_memory_words/1,
         table_insert/3, table_delete/2, table_delete_owned/3,
         table_lookup/2, table_cell_rows/3]).

monotonic_microseconds() ->
    erlang:monotonic_time(microsecond).

enable_scheduler_wall_time() ->
    erlang:system_flag(scheduler_wall_time, true),
    nil.

set_high_priority() ->
    process_flag(priority, high),
    nil.

plain_arguments() ->
    [unicode:characters_to_binary(Argument) || Argument <- init:get_plain_arguments()].

%% The counters of the normal schedulers that are online, as
%% `{SchedulerId, Busy, Total}`, in microseconds. The runtime lists its dirty
%% schedulers after the normal ones, and takes the highest-numbered normal
%% schedulers offline first, so the ids up to the number online are the ones
%% that run processes. Crashes when accounting has not been enabled.
scheduler_wall_time() ->
    Online = erlang:system_info(schedulers_online),
    [{Id, native_to_microseconds(Busy), native_to_microseconds(Total)}
     || {Id, Busy, Total} <- erlang:statistics(scheduler_wall_time),
        Id =< Online].

native_to_microseconds(Native) ->
    erlang:convert_time_unit(Native, native, microsecond).

set_schedulers_online(Count) ->
    erlang:system_flag(schedulers_online, Count),
    nil.

%% The schedulers the runtime started with: one per core unless it was
%% started with another count.
core_count() ->
    erlang:system_info(schedulers).

process_memory_words(Pid) ->
    case erlang:process_info(Pid, memory) of
        {memory, Bytes} -> {ok, Bytes div erlang:system_info(wordsize)};
        undefined -> {error, nil}
    end.

message_queue_length(Pid) ->
    case erlang:process_info(Pid, message_queue_len) of
        {message_queue_len, Length} -> {ok, Length};
        undefined -> {error, nil}
    end.

new_counter() ->
    counters:new(1, [write_concurrency]).

increment(Counter) ->
    counters:add(Counter, 1, 1),
    nil.

counter_value(Counter) ->
    counters:get(Counter, 1).

put_spawn_list(Key, SpawnList) ->
    persistent_term:put({topology_spawn_list, Key}, SpawnList),
    nil.

get_spawn_list(Key) ->
    persistent_term:get({topology_spawn_list, Key}).

erase_spawn_list(Key) ->
    persistent_term:erase({topology_spawn_list, Key}),
    nil.

table_new() ->
    ets:new(topology_units, [ordered_set, public, {read_concurrency, true},
                             {write_concurrency, true}]).

table_memory_words(Table) ->
    ets:info(Table, memory).

table_insert(Table, Key, Row) ->
    ets:insert(Table, {Key, Row}),
    nil.

table_delete(Table, Key) ->
    ets:delete(Table, Key),
    nil.

%% Deletes the row under `Key` only when the process `Pid` owns it, in one
%% step, so a row a rebuilt unit has just written is never removed. A row is
%% `{row, UnitId, Kind, Position, Owner, Connection}` and its owner is a
%% subject, `{subject, Pid, Tag}`.
table_delete_owned(Table, Key, Pid) ->
    Owned = {'=:=', {element, 2, {element, 5, '$1'}}, {const, Pid}},
    ets:select_delete(Table, [{{Key, '$1'}, [Owned], [true]}]),
    nil.

table_lookup(Table, Key) ->
    case ets:lookup(Table, Key) of
        [{_, Row}] -> {ok, Row};
        [] -> {error, nil}
    end.

%% Every row filed under one cell: the keys `{cell_key, X, Y, UnitId}` share
%% their first three elements, so the ordered set reads only that range.
table_cell_rows(Table, X, Y) ->
    ets:select(Table, [{{{cell_key, X, Y, '_'}, '$1'}, [], ['$1']}]).

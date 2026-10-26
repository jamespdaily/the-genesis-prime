-module(topology_ffi).
-export([monotonic_microseconds/0, enable_scheduler_wall_time/0,
         set_schedulers_online/1, core_count/0, new_counter/0, increment/1,
         counter_value/1, put_spawn_list/2, get_spawn_list/1,
         erase_spawn_list/1, table_new/0, table_memory_words/1]).

monotonic_microseconds() ->
    erlang:error(body_in_the_build_commit).

enable_scheduler_wall_time() ->
    erlang:error(body_in_the_build_commit).

set_schedulers_online(_Count) ->
    erlang:error(body_in_the_build_commit).

core_count() ->
    erlang:error(body_in_the_build_commit).

new_counter() ->
    erlang:error(body_in_the_build_commit).

increment(_Counter) ->
    erlang:error(body_in_the_build_commit).

counter_value(_Counter) ->
    erlang:error(body_in_the_build_commit).

put_spawn_list(_Key, _SpawnList) ->
    erlang:error(body_in_the_build_commit).

get_spawn_list(_Key) ->
    erlang:error(body_in_the_build_commit).

erase_spawn_list(_Key) ->
    erlang:error(body_in_the_build_commit).

table_new() ->
    erlang:error(body_in_the_build_commit).

table_memory_words(_Table) ->
    erlang:error(body_in_the_build_commit).

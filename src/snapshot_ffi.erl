-module(snapshot_ffi).
-export([enable_scheduler_wall_time/0, scheduler_times/0, process_count/0,
         port_count/0, run_queue_length/0, heap_and_queue/1]).

%% Starts the runtime's scheduler time accounting, which changes nothing when
%% it is already on.
-spec enable_scheduler_wall_time() -> nil.
enable_scheduler_wall_time() ->
    erlang:system_flag(scheduler_wall_time, true),
    nil.

%% The time the normal schedulers that are online ran processes and the time
%% they existed, each summed, as `{Busy, Total}` in the runtime's native time
%% unit, since accounting started. The runtime takes the highest-numbered
%% normal schedulers offline first, so the ids up to the number online are
%% the ones that run processes. Crashes when accounting is off.
-spec scheduler_times() -> {non_neg_integer(), non_neg_integer()}.
scheduler_times() ->
    Online = erlang:system_info(schedulers_online),
    lists:foldl(fun({Id, Busy, Total}, {BusySum, TotalSum}) when Id =< Online ->
                        {BusySum + Busy, TotalSum + Total};
                   (_Offline, Sums) ->
                        Sums
                end,
                {0, 0},
                erlang:statistics(scheduler_wall_time)).

-spec process_count() -> non_neg_integer().
process_count() ->
    erlang:system_info(process_count).

-spec port_count() -> non_neg_integer().
port_count() ->
    erlang:system_info(port_count).

%% The processes waiting for a scheduler.
-spec run_queue_length() -> non_neg_integer().
run_queue_length() ->
    erlang:statistics(run_queue).

%% `total_heap_size` in words and `message_queue_len` of a process, read in
%% one call, or an error when it is not alive.
-spec heap_and_queue(pid()) -> {ok, {non_neg_integer(), non_neg_integer()}} | {error, nil}.
heap_and_queue(Pid) ->
    case erlang:process_info(Pid, [total_heap_size, message_queue_len]) of
        [{total_heap_size, HeapWords}, {message_queue_len, Queue}] ->
            {ok, {HeapWords, Queue}};
        undefined ->
            {error, nil}
    end.

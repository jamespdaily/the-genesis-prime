%% What the fight load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_fight): a process's reduction count, a counter the runtime
%% keeps, so nothing is traced, and the suspension of a process for the planted run in
%% which the map falls behind.
-module(load_fight_ffi).
-export([reductions/1, suspend/1, resume/1]).

%% The reductions the process has run so far, 0 for a process that ended.
reductions(Pid) ->
    case process_info(Pid, reductions) of
        {reductions, Count} -> Count;
        undefined -> 0
    end.

%% Suspends the process: it takes no message and runs nothing until it is resumed; the
%% messages sent to it wait in its mailbox.
suspend(Pid) ->
    erlang:suspend_process(Pid),
    nil.

%% Resumes the process once for each time it was suspended.
resume(Pid) ->
    erlang:resume_process(Pid),
    nil.

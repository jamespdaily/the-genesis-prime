%% What the fight load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_fight): a process's reduction count, a counter the runtime
%% keeps, so nothing is traced.
-module(load_fight_ffi).
-export([reductions/1]).

%% The reductions the process has run so far, 0 for a process that ended.
reductions(Pid) ->
    case process_info(Pid, reductions) of
        {reductions, Count} -> Count;
        undefined -> 0
    end.

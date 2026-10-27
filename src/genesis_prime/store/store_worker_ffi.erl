%% Runs a function and turns the one exit that says a process is not running
%% into an error, for the store's workers: OTP's supervisor:start_child/2 and
%% pgo's checkout exit with {noproc, _} when the supervisor or the pool is not
%% running, where an answer of "not running" is wanted. Any other exit passes.
-module(store_worker_ffi).
-export([unless_not_running/1]).

unless_not_running(Run) ->
    try {ok, Run()}
    catch exit:{noproc, _} -> {error, nil}
    end.

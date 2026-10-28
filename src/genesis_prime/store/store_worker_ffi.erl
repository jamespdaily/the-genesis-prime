%% Runs a function and turns the one exit that says the database pool is not
%% running into an error, where an answer of "not running" is wanted. Any other
%% exit, including a noproc from elsewhere, passes.
-module(store_worker_ffi).
-export([unless_pool_not_running/1]).

%% pgo's checkout exits with {noproc, {pgo_pool, checkout, _}} when the pool's
%% process is not running (pgo_pool.erl).
unless_pool_not_running(Run) ->
    try {ok, Run()}
    catch exit:{noproc, {pgo_pool, checkout, _}} -> {error, nil}
    end.

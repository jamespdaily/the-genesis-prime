%% Runs a function and turns the one exit that says a process the store needs
%% is not running into an error, where an answer of "not running" is wanted.
%% Any other exit, including a noproc from elsewhere, passes.
-module(store_worker_ffi).
-export([unless_supervisor_not_running/1, unless_pool_not_running/1]).

%% OTP's supervisor:start_child/2 is gen_server:call(Supervisor, _, infinity),
%% which exits with {noproc, {gen_server, call, _}} when no process holds the
%% name.
unless_supervisor_not_running(Run) ->
    try {ok, Run()}
    catch exit:{noproc, {gen_server, call, _}} -> {error, nil}
    end.

%% pgo's checkout exits with {noproc, {pgo_pool, checkout, _}} when the pool's
%% process is not running (pgo_pool.erl).
unless_pool_not_running(Run) ->
    try {ok, Run()}
    catch exit:{noproc, {pgo_pool, checkout, _}} -> {error, nil}
    end.

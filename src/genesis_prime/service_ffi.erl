%% Runs a function and turns the one exit that says a supervisor is not
%% running into an error, where an answer of "not running" is wanted. Any
%% other exit, including a noproc from elsewhere, passes.
-module(service_ffi).
-export([unless_supervisor_not_running/1]).

%% OTP's supervisor:start_child/2 is gen_server:call(Supervisor, _, infinity),
%% which exits with {noproc, {gen_server, call, _}} when no process holds the
%% name.
unless_supervisor_not_running(Run) ->
    try {ok, Run()}
    catch exit:{noproc, {gen_server, call, _}} -> {error, nil}
    end.

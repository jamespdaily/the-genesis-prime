%% Runs a function and turns the exits that say a supervisor is not running
%% into an error, where an answer of "not running" is wanted. Any other exit,
%% including a noproc from elsewhere, passes.
-module(genesis_prime_service_ffi).
-export([unless_supervisor_not_running/1]).

%% OTP's supervisor:start_child/2 is gen_server:call(Supervisor, _, infinity).
%% It exits with {noproc, {gen_server, call, _}} when no process holds the
%% name, and with {shutdown, {gen_server, call, _}} when the supervisor ends
%% with the reason shutdown while the call waits in its mailbox, as it does for
%% a call made while the supervisor stops its children.
unless_supervisor_not_running(Run) ->
    try {ok, Run()}
    catch
        exit:{noproc, {gen_server, call, _}} -> {error, nil};
        exit:{shutdown, {gen_server, call, _}} -> {error, nil}
    end.

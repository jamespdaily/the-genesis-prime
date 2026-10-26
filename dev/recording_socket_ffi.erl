-module(recording_socket_ffi).
-export([hand_over/2, send_at_once/1]).

%% The two socket calls of dev/genesis_prime/recording/listener.gleam that
%% answer with a bare `ok`, which a Gleam `Result(Nil, mug.Error)` reads as
%% {ok, nil}. A failure is {error, Reason} with Reason the operating system's
%% code as an atom, which is how `mug.Error` is written (`closed`, `einval`).
-type failure() :: {error, inet:posix() | closed}.

%% Makes Pid the owner of the socket. Only the socket's current owner may call
%% it.
-spec hand_over(gen_tcp:socket(), pid()) -> {ok, nil} | failure().
hand_over(Socket, Pid) ->
    nil_when_ok(gen_tcp:controlling_process(Socket, Pid)).

%% Turns off Nagle's delay on the socket.
-spec send_at_once(gen_tcp:socket()) -> {ok, nil} | failure().
send_at_once(Socket) ->
    nil_when_ok(inet:setopts(Socket, [{nodelay, true}])).

nil_when_ok(ok) -> {ok, nil};
nil_when_ok({error, _} = Failure) -> Failure.

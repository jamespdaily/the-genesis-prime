-module(recording_socket_ffi).
-export([hand_over/2, send_at_once/1, local_address/1, finish_sending/1]).

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

%% The socket's own address and port as text, the way the server writes a
%% peer's (`genesis_prime_socket_ffi:peer/1`), so a connection's address here
%% is the peer address the server at the other end sees.
-spec local_address(gen_tcp:socket()) -> {ok, binary()} | failure().
local_address(Socket) ->
    case inet:sockname(Socket) of
        {ok, {Address, Port}} ->
            {ok, iolist_to_binary([inet:ntoa(Address), ":", integer_to_list(Port)])};
        {error, _} = Failure ->
            Failure
    end.

%% Closes the sending side of the socket only: the other side reads the end of
%% the stream and the socket still receives what it sends back.
-spec finish_sending(gen_tcp:socket()) -> {ok, nil} | failure().
finish_sending(Socket) ->
    nil_when_ok(gen_tcp:shutdown(Socket, write)).

nil_when_ok(ok) -> {ok, nil};
nil_when_ok({error, _} = Failure) -> Failure.

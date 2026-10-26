-module(freezing_relay_ffi).
-export([start/3, opened/1, frozen_connection/1]).

%% The Gleam types of test/freezing_relay.gleam:
%%   Relay(host, port, counters)  is {relay, Host, Port, Counters}
%%   Failure: NotListening(code) is {not_listening, Code}, with Code the
%%   operating system's error code as a binary.
%% Counters is one atomics array of 3 slots: 1 holds how many connections the
%% relay has accepted, 2 is 1 once a connection has been frozen, and 3 holds
%% the number of the connection that was frozen.
-type relay() :: {relay, binary(), inet:port_number(), atomics:atomics_ref()}.
-type failure() :: {not_listening, binary()}.

-define(OPENED, 1).
-define(FROZEN, 2).
-define(FROZEN_CONNECTION, 3).

%% The address family of a host given as text, the loopback address of that
%% family and the same address as text. A host with a colon is IPv6.
family(Host) ->
    case binary:match(Host, <<":">>) of
        nomatch -> {inet, {127, 0, 0, 1}, <<"127.0.0.1">>};
        _ -> {inet6, {0, 0, 0, 0, 0, 0, 0, 1}, <<"::1">>}
    end.

%% Listens on a free port of the target's loopback family and starts an
%% acceptor, linked to the caller, that passes each connection through to the
%% target. The first connection whose bytes to the target contain Statement
%% (compared without regard to case) is passed that statement and then frozen.
-spec start(binary(), inet:port_number(), binary()) -> {ok, relay()} | {error, failure()}.
start(TargetHost, TargetPort, Statement) ->
    {Family, Loopback, LoopbackText} = family(TargetHost),
    Options = [Family, {ip, Loopback}, binary, {active, false}, {reuseaddr, true}],
    case gen_tcp:listen(0, Options) of
        {ok, Listen} ->
            {ok, Port} = inet:port(Listen),
            Counters = atomics:new(3, []),
            Acceptor = spawn_link(fun() ->
                accept(Listen, {target, TargetHost, TargetPort}, lower(Statement), Counters)
            end),
            ok = gen_tcp:controlling_process(Listen, Acceptor),
            {ok, {relay, LoopbackText, Port, Counters}};
        {error, Reason} ->
            {error, {not_listening, atom_to_binary(Reason)}}
    end.

%% How many connections the relay has accepted.
-spec opened(atomics:atomics_ref()) -> integer().
opened(Counters) ->
    atomics:get(Counters, ?OPENED).

%% The number, from 1, of the connection that was frozen, or none.
-spec frozen_connection(atomics:atomics_ref()) -> {some, integer()} | none.
frozen_connection(Counters) ->
    case atomics:get(Counters, ?FROZEN) of
        1 -> {some, atomics:get(Counters, ?FROZEN_CONNECTION)};
        0 -> none
    end.

%% Accepts connections until the listening socket closes, which happens when
%% this process ends. Each connection gets a process of its own, linked to the
%% acceptor so it ends with it.
accept(Listen, Target, Statement, Counters) ->
    case gen_tcp:accept(Listen) of
        {ok, Client} ->
            Number = atomics:add_get(Counters, ?OPENED, 1),
            Pipe = spawn_link(fun() ->
                receive
                    handed_over -> pipe(Client, Target, Statement, Counters, Number)
                end
            end),
            ok = gen_tcp:controlling_process(Client, Pipe),
            Pipe ! handed_over,
            accept(Listen, Target, Statement, Counters);
        {error, _Closed} ->
            ok
    end.

pipe(Client, {target, TargetHost, TargetPort}, Statement, Counters, Number) ->
    {Family, _, _} = family(TargetHost),
    Address = case inet:parse_address(binary_to_list(TargetHost)) of
        {ok, Ip} -> Ip;
        {error, einval} -> binary_to_list(TargetHost)
    end,
    case gen_tcp:connect(Address, TargetPort, [Family, binary, {active, false}]) of
        {ok, Target} ->
            ok = inet:setopts(Client, [{active, true}]),
            ok = inet:setopts(Target, [{active, true}]),
            pass(Client, Target, Statement, Counters, Number);
        {error, _} ->
            gen_tcp:close(Client)
    end.

%% Passes bytes both ways until either side closes. When the bytes to the
%% target hold the statement and no connection has been frozen yet, they are
%% passed on and this connection freezes.
pass(Client, Target, Statement, Counters, Number) ->
    receive
        {tcp, Client, Data} ->
            _ = gen_tcp:send(Target, Data),
            case binary:match(lower(Data), Statement) =/= nomatch
                andalso atomics:compare_exchange(Counters, ?FROZEN, 0, 1) =:= ok of
                true ->
                    atomics:put(Counters, ?FROZEN_CONNECTION, Number),
                    frozen(Client, Target);
                false ->
                    pass(Client, Target, Statement, Counters, Number)
            end;
        {tcp, Target, Data} ->
            _ = gen_tcp:send(Client, Data),
            pass(Client, Target, Statement, Counters, Number);
        {tcp_closed, _} ->
            close(Client, Target);
        {tcp_error, _, _} ->
            close(Client, Target)
    end.

%% Neither side hears from the other, and neither socket is closed. Only the
%% client's own close ends it, which closes the target as the relay does for
%% any connection, so Postgres rolls back what the frozen connection had begun.
frozen(Client, Target) ->
    receive
        {tcp, _, _} ->
            frozen(Client, Target);
        {tcp_closed, Client} ->
            close(Client, Target);
        {tcp_error, Client, _} ->
            close(Client, Target);
        {tcp_closed, Target} ->
            frozen(Client, Target);
        {tcp_error, Target, _} ->
            frozen(Client, Target)
    end.

close(Client, Target) ->
    gen_tcp:close(Client),
    gen_tcp:close(Target).

lower(Bytes) ->
    << <<(case Byte of
              _ when Byte >= $A, Byte =< $Z -> Byte + 32;
              _ -> Byte
          end)>> || <<Byte>> <= Bytes >>.

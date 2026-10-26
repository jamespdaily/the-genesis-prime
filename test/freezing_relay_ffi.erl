-module(freezing_relay_ffi).
-export([start/3, opened/1, frozen_connection/1]).

%% The Gleam types of test/freezing_relay.gleam:
%%   Relay(host, port, counters)  is {relay, Host, Port, Counters}
%%   Freeze: Before(Statement) is {before, Statement}, After(Statement) is
%%   {'after', Statement}
%%   Failure: NotListening(code) is {not_listening, Code}, with Code the
%%   operating system's error code as a binary.
%% Counters is one atomics array of 3 slots: 1 holds how many connections the
%% relay has accepted, 2 is 1 once a connection has been frozen, and 3 holds
%% the number of the connection that was frozen.
-type freeze() :: {before, binary()} | {'after', binary()}.
-type relay() :: {relay, binary(), inet:port_number(), atomics:atomics_ref()}.
-type failure() :: {not_listening, binary()}.

-define(OPENED, 1).
-define(FROZEN, 2).
-define(FROZEN_CONNECTION, 3).

%% What a connection's reader has: the bytes of the client's messages that are
%% not yet a whole message, whether the startup packet has been read, and the
%% text of the last statement the client parsed since its last Sync.
-record(reader, {phase = startup, buffer = <<>>, statement = none}).

%% The address family of a host given as text, the loopback address of that
%% family and the same address as text. A host with a colon is IPv6.
family(Host) ->
    case binary:match(Host, <<":">>) of
        nomatch -> {inet, {127, 0, 0, 1}, <<"127.0.0.1">>};
        _ -> {inet6, {0, 0, 0, 0, 0, 0, 0, 1}, <<"::1">>}
    end.

%% Listens on a free port of the target's loopback family and starts an
%% acceptor, linked to the caller, that passes each connection through to the
%% target.
-spec start(binary(), inet:port_number(), freeze()) -> {ok, relay()} | {error, failure()}.
start(TargetHost, TargetPort, Freeze) ->
    {Family, Loopback, LoopbackText} = family(TargetHost),
    Options = [Family, {ip, Loopback}, binary, {active, false}, {reuseaddr, true}],
    case gen_tcp:listen(0, Options) of
        {ok, Listen} ->
            {ok, Port} = inet:port(Listen),
            Counters = atomics:new(3, []),
            Acceptor = spawn_link(fun() ->
                accept(Listen, {TargetHost, TargetPort}, normalised(Freeze), Counters)
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

normalised({When, Statement}) ->
    {When, lower(Statement)}.

%% Accepts connections until the listening socket closes, which happens when
%% this process ends. Each connection gets a process of its own, linked to the
%% acceptor so it ends with it.
accept(Listen, Target, Freeze, Counters) ->
    case gen_tcp:accept(Listen) of
        {ok, Client} ->
            Number = atomics:add_get(Counters, ?OPENED, 1),
            Pipe = spawn_link(fun() ->
                receive
                    handed_over -> pipe(Client, Target, Freeze, Counters, Number)
                end
            end),
            ok = gen_tcp:controlling_process(Client, Pipe),
            Pipe ! handed_over,
            accept(Listen, Target, Freeze, Counters);
        {error, _Closed} ->
            ok
    end.

pipe(Client, {TargetHost, TargetPort}, Freeze, Counters, Number) ->
    {Family, _, _} = family(TargetHost),
    Address = case inet:parse_address(binary_to_list(TargetHost)) of
        {ok, Ip} -> Ip;
        {error, einval} -> binary_to_list(TargetHost)
    end,
    case gen_tcp:connect(Address, TargetPort, [Family, binary, {active, false}]) of
        {ok, Target} ->
            ok = inet:setopts(Client, [{active, true}]),
            ok = inet:setopts(Target, [{active, true}]),
            pass(Client, Target, #reader{}, {Freeze, Counters, Number});
        {error, _} ->
            gen_tcp:close(Client)
    end.

%% Passes the client's messages to the target whole, one at a time, and the
%% target's bytes to the client, until either side closes or the connection
%% freezes.
pass(Client, Target, Reader, Context) ->
    receive
        {tcp, Client, Data} ->
            Buffer = <<(Reader#reader.buffer)/binary, Data/binary>>,
            case read(Buffer, Reader#reader{buffer = <<>>}, Context, []) of
                {more, Forward, Next} ->
                    _ = gen_tcp:send(Target, Forward),
                    pass(Client, Target, Next, Context);
                {freeze, Forward} ->
                    _ = gen_tcp:send(Target, Forward),
                    frozen(Client, Target)
            end;
        {tcp, Target, Data} ->
            _ = gen_tcp:send(Client, Data),
            pass(Client, Target, Reader, Context);
        {tcp_closed, _} ->
            close(Client, Target);
        {tcp_error, _, _} ->
            close(Client, Target)
    end.

%% Reads the whole messages of the buffer, giving what is to be sent on and
%% the reader left with the bytes of a message that is not whole yet. The
%% startup packet is a length of 4 bytes and its body; every message after it
%% is a type byte, a length of 4 bytes that counts itself, and the body.
read(Buffer, Reader = #reader{phase = startup}, Context, Forward) ->
    case Buffer of
        <<Length:32, _/binary>> when byte_size(Buffer) >= Length ->
            <<Packet:Length/binary, Rest/binary>> = Buffer,
            read(Rest, Reader#reader{phase = running}, Context, [Forward, Packet]);
        _ ->
            {more, Forward, Reader#reader{buffer = Buffer}}
    end;
read(Buffer, Reader, Context, Forward) ->
    case Buffer of
        <<Type, Length:32, _/binary>> when byte_size(Buffer) >= Length + 1 ->
            Size = Length + 1,
            <<Message:Size/binary, Rest/binary>> = Buffer,
            message(Type, Message, Rest, Reader, Context, Forward);
        _ ->
            {more, Forward, Reader#reader{buffer = Buffer}}
    end.

%% One whole message. A Parse names a statement; the Sync that ends an
%% exchange resets it. The first connection to meet the freeze is frozen: at a
%% Parse of the statement the relay holds it back, and at the Sync that ends
%% the exchange of the statement the relay has passed it.
message($P, Message, Rest, Reader, Context = {{Moment, Wanted}, _, _}, Forward) ->
    Statement = lower(parsed_statement(Message)),
    Meets = binary:match(Statement, Wanted) =/= nomatch,
    case Moment =:= before andalso Meets andalso freeze_first(Context) of
        true ->
            {freeze, Forward};
        false ->
            read(Rest, Reader#reader{statement = Statement}, Context, [Forward, Message])
    end;
message($S, Message, Rest, Reader = #reader{statement = Statement},
        Context = {{Moment, Wanted}, _, _}, Forward) ->
    Meets = Statement =/= none andalso binary:match(Statement, Wanted) =/= nomatch,
    case Moment =:= 'after' andalso Meets andalso freeze_first(Context) of
        true ->
            {freeze, [Forward, Message]};
        false ->
            read(Rest, Reader#reader{statement = none}, Context, [Forward, Message])
    end;
message(_Type, Message, Rest, Reader, Context, Forward) ->
    read(Rest, Reader, Context, [Forward, Message]).

%% The text of the statement of a Parse message: after the type, the length,
%% the name of the statement and its end, up to the end of the text.
parsed_statement(<<$P, _Length:32, Body/binary>>) ->
    [_Name, Rest] = binary:split(Body, <<0>>),
    [Statement | _] = binary:split(Rest, <<0>>),
    Statement.

%% True for the first connection to ask, which is then the frozen one.
freeze_first({_, Counters, Number}) ->
    case atomics:compare_exchange(Counters, ?FROZEN, 0, 1) of
        ok ->
            atomics:put(Counters, ?FROZEN_CONNECTION, Number),
            true;
        _ ->
            false
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

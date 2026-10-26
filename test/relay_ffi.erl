-module(relay_ffi).
-export([refusing/2, forward/1]).

%% The Gleam types of test/relay.gleam:
%%   Target(host, port)         is {target, Host, Port}
%%   Relay(host, port, target)  is {relay, Host, Port, Target}
%%   Failure: AddressInUse is address_in_use, NotListening(code) is
%%   {not_listening, Code}, with Code the operating system's error code as a
%%   binary.
-type target() :: {target, binary(), inet:port_number()}.
-type relay() :: {relay, binary(), inet:port_number(), target()}.
-type failure() :: address_in_use | {not_listening, binary()}.

%% The address family of a host given as text, the loopback address of that
%% family and the same address as text. A host with a colon is IPv6.
family(Host) ->
    case binary:match(Host, <<":">>) of
        nomatch -> {inet, {127, 0, 0, 1}, <<"127.0.0.1">>};
        _ -> {inet6, {0, 0, 0, 0, 0, 0, 0, 1}, <<"::1">>}
    end.

%% Chooses a free port on the loopback of the target's family by listening on
%% port 0 and closing the socket again, so nothing listens on the port that is
%% returned.
-spec refusing(binary(), inet:port_number()) -> {ok, relay()} | {error, failure()}.
refusing(TargetHost, TargetPort) ->
    {Family, Loopback, LoopbackText} = family(TargetHost),
    case gen_tcp:listen(0, [Family, {ip, Loopback}]) of
        {ok, Listen} ->
            {ok, Port} = inet:port(Listen),
            ok = gen_tcp:close(Listen),
            {ok, {relay, LoopbackText, Port, {target, TargetHost, TargetPort}}};
        {error, Reason} ->
            {error, failure(Reason)}
    end.

%% Listens on the relay's port and starts an acceptor, linked to the caller, that
%% passes each connection through to the target.
-spec forward(relay()) -> {ok, nil} | {error, failure()}.
forward({relay, Host, Port, {target, TargetHost, TargetPort}}) ->
    {Family, Loopback, _} = family(Host),
    Options = [Family, {ip, Loopback}, binary, {active, false}, {reuseaddr, true}],
    case gen_tcp:listen(Port, Options) of
        {ok, Listen} ->
            Acceptor = spawn_link(fun() ->
                accept(Listen, TargetHost, TargetPort)
            end),
            ok = gen_tcp:controlling_process(Listen, Acceptor),
            {ok, nil};
        {error, Reason} ->
            {error, failure(Reason)}
    end.

failure(eaddrinuse) -> address_in_use;
failure(Reason) -> {not_listening, atom_to_binary(Reason)}.

%% Accepts connections until the listening socket closes, which happens when
%% this process ends. Each connection gets a process of its own, linked to the
%% acceptor so it ends with it.
accept(Listen, TargetHost, TargetPort) ->
    case gen_tcp:accept(Listen) of
        {ok, Client} ->
            Pipe = spawn_link(fun() ->
                receive
                    handed_over -> pipe(Client, TargetHost, TargetPort)
                end
            end),
            ok = gen_tcp:controlling_process(Client, Pipe),
            Pipe ! handed_over,
            accept(Listen, TargetHost, TargetPort);
        {error, _Closed} ->
            ok
    end.

%% Connects to the target and passes bytes both ways until either side closes;
%% a client that cannot reach the target is closed at once.
pipe(Client, TargetHost, TargetPort) ->
    {Family, _, _} = family(TargetHost),
    Address = case inet:parse_address(binary_to_list(TargetHost)) of
        {ok, Ip} -> Ip;
        {error, einval} -> binary_to_list(TargetHost)
    end,
    case gen_tcp:connect(Address, TargetPort, [Family, binary, {active, false}]) of
        {ok, Target} ->
            ok = inet:setopts(Client, [{active, true}]),
            ok = inet:setopts(Target, [{active, true}]),
            pass(Client, Target);
        {error, _} ->
            gen_tcp:close(Client)
    end.

pass(Client, Target) ->
    receive
        {tcp, Client, Data} ->
            _ = gen_tcp:send(Target, Data),
            pass(Client, Target);
        {tcp, Target, Data} ->
            _ = gen_tcp:send(Client, Data),
            pass(Client, Target);
        {tcp_closed, _} ->
            close(Client, Target);
        {tcp_error, _, _} ->
            close(Client, Target)
    end.

close(Client, Target) ->
    gen_tcp:close(Client),
    gen_tcp:close(Target).

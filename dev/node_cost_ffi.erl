-module(node_cost_ffi).
-export([monotonic_nanoseconds/0, start_distribution/0, stop_distribution/0,
         start_peer/0, stop_peer/1, start_server_on_peer/1, ask_node_name/1,
         peer_node/1, spawn_on/2]).

%% A peer node: the process that controls it, linked to the process that
%% started it, and the node it runs as. The peer is connected through
%% distribution, where `peer:call` is not available, so every call to it goes
%% through `erpc` on the node name.
-type peer() :: {pid(), node()}.

%% How long a call to a peer node, or the start of one, may take before the
%% benchmark stops with a message instead of hanging.
-define(DEADLINE_MS, 30000).

-spec monotonic_nanoseconds() -> integer().
monotonic_nanoseconds() ->
    erlang:monotonic_time(nanosecond).

%% Makes this node distributed under a name made for this run: the operating
%% system process id keeps two runs on one machine apart, and the unique
%% integer keeps a second start in one run apart. The reason a start is
%% refused is printed, because the Gleam side only learns that it failed.
-spec start_distribution() -> {ok, node()} | {error, nil}.
start_distribution() ->
    Name = list_to_atom("node_cost_" ++ os:getpid() ++ "_"
                        ++ integer_to_list(erlang:unique_integer([positive]))),
    case net_kernel:start(Name, #{name_domain => shortnames}) of
        {ok, _Pid} ->
            {ok, node()};
        {error, Reason} ->
            io:format(standard_error,
                      "distribution did not start: ~p~n", [Reason]),
            {error, nil}
    end.

-spec stop_distribution() -> nil.
stop_distribution() ->
    ok = net_kernel:stop(),
    nil.

%% Starts a peer node linked to the caller, with every code path of this node
%% that is not part of the OTP installation, so the peer finds this project's
%% modules and its packages. The peer connects through distribution, which the
%% caller has started.
-spec start_peer() -> {ok, peer()} | {error, nil}.
start_peer() ->
    Root = code:root_dir(),
    Paths = [Path || Path <- code:get_path(),
                     Path =/= ".",
                     not lists:prefix(Root, Path)],
    Options = #{name => peer:random_name("node_cost_peer"),
                args => ["-pa" | Paths],
                wait_boot => ?DEADLINE_MS},
    case peer:start_link(Options) of
        {ok, Controller, Node} ->
            {ok, {Controller, Node}};
        {error, Reason} ->
            io:format(standard_error, "peer did not start: ~p~n", [Reason]),
            {error, nil}
    end.

-spec stop_peer(peer()) -> nil.
stop_peer({Controller, _Node}) ->
    ok = peer:stop(Controller),
    nil.

%% Calls the Gleam `start_server` of `genesis_prime/node_cost` in a process on the peer that stays alive until
%% the node stops, so the supervisor it starts stays up. The process reports
%% the outcome of the start and then waits.
-spec start_server_on_peer(peer()) -> {ok, nil} | {error, nil}.
start_server_on_peer({_Controller, Node}) ->
    Caller = self(),
    Ref = make_ref(),
    spawn(Node,
          fun() ->
              Outcome = case genesis_prime@node_cost:start_server() of
                            {ok, _Started} -> ok;
                            {error, _Reason} -> error
                        end,
              Caller ! {Ref, Outcome},
              receive after infinity -> ok end
          end),
    receive
        {Ref, ok} -> {ok, nil};
        {Ref, error} -> {error, nil}
    after ?DEADLINE_MS ->
        {error, nil}
    end.

%% A round trip to the peer's runtime; the answer is the peer's node name.
-spec ask_node_name(peer()) -> node().
ask_node_name({_Controller, Node}) ->
    erpc:call(Node, erlang, node, [], ?DEADLINE_MS).

-spec peer_node(peer()) -> node().
peer_node({_Controller, Node}) ->
    Node.

-spec spawn_on(node(), fun(() -> nil)) -> pid().
spawn_on(Node, Body) ->
    spawn(Node, Body).

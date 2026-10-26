-module(node_cost_ffi).
-export([monotonic_nanoseconds/0, start_distribution/0, stop_distribution/0,
         start_peer/0, stop_peer/1, start_server_on_peer/1, ask_node_name/1,
         peer_node/1, spawn_on/2]).

-spec monotonic_nanoseconds() -> integer().
monotonic_nanoseconds() ->
    erlang:error({todo, "body in the build commit"}).

-spec start_distribution() -> {ok, node()} | {error, nil}.
start_distribution() ->
    erlang:error({todo, "body in the build commit"}).

-spec stop_distribution() -> nil.
stop_distribution() ->
    erlang:error({todo, "body in the build commit"}).

-spec start_peer() -> {ok, pid()} | {error, nil}.
start_peer() ->
    erlang:error({todo, "body in the build commit"}).

-spec stop_peer(pid()) -> nil.
stop_peer(_Peer) ->
    erlang:error({todo, "body in the build commit"}).

-spec start_server_on_peer(pid()) -> {ok, nil} | {error, nil}.
start_server_on_peer(_Peer) ->
    erlang:error({todo, "body in the build commit"}).

-spec ask_node_name(pid()) -> node().
ask_node_name(_Peer) ->
    erlang:error({todo, "body in the build commit"}).

-spec peer_node(pid()) -> node().
peer_node(_Peer) ->
    erlang:error({todo, "body in the build commit"}).

-spec spawn_on(node(), fun(() -> nil)) -> pid().
spawn_on(_Node, _Body) ->
    erlang:error({todo, "body in the build commit"}).

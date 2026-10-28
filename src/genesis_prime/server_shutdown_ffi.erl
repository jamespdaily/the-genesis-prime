%% The host's stop signal for the server's tree (genesis_prime/server). SIGTERM
%% makes the VM run init:stop, which stops the applications and halts; a tree
%% started outside an application is not stopped by it, so its processes get no
%% Stopping and no recording gets its End. This handler replaces the VM's own
%% for the signals: SIGTERM stops the tree, then the VM; any other signal is
%% given to the VM's handler as before.
-module(server_shutdown_ffi).
-behaviour(gen_event).

-export([stop_tree_on_sigterm/1]).
-export([init/1, handle_event/2, handle_call/2, handle_info/2]).

%% How long the tree has to stop before the VM stops anyway.
-define(TREE_STOP_MS, 60000).

stop_tree_on_sigterm(Tree) ->
    ok = gen_event:swap_handler(erl_signal_server, {erl_signal_handler, []},
                                {?MODULE, Tree}),
    nil.

init({Tree, _Swapped}) -> {ok, Tree};
init(Tree) -> {ok, Tree}.

handle_event(sigterm, Tree) ->
    logger:info("SIGTERM received - stopping the supervision tree"),
    try proc_lib:stop(Tree, normal, ?TREE_STOP_MS)
    catch _:_ -> ok
    end,
    init:stop(),
    {ok, Tree};
handle_event(Event, Tree) ->
    {ok, []} = erl_signal_handler:handle_event(Event, []),
    {ok, Tree}.

handle_call(_Request, Tree) -> {ok, ok, Tree}.

handle_info(_Info, Tree) -> {ok, Tree}.

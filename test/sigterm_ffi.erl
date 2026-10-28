%% Starts a node of its own, has it serve a tree, ends it with the signal the
%% host sends a server (SIGTERM), and waits for the node to end. A node is the
%% only thing that can show how the VM treats the tree when it is told to stop.
-module(sigterm_ffi).
-export([terminate_a_serving_node/1]).

terminate_a_serving_node(Folder) ->
    Root = code:root_dir(),
    Paths = [Path || Path <- code:get_path(), not lists:prefix(Root, Path)],
    Peer = case peer:start(#{connection => standard_io, args => ["-pa" | Paths]}) of
               {ok, Started} -> Started;
               {ok, Started, _Node} -> Started
           end,
    Watched = erlang:monitor(process, Peer),
    try
        peer:call(Peer, sigterm_test, serve, [Folder], 30000),
        OsPid = peer:call(Peer, os, getpid, [], 30000),
        _ = os:cmd("kill -TERM " ++ OsPid),
        receive
            {'DOWN', Watched, process, Peer, _} -> {ok, nil}
        after 30000 ->
            peer:stop(Peer),
            {error, nil}
        end
    catch
        _:_ ->
            try peer:stop(Peer) catch _:_ -> ok end,
            {error, nil}
    end.

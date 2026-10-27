%% Runs a test function in a fresh node: a peer started with this node's code
%% path over standard_io, so it needs no distribution, and stopped after.
%% Nothing in the peer is loaded but what the call itself loads.
-module(fresh_node_ffi).
-export([run/3]).

run(Module, Function, TimeoutMs) ->
    %% The peer's own erl holds OTP's paths; it is given the project's.
    Root = code:root_dir(),
    Paths = [Path || Path <- code:get_path(), not lists:prefix(Root, Path)],
    Peer = case peer:start_link(#{connection => standard_io, args => ["-pa" | Paths]}) of
               {ok, Started} -> Started;
               {ok, Started, _Node} -> Started
           end,
    try peer:call(Peer, binary_to_atom(Module), binary_to_atom(Function), [],
                  TimeoutMs) of
        _ -> {ok, nil}
    catch
        Class:Reason ->
            {error, {not_returned, unicode:characters_to_binary(
                                      io_lib:format("~p: ~0p", [Class, Reason]))}}
    after
        peer:stop(Peer)
    end.

-module(application_support_ffi).
-export([stop_under_root/1]).

%% Ends a tree the application's root runs, as the root ends it when the node
%% stops: with the exit `shutdown`, waiting until the tree has ended. A tree
%% that has already ended is no failure. An exit signal from the test would
%% not do: a supervisor takes only its parent's exit as its stop, and the
%% root, not the test, is the parent of a tree started under it.
stop_under_root(Tree) ->
    {ok, Root} = application:get_supervisor(genesis_prime),
    _ = supervisor:terminate_child(Root, Tree),
    nil.

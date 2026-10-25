-module(repository_ffi).
-export([tracked_files/0]).

%% The output of `git ls-files`, run in the current directory.
tracked_files() ->
    unicode:characters_to_binary(os:cmd("git ls-files")).

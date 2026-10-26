-module(repository_ffi).
-export([tracked_files/0, note_tree_read/0, tree_reads/0]).

%% The output of `git ls-files`, run in the current directory.
tracked_files() ->
    unicode:characters_to_binary(os:cmd("git ls-files")).

%% Counts one read of the source tree from disk, in a counter every process of
%% this VM shares.
note_tree_read() ->
    counters:add(reads_counter(), 1, 1).

%% The number of source tree reads counted in this VM so far.
tree_reads() ->
    counters:get(reads_counter(), 1).

reads_counter() ->
    database_support_ffi:once(tree_reads, fun() -> counters:new(1, [atomics]) end).

%% What the ground's measure run needs of the runtime and no Gleam library exposes
%% (genesis_prime/terrain_walk): the memory the VM holds for binaries and in all, and the
%% resident size of the whole OS process. Nothing is traced: each reads a counter.
-module(terrain_walk_ffi).
-export([binary_bytes/0, total_bytes/0, resident_bytes/0, collect/0]).

%% The bytes the VM holds in reference-counted binaries, where a ground file lives.
binary_bytes() ->
    erlang:memory(binary).

%% The bytes the VM holds in all.
total_bytes() ->
    erlang:memory(total).

%% The resident size of this operating system process, as `ps` reports it.
resident_bytes() ->
    Text = os:cmd("ps -o rss= -p " ++ os:getpid()),
    list_to_integer(string:trim(Text)) * 1024.

%% Collects every process's garbage, so a reading is of what is held and not of what is
%% waiting to be freed.
collect() ->
    lists:foreach(fun(Pid) -> erlang:garbage_collect(Pid) end, erlang:processes()),
    nil.

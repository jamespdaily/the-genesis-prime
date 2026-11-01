-module(table_generator_ffi).
-export([scratch_folder/1, halt_with/1]).

%% Makes a folder no other call has used inside the base folder, and gives its
%% path.
-spec scratch_folder(binary()) -> binary().
scratch_folder(Base) ->
    Name = io_lib:format("table_generator_~s_~p",
                         [os:getpid(), erlang:unique_integer([positive])]),
    Path = unicode:characters_to_binary(filename:join(Base, lists:flatten(Name))),
    ok = filelib:ensure_path(Path),
    Path.

%% Stops the VM with the exit status, after the output is written.
-spec halt_with(integer()) -> nil.
halt_with(Status) ->
    erlang:halt(Status, [{flush, true}]).

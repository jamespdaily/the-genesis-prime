-module(table_generator_ffi).
-export([scratch_folder/1, run/2, halt_with/1]).

%% Makes a folder no other call has used inside the base folder, and gives its
%% path.
-spec scratch_folder(binary()) -> binary().
scratch_folder(Base) ->
    Name = io_lib:format("table_generator_~s_~p",
                         [os:getpid(), erlang:unique_integer([positive])]),
    Path = unicode:characters_to_binary(filename:join(Base, lists:flatten(Name))),
    ok = filelib:ensure_path(Path),
    Path.

%% Runs a program from the path with the arguments, in the current folder, and
%% waits for it: its exit status and what it wrote.
-spec run(binary(), [binary()]) -> {integer(), binary()}.
run(Program, Arguments) ->
    case os:find_executable(unicode:characters_to_list(Program)) of
        false ->
            {127, <<"command not found: ", Program/binary>>};
        Path ->
            Port = open_port({spawn_executable, Path},
                             [exit_status, stderr_to_stdout, binary, {args, Arguments}]),
            collect(Port, <<>>)
    end.

collect(Port, Output) ->
    receive
        {Port, {data, Data}} -> collect(Port, <<Output/binary, Data/binary>>);
        {Port, {exit_status, Status}} -> {Status, Output}
    end.

%% Stops the VM with the exit status, after the output is written.
-spec halt_with(integer()) -> nil.
halt_with(Status) ->
    erlang:halt(Status, [{flush, true}]).

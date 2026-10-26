-module(table_generator_ffi).
-export([arguments/0, getenv/1, scratch_folder/0, run/2, halt_with/1]).

%% The arguments after the module name on the `gleam run` command line.
-spec arguments() -> [binary()].
arguments() ->
    [unicode:characters_to_binary(Argument) || Argument <- init:get_plain_arguments()].

%% The value of an environment variable, or an error when it is not set.
-spec getenv(binary()) -> {ok, binary()} | {error, nil}.
getenv(Name) ->
    case os:getenv(unicode:characters_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.

%% Makes a folder no other call has used, and gives its path.
-spec scratch_folder() -> binary().
scratch_folder() ->
    Base = case os:getenv("TMPDIR") of
               false -> "/tmp";
               Folder -> Folder
           end,
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

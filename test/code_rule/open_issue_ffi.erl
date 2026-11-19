%% The answer of `gh issue list --state open --json number` for the repository
%% in the current directory, run as a port so it has a deadline of its own;
%% shellout waits for ever. Only gh's standard output is the answer; its standard
%% error goes to the VM's own, so a notice from gh never reaches the parser. The
%% reason is given when gh is not installed, exits with a failure or does not
%% answer within the deadline.
-module(open_issue_ffi).
-export([list_open/1]).

list_open(DeadlineMilliseconds) ->
    case os:find_executable("gh") of
        false ->
            {error, {not_read, <<"gh is not installed">>}};
        Gh ->
            Port = open_port({spawn_executable, Gh},
                             [binary, exit_status,
                              {args, ["issue", "list", "--state", "open",
                                      "--limit", "5000", "--json", "number"]}]),
            Deadline = erlang:monotonic_time(millisecond) + DeadlineMilliseconds,
            collect(Port, <<>>, Deadline)
    end.

collect(Port, Output, Deadline) ->
    Left = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Data}} ->
            collect(Port, <<Output/binary, Data/binary>>, Deadline);
        {Port, {exit_status, 0}} ->
            {ok, Output};
        {Port, {exit_status, Status}} ->
            Reason = iolist_to_binary(
                       io_lib:format("gh exited with status ~b (its message is in the test log)",
                                     [Status])),
            {error, {not_read, Reason}}
    after Left ->
        try port_close(Port) catch error:badarg -> ok end,
        {error, {not_read, <<"gh gave no answer before its deadline">>}}
    end.

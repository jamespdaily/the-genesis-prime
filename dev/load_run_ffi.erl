%% What the load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_run): the server's node, started as a peer of the node
%% that plays the clients, and called by the functions the run names; the
%% clients' own scheduler count; and an exit reason as one line of text.
-module(load_run_ffi).
-export([start_peer/0, stop_peer/1, start_server/2, sample/2, log_to_null/0, limit_schedulers/1,
         silence_crash_reports/0, describe_exit/1]).

%% Starts a node of its own with this node's code, over standard_io, which needs
%% no distribution. The environment (the database, the game address, the table
%% folder) is this node's.
start_peer() ->
    Paths = [Path || Path <- code:get_path(),
                     not lists:prefix(code:root_dir(), Path)],
    case peer:start_link(#{connection => standard_io, args => ["-pa" | Paths]}) of
        {ok, Peer} -> Peer;
        {ok, Peer, _Node} -> Peer
    end.

stop_peer(Peer) ->
    peer:stop(Peer),
    nil.

%% Runs the function `Start` in the peer, which starts the server there, and
%% gives what it returns.
start_server(Peer, Start) ->
    {ok, _} = peer:call(Peer, application, ensure_all_started, [genesis_prime], 60000),
    peer:call(Peer, erlang, apply, [Start, []], 120000).

%% The peer's sample, taken as the watch says.
sample(Peer, Watch) ->
    peer:call(Peer, genesis_prime@load_sample, take, [Watch], 60000).

%% Makes the node's log lines go to a file handler that writes to /dev/null, so
%% the server formats and writes each line as it does to a file or a pipe, and
%% the lines do not go through the peer's control channel to the clients' node.
log_to_null() ->
    ok = logger:remove_handler(default),
    ok = logger:add_handler(default, logger_std_h,
                            #{config => #{type => {file, "/dev/null"},
                                          filesync_repeat_interval => no_repeat}}),
    nil.

%% Takes schedulers offline until `Count` are online, as a node with fewer cores.
limit_schedulers(Count) ->
    erlang:system_flag(schedulers_online, Count),
    nil.

%% Stops this node's logger from writing the crash report of every client that
%% fails, which the run counts and reports itself.
silence_crash_reports() ->
    logger:set_primary_config(level, none),
    nil.

%% An exit reason as a line: a failed assertion's message when it has one,
%% else the reason as Erlang prints it, cut at 240 bytes.
describe_exit(normal) -> <<"normal">>;
describe_exit(killed) -> <<"killed">>;
describe_exit({abnormal, Reason}) ->
    Text = case Reason of
               #{message := Message} when is_binary(Message) -> Message;
               _ -> unicode:characters_to_binary(io_lib:format("~0p", [Reason]))
           end,
    binary:part(Text, 0, min(byte_size(Text), 240)).

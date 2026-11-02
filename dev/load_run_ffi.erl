%% What the load run needs of the runtime and no Gleam library exposes
%% (genesis_prime/load_run): the server's node, started as a peer of the node
%% that plays the clients and called with functions to run; the logger of each
%% node; and an exit reason as text.
-module(load_run_ffi).
-export([start_peer/0, stop_peer/1, in_peer/2, log_to_null/0,
         silence_crash_reports/0, describe_exit/1, no_local_port/1]).

%% Starts a node of its own with this node's code, over standard_io, which needs
%% no distribution, with the server's application running. The environment (the
%% database, the game address, the table folder) is this node's.
start_peer() ->
    Paths = [Path || Path <- code:get_path(),
                     not lists:prefix(code:root_dir(), Path)],
    Peer = case peer:start_link(#{connection => standard_io, args => ["-pa" | Paths]}) of
               {ok, Started} -> Started;
               {ok, Started, _Node} -> Started
           end,
    {ok, _} = peer:call(Peer, application, ensure_all_started, [genesis_prime], 60000),
    Peer.

stop_peer(Peer) ->
    peer:stop(Peer),
    nil.

%% Runs the function in the peer and gives what it returns.
in_peer(Peer, Run) ->
    peer:call(Peer, erlang, apply, [Run, []], 120000).

%% Makes the node's log lines go to a file handler that writes to /dev/null, so
%% the server formats and writes each line as it does to a file or a pipe, and
%% the lines do not go through the peer's control channel to the clients' node.
log_to_null() ->
    ok = logger:remove_handler(default),
    ok = logger:add_handler(default, logger_std_h,
                            #{config => #{type => {file, "/dev/null"},
                                          filesync_repeat_interval => no_repeat}}),
    nil.

%% Stops this node's logger from writing the crash report of every client that
%% fails, which the run counts and reports itself.
silence_crash_reports() ->
    logger:set_primary_config(level, none),
    nil.

%% An exit reason as a line. A process started with proc_lib that fails an
%% assertion exits with {ErrorMap, Stacktrace}: the line is the map's message
%% and the value that did not match, cut short.
describe_exit(killed) -> <<"killed">>;
describe_exit({abnormal, {#{message := Message, value := Value}, _Stack}})
  when is_binary(Message) ->
    cut(<<Message/binary, ": ", (cut(genesis_prime_step_runtime_ffi:term_text(Value), 120))/binary>>, 240);
describe_exit({abnormal, {#{message := Message}, _Stack}}) when is_binary(Message) ->
    cut(Message, 240);
describe_exit({abnormal, Reason}) ->
    cut(genesis_prime_step_runtime_ffi:term_text(Reason), 240).

%% Whether `eaddrnotavail` is anywhere in the exit reason, however deep and long.
no_local_port({abnormal, Reason}) ->
    string:find(genesis_prime_step_runtime_ffi:term_text(Reason), "eaddrnotavail") =/= nomatch;
no_local_port(_) ->
    false.

cut(Text, Most) ->
    binary:part(Text, 0, min(byte_size(Text), Most)).

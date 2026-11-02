%% The clock, the unique numbers and the logger that every shell uses
%% (genesis_prime/step/runtime). Each function returns the Gleam shape its
%% caller declares.
-module(genesis_prime_step_runtime_ffi).

-export([unique_id/0, monotonic_ms/0, filetime/0, log/3, set_about/1, term_text/1,
         log_stray/2, show_info_lines/0, keep_mailboxes_out_of_crash_reports/0]).

%% FILETIME counts 100-nanosecond intervals from 1601-01-01; the Unix epoch is
%% this many of them after it.
-define(FILETIME_AT_UNIX_EPOCH, 116444736000000000).

show_info_lines() ->
    ok = logger:set_primary_config(level, info),
    %% At info OTP also logs a progress report for every supervisor and child
    %% it starts; OTP's own filter keeps them out.
    case logger:add_primary_filter(progress_reports,
                                   {fun logger_filters:progress/2, stop}) of
        ok -> nil;
        {error, {already_exist, progress_reports}} -> nil
    end.

%% OTP's crash report of a process lists the messages waiting in its mailbox,
%% and those of the processes linked to it. A message can hold a session key or
%% a password, so a primary filter empties each list before any handler sees
%% the report.
keep_mailboxes_out_of_crash_reports() ->
    case logger:add_primary_filter(crash_report_mailboxes,
                                   {fun without_mailboxes/2, no_extra}) of
        ok -> nil;
        {error, {already_exist, crash_report_mailboxes}} -> nil
    end.

without_mailboxes(#{msg := {report, #{label := {proc_lib, crash},
                                      report := [Own | Neighbours]} = Report}} = Event,
                  no_extra) ->
    Event#{msg := {report, Report#{report := [empty_mailbox(Own)
                                              | [empty_mailboxes(Group) || Group <- Neighbours]]}}};
without_mailboxes(Event, no_extra) ->
    Event.

empty_mailboxes(Group) when is_list(Group) -> lists:map(fun empty_mailbox/1, Group);
empty_mailboxes(Other) -> Other.

empty_mailbox(Info) when is_list(Info) ->
    lists:keystore(messages, 1, Info, {messages, []});
empty_mailbox(Other) ->
    Other.

%% A term as Erlang writes it on one line.
term_text(Term) ->
    unicode:characters_to_binary(io_lib:format("~0p", [Term])).

unique_id() ->
    erlang:unique_integer([positive, monotonic]).

monotonic_ms() ->
    erlang:monotonic_time(millisecond).

%% The BEAM's system time, which follows its time correction, as a FILETIME.
filetime() ->
    erlang:system_time(nanosecond) div 100 + ?FILETIME_AT_UNIX_EPOCH.

%% Writes a log line through the logger, each known field of its who and where
%% as a metadata key of its own.
log(Level, Text, About) ->
    logger:log(level(Level), "~ts", [Text], metadata(About)),
    nil.

%% Sets the calling process's logger metadata, which every line it logs
%% carries, from the fields of About that are known.
set_about(About) ->
    logger:update_process_metadata(metadata(About)),
    nil.

%% Writes a warning that Shell dropped a message it does not take, naming the
%% message's kind and never its contents: a message can hold a session key.
log_stray(Message, Shell) ->
    logger:log(warning, "~ts dropped a message it does not take: ~ts",
               [Shell, kind(Message)]),
    nil.

kind(Message) when is_tuple(Message), tuple_size(Message) > 0,
                   is_atom(element(1, Message)) ->
    io_lib:format("a tuple of ~b elements tagged ~ts",
                  [tuple_size(Message), atom_to_binary(element(1, Message))]);
kind(Message) when is_tuple(Message) ->
    io_lib:format("a tuple of ~b elements", [tuple_size(Message)]);
kind(Message) when is_atom(Message) ->
    io_lib:format("the atom ~ts", [atom_to_binary(Message)]);
kind(Message) when is_binary(Message) ->
    io_lib:format("a binary of ~b bytes", [byte_size(Message)]);
kind(Message) when is_map(Message) ->
    io_lib:format("a map of ~b keys", [map_size(Message)]);
kind(Message) when is_list(Message) -> "a list";
kind(Message) when is_integer(Message) -> "an integer";
kind(Message) when is_float(Message) -> "a float";
kind(Message) when is_pid(Message) -> "a process id";
kind(Message) when is_reference(Message) -> "a reference";
kind(Message) when is_function(Message) -> "a function";
kind(Message) when is_port(Message) -> "a port";
kind(_Message) -> "a term of another kind".

metadata({about, Connection, Peer, Account, Character, Map, Message}) ->
    Fields = [{connection, Connection}, {peer, Peer}, {account_id, Account},
              {character_id, Character}, {map, Map}, {message, Message}],
    maps:from_list([{Key, Value} || {Key, {some, Value}} <- Fields]).

level(log_error) -> error;
level(log_warning) -> warning;
level(log_info) -> info;
level(log_debug) -> debug.

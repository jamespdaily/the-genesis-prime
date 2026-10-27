%% The clock, the unique numbers and the logger that every shell uses
%% (genesis_prime/step/runtime). Each function returns the Gleam shape its
%% caller declares.
-module(step_runtime_ffi).

-export([unique_id/0, monotonic_ms/0, filetime/0, log/3]).

%% FILETIME counts 100-nanosecond intervals from 1601-01-01; the Unix epoch is
%% this many of them after it.
-define(FILETIME_AT_UNIX_EPOCH, 116444736000000000).

unique_id() ->
    erlang:unique_integer([positive, monotonic]).

monotonic_ms() ->
    erlang:monotonic_time(millisecond).

%% The BEAM's system time, which follows its time correction, as a FILETIME.
filetime() ->
    erlang:system_time(nanosecond) div 100 + ?FILETIME_AT_UNIX_EPOCH.

%% Writes a log line through the logger, each known field of its who and where
%% as a metadata key of its own.
log(Level, Text, {about, Connection, Peer, Account, Character, Map, Message}) ->
    Fields = [{connection, Connection}, {peer, Peer}, {account_id, Account},
              {character_id, Character}, {map, Map}, {message, Message}],
    Metadata = maps:from_list([{Key, Value} || {Key, {some, Value}} <- Fields]),
    logger:log(level(Level), "~ts", [Text], Metadata),
    nil.

level(log_error) -> error;
level(log_warning) -> warning;
level(log_info) -> info;
level(log_debug) -> debug.

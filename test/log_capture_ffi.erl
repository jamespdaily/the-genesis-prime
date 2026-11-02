%% Captures log lines for the tests through one logger handler that stays
%% installed, and a table of the captures that want lines. A capture is added to
%% the table and removed from it, never added to or removed from the logger as a
%% handler of its own: OTP's logger_server takes the primary configuration's
%% handler list when it receives a remove_handler, and writes it back after the
%% handler's removing_handler callback, so a handler added meanwhile is dropped
%% from the list (its configuration remains, `logger:get_handler_config/1`
%% finds it, but no event reaches it). Tests that add and remove handlers at the
%% same time lose each other's lines.
-module(log_capture_ffi).
-export([start/3, stop/1, log/2, primary_level/0, set_primary_level/1,
         log_progress_report/0, remove_progress_filter/0,
         remove_crash_report_filter/0]).

-define(HANDLER, log_capture).
-define(CAPTURES, log_capture_captures).

%% Sends each event the Source logs to the Gleam subject Into: Source is
%% {process, Pid} for the events that process logs or all_processes for every
%% event of the node. Each event is sent as {Level, Text}, or, with
%% WithMetadata, {Level, Text, Metadata}, the metadata as {Key, Value} binaries,
%% the value as Erlang prints it. All are binaries. The handler runs in the
%% process that logs, so its send lands in the subject's owner's mailbox.
start(Source, {subject, Owner, Tag}, WithMetadata) ->
    ensure_table(),
    ensure_handler(),
    Id = erlang:unique_integer([positive]),
    true = ets:insert(?CAPTURES, {Id, Source, Owner, Tag, WithMetadata}),
    Id.

stop(Id) ->
    true = ets:delete(?CAPTURES, Id),
    nil.

%% The logger's handler callback.
log(#{level := Level, msg := Msg, meta := Meta}, _Config) ->
    try
        lists:foreach(
          fun({_Id, Source, Owner, Tag, WithMetadata}) ->
                  case from(Source, Meta) of
                      true -> Owner ! {Tag, line(Level, Msg, Meta, WithMetadata)};
                      false -> ok
                  end
          end,
          ets:tab2list(?CAPTURES))
    catch error:badarg -> ok
    end,
    ok;
log(_Event, _Config) ->
    ok.

from(all_processes, _Meta) -> true;
from({process, Pid}, #{pid := Pid}) -> true;
from({process, _Pid}, _Meta) -> false.

line(Level, Msg, _Meta, false) -> {atom_to_binary(Level), text(Msg)};
line(Level, Msg, Meta, true) -> {atom_to_binary(Level), text(Msg), metadata(Meta)}.

metadata(Meta) ->
    [{atom_to_binary(Key), unicode:characters_to_binary(io_lib:format("~0p", [Value]))}
     || {Key, Value} <- maps:to_list(Meta), is_atom(Key)].

text({string, String}) -> unicode:characters_to_binary(String);
text({report, Report}) -> unicode:characters_to_binary(io_lib:format("~0p", [Report]));
text({Format, Arguments}) -> unicode:characters_to_binary(io_lib:format(Format, Arguments)).

%% The table is owned by a process of its own that never ends, so it outlives
%% the test that made it. Two tests that start at once make it once.
ensure_table() ->
    case ets:whereis(?CAPTURES) of
        undefined ->
            Caller = self(),
            _ = spawn(fun() ->
                              try ets:new(?CAPTURES, [named_table, public, set])
                              catch error:badarg -> ok
                              end,
                              Caller ! {table_ready, self()},
                              receive never -> ok end
                      end),
            receive {table_ready, _} -> ok end;
        _ -> ok
    end.

%% The handler is installed once. Callers take a lock first and add it only
%% when the logger does not list it: the logger checks that a handler's id is
%% free when it takes the request, not when it adds the handler, so two adds of
%% one id that overlap are both accepted and list the handler twice, and every
%% event then reaches each capture twice.
ensure_handler() ->
    ok =
        global:trans({{?MODULE, handler}, self()},
                     fun() ->
                             case lists:member(?HANDLER, logger:get_handler_ids()) of
                                 true -> ok;
                                 false -> ok = logger:add_handler(?HANDLER, ?MODULE, #{})
                             end
                     end,
                     [node()]),
    ok.

primary_level() ->
    #{level := Level} = logger:get_primary_config(),
    Level.

set_primary_level(Level) ->
    ok = logger:set_primary_config(level, Level),
    nil.

log_progress_report() ->
    logger:info(#{label => {supervisor, progress},
                  report => [{supervisor, {local, planted}}, {started, []}]}),
    nil.

remove_progress_filter() ->
    _ = logger:remove_primary_filter(progress_reports),
    nil.

%% Removes the filter the server's start adds against mailboxes in crash
%% reports.
remove_crash_report_filter() ->
    _ = logger:remove_primary_filter(crash_report_mailboxes),
    nil.

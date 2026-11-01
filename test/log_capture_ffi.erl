-module(log_capture_ffi).
-export([start/2, start_with_metadata/2, start_all/1, stop/1, log/2, primary_level/0,
         set_primary_level/1,
         log_progress_report/0, remove_progress_filter/0]).

%% Adds a logger handler that sends each event logged by the process From to
%% the Gleam subject Into, as {Level, Text}, both binaries. The handler runs in
%% the process that logs, so its send lands in the subject's owner's mailbox.
start(From, {subject, Owner, Tag}) ->
    Id = binary_to_atom(
        <<"log_capture_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>),
    ok = logger:add_handler(Id, ?MODULE,
                            #{config => #{from => From, owner => Owner, tag => Tag}}),
    Id.

%% As start/2, and each event is sent as {Level, Text, Metadata}, the metadata as
%% {Key, Value} binaries, the value as Erlang prints it.
start_with_metadata(From, {subject, Owner, Tag}) ->
    Id = binary_to_atom(
        <<"log_capture_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>),
    ok = logger:add_handler(Id, ?MODULE,
                            #{config => #{from => From, owner => Owner, tag => Tag,
                                          metadata => true}}),
    Id.

%% As start_with_metadata/2, for every process of the node.
start_all(Into) ->
    start_all_for(Into).

stop(Id) ->
    _ = logger:remove_handler(Id),
    nil.

%% The logger's handler callback.
log(#{level := Level, msg := Msg, meta := Meta},
    #{config := #{all := true, owner := Owner, tag := Tag}}) ->
    Owner ! {Tag, {atom_to_binary(Level), text(Msg), metadata(Meta)}},
    ok;
log(#{level := Level, msg := Msg, meta := #{pid := From} = Meta},
    #{config := #{from := From, owner := Owner, tag := Tag, metadata := true}}) ->
    Owner ! {Tag, {atom_to_binary(Level), text(Msg), metadata(Meta)}},
    ok;
log(#{level := Level, msg := Msg, meta := #{pid := From}},
    #{config := #{from := From, owner := Owner, tag := Tag}}) ->
    Owner ! {Tag, {atom_to_binary(Level), text(Msg)}},
    ok;
log(_Event, _Config) ->
    ok.

metadata(Meta) ->
    [{atom_to_binary(Key), unicode:characters_to_binary(io_lib:format("~0p", [Value]))}
     || {Key, Value} <- maps:to_list(Meta), is_atom(Key)].

text({string, String}) -> unicode:characters_to_binary(String);
text({report, Report}) -> unicode:characters_to_binary(io_lib:format("~0p", [Report]));
text({Format, Arguments}) -> unicode:characters_to_binary(io_lib:format(Format, Arguments)).

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

start_all_for({subject, Owner, Tag}) ->
    Id = binary_to_atom(
        <<"log_capture_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>),
    ok = logger:add_handler(Id, ?MODULE,
                            #{config => #{all => true, owner => Owner, tag => Tag}}),
    Id.

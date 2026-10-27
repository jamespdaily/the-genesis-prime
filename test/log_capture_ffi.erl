-module(log_capture_ffi).
-export([start/2, stop/1, log/2]).

%% Adds a logger handler that sends each event logged by the process From to
%% the Gleam subject Into, as {Level, Text}, both binaries. The handler runs in
%% the process that logs, so its send lands in the subject's owner's mailbox.
start(From, {subject, Owner, Tag}) ->
    Id = binary_to_atom(
        <<"log_capture_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>),
    ok = logger:add_handler(Id, ?MODULE,
                            #{config => #{from => From, owner => Owner, tag => Tag}}),
    Id.

stop(Id) ->
    _ = logger:remove_handler(Id),
    nil.

%% The logger's handler callback.
log(#{level := Level, msg := Msg, meta := #{pid := From}},
    #{config := #{from := From, owner := Owner, tag := Tag}}) ->
    Owner ! {Tag, {atom_to_binary(Level), text(Msg)}},
    ok;
log(_Event, _Config) ->
    ok.

text({string, String}) -> unicode:characters_to_binary(String);
text({report, Report}) -> unicode:characters_to_binary(io_lib:format("~0p", [Report]));
text({Format, Arguments}) -> unicode:characters_to_binary(io_lib:format(Format, Arguments)).

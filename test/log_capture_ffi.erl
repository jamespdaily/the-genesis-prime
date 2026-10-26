-module(log_capture_ffi).
-export([start/0, await/2, log/2]).

%% Adds a logger handler under an id of its own that forwards every log event
%% to the calling process, and removes it when the calling process is down.
-spec start() -> nil.
start() ->
    Id = list_to_atom("log_capture_"
                      ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = logger:add_handler(Id, ?MODULE, #{config => #{target => self()}}),
    Caller = self(),
    spawn(fun() ->
                  Ref = monitor(process, Caller),
                  receive {'DOWN', Ref, _, _, _} -> logger:remove_handler(Id) end
          end),
    nil.

%% logger handler callback.
log(Event, #{config := #{target := Target}}) ->
    Target ! {captured_log, Event},
    ok.

%% Waits up to `Within` milliseconds for a log event logged by `Pid` and
%% returns its level and message, or fails.
-spec await(pid(), non_neg_integer()) ->
    {ok, {info_level | warning_level | error_level | other_level, binary()}} | {error, nil}.
await(Pid, Within) ->
    receive
        {captured_log, #{level := Level, msg := Message, meta := #{pid := Pid}}} ->
            {ok, {level(Level), text(Message)}}
    after Within ->
        {error, nil}
    end.

level(info) -> info_level;
level(warning) -> warning_level;
level(error) -> error_level;
level(_Other) -> other_level.

text({string, Chardata}) ->
    unicode:characters_to_binary(Chardata);
text({Format, Arguments}) when is_list(Format) ->
    unicode:characters_to_binary(io_lib:format(Format, Arguments));
text({report, Report}) ->
    unicode:characters_to_binary(io_lib:format("~p", [Report])).

-module(named_send_ffi).
-export([send/2]).

%% Sends `Message` to the process registered under `Name`, tagged as gleam_erlang's
%% `process.send` tags a message to a named subject: `{Name, Message}`. A name
%% with no process is no error here, where `erlang:send/2` raises `badarg` for it.
-spec send(atom(), term()) -> nil.
send(Name, Message) ->
    try
        erlang:send(Name, {Name, Message}),
        nil
    catch
        error:badarg -> nil
    end.

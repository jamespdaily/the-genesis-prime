%% Reads the terms of a rule recording back. Only bytes the server wrote are
%% read: a recording is written by the server's own recorder and read by
%% developers and tests from the repository, never taken from a client. So
%% binary_to_term reads them without [safe]: the atoms a recording holds (its
%% header's and its terms' tags) exist only once the modules that make them are
%% loaded, and [safe] would refuse a valid recording in a node that has not
%% loaded them. A term is returned only when its tag and size are those of a
%% header or a record.
-module(rule_recording_ffi).

-export([decode_header/1, decode_record/1]).

decode_header(Bytes) ->
    case term(Bytes) of
        {ok, Header} when is_tuple(Header), tuple_size(Header) =:= 7,
                          element(1, Header) =:= header -> {ok, Header};
        _ -> {error, nil}
    end.

decode_record(Bytes) ->
    case term(Bytes) of
        {ok, {taken, _Input, _Step} = Record} -> {ok, Record};
        {ok, {'end', Count} = Record} when is_integer(Count) -> {ok, Record};
        _ -> {error, nil}
    end.

term(Bytes) ->
    try {ok, binary_to_term(Bytes)}
    catch error:badarg -> {error, nil}
    end.

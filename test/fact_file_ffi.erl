-module(fact_file_ffi).
-export([line_after_only/2]).

%% The line that follows the one occurrence of Key in Text, without its line
%% end. An error when Key occurs not exactly once, or no line end follows it.
-spec line_after_only(binary(), binary()) -> {ok, binary()} | {error, nil}.
line_after_only(Text, Key) ->
    case binary:matches(Text, Key) of
        [{Start, Length}] ->
            From = Start + Length,
            Rest = binary:part(Text, From, byte_size(Text) - From),
            case binary:match(Rest, <<"\n">>) of
                {LineEnd, _} -> {ok, binary:copy(binary:part(Rest, 0, LineEnd))};
                nomatch -> {error, nil}
            end;
        _ ->
            {error, nil}
    end.

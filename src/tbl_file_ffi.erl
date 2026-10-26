-module(tbl_file_ffi).
-export([utf16_text/1, gap/0, table_of/1, row/2, rows/1]).

%% The UTF-8 form of the UTF-16 little-endian text at the start of Bytes, up
%% to its first zero character. An error when no zero character ends the text
%% on a 2-byte boundary, or when the text is not valid UTF-16.
-spec utf16_text(binary()) -> {ok, binary()} | {error, nil}.
utf16_text(Bytes) ->
    case text_length(Bytes, 0) of
        none ->
            {error, nil};
        Length ->
            case unicode:characters_to_binary(binary:part(Bytes, 0, Length),
                                              {utf16, little}, utf8) of
                Text when is_binary(Text) -> {ok, Text};
                _ -> {error, nil}
            end
    end.

%% The byte length of the text before its zero character, or none.
text_length(<<0, 0, _/binary>>, Length) -> Length;
text_length(<<_, _, Rest/binary>>, Length) -> text_length(Rest, Length + 2);
text_length(_, _) -> none.

%% What stands in a table's tuple where an id has no row.
-spec gap() -> nil.
gap() -> nil.

%% The rows, and the gaps among them, as one tuple.
-spec table_of([tuple() | nil]) -> tuple().
table_of(Rows) -> list_to_tuple(Rows).

%% The row of an id: element Id + 1 of the table, unless the id is outside the
%% tuple or stands at a gap.
-spec row(tuple(), integer()) -> {ok, tuple()} | {error, nil}.
row(Table, Id) when Id >= 0, Id < tuple_size(Table) ->
    case element(Id + 1, Table) of
        nil -> {error, nil};
        Row -> {ok, Row}
    end;
row(_Table, _Id) ->
    {error, nil}.

%% Every row, in id order, without the gaps.
-spec rows(tuple()) -> [tuple()].
rows(Table) ->
    [Row || Row <- tuple_to_list(Table), Row =/= nil].

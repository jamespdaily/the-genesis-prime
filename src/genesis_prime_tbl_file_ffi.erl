-module(genesis_prime_tbl_file_ffi).
-export([utf16_text/1, gap/0, table_of/1, row/2, rows/1, patch/3]).

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

%% The table with the rows put by id and the ids in Removes emptied, as a new
%% tuple: ids past the end grow it with gaps, and a removed id is a gap, as in a
%% table read from a file. The table it was made from is not changed.
-spec patch(tuple(), [{integer(), tuple()}], [integer()]) -> tuple().
patch(Table, Puts, Removes) ->
    Updates = maps:merge(maps:from_list(Puts), maps:from_keys(Removes, nil)),
    Size = lists:max([tuple_size(Table) | [Id + 1 || Id <- maps:keys(Updates)]]),
    list_to_tuple([case maps:find(Id, Updates) of
                       {ok, Row} -> Row;
                       error when Id < tuple_size(Table) -> element(Id + 1, Table);
                       error -> nil
                   end || Id <- lists:seq(0, Size - 1)]).

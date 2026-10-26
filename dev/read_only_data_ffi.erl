-module(read_only_data_ffi).
-export([monotonic_nanoseconds/0, word_bytes/0, schedulers_online/0,
         collect_process/1, process_memory_bytes/1, binary_memory_bytes/0,
         build_rows/3, table_of/1, map_of/1, row_at/2, row_in/2, id_of/1,
         read_stream/3, persistent_term_put/2, persistent_term_erase/1,
         persistent_term_bytes/0, new_table/0, insert_rows/2,
         table_memory_words/1]).

%% The kind of a column, as the Gleam type `client_table.ColumnKind` names its
%% constructors.
-type column_kind() :: integer32 | float32 | boolean32 | integer64 | utf16_text.

-spec monotonic_nanoseconds() -> integer().
monotonic_nanoseconds() ->
    erlang:monotonic_time(nanosecond).

-spec word_bytes() -> pos_integer().
word_bytes() ->
    erlang:system_info(wordsize).

-spec schedulers_online() -> pos_integer().
schedulers_online() ->
    erlang:system_info(schedulers_online).

-spec collect_process(pid()) -> nil.
collect_process(Pid) ->
    erlang:garbage_collect(Pid),
    nil.

-spec process_memory_bytes(pid()) -> non_neg_integer().
process_memory_bytes(Pid) ->
    {memory, Bytes} = process_info(Pid, memory),
    Bytes.

-spec binary_memory_bytes() -> non_neg_integer().
binary_memory_bytes() ->
    erlang:memory(binary).

%% Count rows, ids 1 to Count in order. A row has one element per kind, in
%% order; element 1 is the id. An integer is a value from the id and the
%% column, a float likewise, a boolean alternates by id, and a text is a
%% binary of TextBytes bytes of UTF-16 little-endian, different for every id.
-spec build_rows([column_kind()], non_neg_integer(), non_neg_integer()) ->
          [tuple()].
build_rows(Kinds, TextBytes, Count) ->
    Filler = binary:copy(<<$a, 0>>, max(0, (TextBytes - 4) div 2)),
    Indexed = lists:enumerate(Kinds),
    [row(Id, Indexed, TextBytes, Filler) || Id <- lists:seq(1, Count)].

%% The rows, ids from 1 with no gap, as one tuple: the row of id N is element N.
-spec table_of([tuple()]) -> tuple().
table_of(Rows) ->
    list_to_tuple(Rows).

-spec map_of([tuple()]) -> #{integer() => tuple()}.
map_of(Rows) ->
    maps:from_list([{id_of(Row), Row} || Row <- Rows]).

-spec row_at(tuple(), pos_integer()) -> tuple().
row_at(Table, Id) ->
    element(Id, Table).

-spec row_in(#{integer() => tuple()}, integer()) -> tuple().
row_in(Map, Id) ->
    maps:get(Id, Map).

-spec id_of(tuple()) -> integer().
id_of(Row) ->
    element(1, Row).

%% A binary of Count entries of 4 bytes: the table index in the first byte
%% (entry N is for table N rem 3, in the order of RowCounts) and in the other
%% three a random id from 1 to that table's row count. The generator is
%% `rand` with the `exsss` algorithm seeded from Seed.
-spec read_stream([pos_integer()], pos_integer(), integer()) -> binary().
read_stream(RowCounts, Count, Seed) ->
    Tables = length(RowCounts),
    Counts = list_to_tuple(RowCounts),
    read_stream(0, Count, Tables, Counts, rand:seed_s(exsss, Seed), <<>>).

-spec persistent_term_put(reference(), term()) -> nil.
persistent_term_put(Key, Table) ->
    persistent_term:put(Key, Table),
    nil.

-spec persistent_term_erase(reference()) -> nil.
persistent_term_erase(Key) ->
    persistent_term:erase(Key),
    nil.

%% The bytes the runtime reports persistent terms hold, from
%% `persistent_term:info()`.
-spec persistent_term_bytes() -> non_neg_integer().
persistent_term_bytes() ->
    maps:get(memory, persistent_term:info()).

%% A public `set` table, unnamed, keyed on element 1, with read_concurrency.
-spec new_table() -> ets:tid().
new_table() ->
    ets:new(read_only_data, [set, public, {keypos, 1}, {read_concurrency, true}]).

-spec insert_rows(ets:tid(), [tuple()]) -> nil.
insert_rows(Table, Rows) ->
    true = ets:insert(Table, Rows),
    nil.

-spec table_memory_words(ets:tid()) -> non_neg_integer().
table_memory_words(Table) ->
    ets:info(Table, memory).

%% Entry Index of the stream: table Index rem Tables, then a random id.
read_stream(Count, Count, _Tables, _Counts, _State, Stream) ->
    Stream;
read_stream(Index, Count, Tables, Counts, State, Stream) ->
    Table = Index rem Tables,
    {Id, Next} = rand:uniform_s(element(Table + 1, Counts), State),
    read_stream(Index + 1, Count, Tables, Counts, Next,
                <<Stream/bitstring, Table:8, Id:24>>).

%% One row: element 1 is the id, and every other element is a value of its
%% column's kind made from the id and the column's position.
row(Id, Indexed, TextBytes, Filler) ->
    list_to_tuple([cell(Kind, Id, Column, TextBytes, Filler)
                   || {Column, Kind} <- Indexed]).

cell(integer32, Id, 1, _TextBytes, _Filler) ->
    Id;
cell(integer32, Id, Column, _TextBytes, _Filler) ->
    (Id * 31 + Column * 7) rem 1000003;
cell(float32, Id, Column, _TextBytes, _Filler) ->
    (Id rem 1000) * 0.5 + Column;
cell(boolean32, Id, _Column, _TextBytes, _Filler) ->
    Id rem 2 =:= 0;
cell(integer64, Id, Column, _TextBytes, _Filler) ->
    Id * 4294967311 + Column;
cell(utf16_text, Id, _Column, TextBytes, Filler) ->
    binary:part(<<Id:32/little, Filler/binary>>, 0, TextBytes).

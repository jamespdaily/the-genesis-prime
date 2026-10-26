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
collect_process(_Pid) ->
    error(todo_body_in_the_build_commit).

-spec process_memory_bytes(pid()) -> non_neg_integer().
process_memory_bytes(_Pid) ->
    error(todo_body_in_the_build_commit).

-spec binary_memory_bytes() -> non_neg_integer().
binary_memory_bytes() ->
    error(todo_body_in_the_build_commit).

%% Count rows, ids 1 to Count in order. A row has one element per kind, in
%% order; element 1 is the id. An integer is a value from the id and the
%% column, a float likewise, a boolean alternates by id, and a text is a
%% binary of TextBytes bytes of UTF-16 little-endian, different for every id.
-spec build_rows([column_kind()], non_neg_integer(), non_neg_integer()) ->
          [tuple()].
build_rows(_Kinds, _TextBytes, _Count) ->
    error(todo_body_in_the_build_commit).

%% The rows, ids from 1 with no gap, as one tuple: the row of id N is element N.
-spec table_of([tuple()]) -> tuple().
table_of(_Rows) ->
    error(todo_body_in_the_build_commit).

-spec map_of([tuple()]) -> #{integer() => tuple()}.
map_of(_Rows) ->
    error(todo_body_in_the_build_commit).

-spec row_at(tuple(), pos_integer()) -> tuple().
row_at(_Table, _Id) ->
    error(todo_body_in_the_build_commit).

-spec row_in(#{integer() => tuple()}, integer()) -> tuple().
row_in(_Map, _Id) ->
    error(todo_body_in_the_build_commit).

-spec id_of(tuple()) -> integer().
id_of(_Row) ->
    error(todo_body_in_the_build_commit).

%% A binary of Count entries of 4 bytes: the table index in the first byte
%% (entry N is for table N rem 3, in the order of RowCounts) and in the other
%% three a random id from 1 to that table's row count. The generator is
%% `rand` with the `exsss` algorithm seeded from Seed.
-spec read_stream([pos_integer()], pos_integer(), integer()) -> binary().
read_stream(_RowCounts, _Count, _Seed) ->
    error(todo_body_in_the_build_commit).

-spec persistent_term_put(reference(), tuple()) -> nil.
persistent_term_put(_Key, _Table) ->
    error(todo_body_in_the_build_commit).

-spec persistent_term_erase(reference()) -> nil.
persistent_term_erase(_Key) ->
    error(todo_body_in_the_build_commit).

%% The bytes the runtime reports persistent terms hold, from
%% `persistent_term:info()`.
-spec persistent_term_bytes() -> non_neg_integer().
persistent_term_bytes() ->
    error(todo_body_in_the_build_commit).

%% A public `set` table, unnamed, keyed on element 1, with read_concurrency.
-spec new_table() -> ets:tid().
new_table() ->
    error(todo_body_in_the_build_commit).

-spec insert_rows(ets:tid(), [tuple()]) -> nil.
insert_rows(_Table, _Rows) ->
    error(todo_body_in_the_build_commit).

-spec table_memory_words(ets:tid()) -> non_neg_integer().
table_memory_words(_Table) ->
    error(todo_body_in_the_build_commit).

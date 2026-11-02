-module(table_rows_test_ffi).
-export([record_fields/1]).

%% The fields of a generated table row, in the order of the table's columns:
%% a Gleam record is a tuple of its constructor's tag and its fields.
-spec record_fields(tuple()) -> [term()].
record_fields(Row) ->
    tl(tuple_to_list(Row)).

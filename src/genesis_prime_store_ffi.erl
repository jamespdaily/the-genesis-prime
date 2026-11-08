-module(genesis_prime_store_ffi).
-export([empty/0, put_table/3, put_derived/3, has_table/2, table/2, derived/2,
         forget_derived/1, merge_tables/2, keep/2]).

%% The tables of one load as one value: {Tables, Derived}, a map of each table
%% by its name and a map of each derived value by its name. A table is the
%% tuple genesis_prime_tbl_file_ffi makes.
-spec empty() -> {map(), map()}.
empty() -> {#{}, #{}}.

-spec put_table(binary(), term(), {map(), map()}) -> {map(), map()}.
put_table(Name, Table, {Tables, Derived}) -> {Tables#{Name => Table}, Derived}.

-spec put_derived(binary(), term(), {map(), map()}) -> {map(), map()}.
put_derived(Name, Value, {Tables, Derived}) -> {Tables, Derived#{Name => Value}}.

-spec has_table(binary(), {map(), map()}) -> boolean().
has_table(Name, {Tables, _Derived}) -> maps:is_key(Name, Tables).

%% The table of a name; a name the load has no table for stops the caller.
-spec table(binary(), {map(), map()}) -> term().
table(Name, {Tables, _Derived}) -> maps:get(Name, Tables).

%% The derived value of a name; a name no derivation built stops the caller.
-spec derived(binary(), {map(), map()}) -> term().
derived(Name, {_Tables, Derived}) -> maps:get(Name, Derived).

%% The tables with no derived value, for an edit, whose derived values are
%% built again from the edited tables.
-spec forget_derived({map(), map()}) -> {map(), map()}.
forget_derived({Tables, _Derived}) -> {Tables, #{}}.

%% The tables of the first value with the tables of the second added; a table
%% the second names replaces the first's.
-spec merge_tables({map(), map()}, {map(), map()}) -> {map(), map()}.
merge_tables({Tables, Derived}, {More, _}) -> {maps:merge(Tables, More), Derived}.

%% Stores the value under the key, once, and gives the stored copy, which lives
%% in the literal area, so a process that holds it holds no copy of its own and
%% a message that carries it copies nothing. A key that holds a value stops the
%% caller: replacing or erasing a held value copies the whole of it into every
%% process that holds it.
-spec keep(term(), term()) -> term().
keep(Key, Value) ->
    case persistent_term:get(Key, none) of
        none ->
            persistent_term:put(Key, Value),
            persistent_term:get(Key);
        _ ->
            error({load_key_held, Key})
    end.

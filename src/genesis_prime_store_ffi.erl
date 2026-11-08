-module(genesis_prime_store_ffi).
-export([empty/0, put_table/3, put_derived/3, find_table/3, find_derived/3,
         forget_derived/1, merge_tables/2, keep/2]).

%% The tables of one load as one value: {Tables, Derived}, a map of each table
%% by its name and a map of each derived value by its name. A table is the
%% tuple genesis_prime_tbl_file_ffi makes. A load stores the value in one
%% persistent term, and a handle to it is the term's key: a read takes the
%% value from the term, whose subterms a read does not copy.
-spec empty() -> {map(), map()}.
empty() -> {#{}, #{}}.

-spec put_table(binary(), term(), {map(), map()}) -> {map(), map()}.
put_table(Name, Table, {Tables, Derived}) -> {Tables#{Name => Table}, Derived}.

-spec put_derived(binary(), term(), {map(), map()}) -> {map(), map()}.
put_derived(Name, Value, {Tables, Derived}) -> {Tables, Derived#{Name => Value}}.

%% The table of a name: the edits' first, then each stored value's in order of
%% Bases (a list of persistent term keys).
-spec find_table(binary(), [term()], {map(), map()}) -> {ok, term()} | {error, nil}.
find_table(Name, Bases, {Edits, _}) ->
    case maps:find(Name, Edits) of
        {ok, _} = Found -> Found;
        error -> find_stored(Name, Bases, 1)
    end.

%% The derived value of a name: the edits' first, then each stored value's in
%% order of Bases.
-spec find_derived(binary(), [term()], {map(), map()}) -> {ok, term()} | {error, nil}.
find_derived(Name, Bases, {_, Edits}) ->
    case maps:find(Name, Edits) of
        {ok, _} = Found -> Found;
        error -> find_stored(Name, Bases, 2)
    end.

find_stored(_Name, [], _Part) ->
    {error, nil};
find_stored(Name, [Base | Rest], Part) ->
    case maps:find(Name, element(Part, persistent_term:get(Base))) of
        {ok, _} = Found -> Found;
        error -> find_stored(Name, Rest, Part)
    end.

%% The edits without a derived value, for an edit of a test, whose derived
%% values are built again from the edited tables.
-spec forget_derived({map(), map()}) -> {map(), map()}.
forget_derived({Tables, _Derived}) -> {Tables, #{}}.

%% The edits of the first with the tables of the second put over them; the
%% derived values are the first's.
-spec merge_tables({map(), map()}, {map(), map()}) -> {map(), map()}.
merge_tables({Tables, Derived}, {More, _}) -> {maps:merge(Tables, More), Derived}.

%% Stores the value under the key, once. A key that holds a value stops the
%% caller: replacing or erasing a held value copies the whole of it into every
%% process that holds it.
-spec keep(term(), term()) -> nil.
keep(Key, Value) ->
    case persistent_term:get(Key, none) of
        none ->
            persistent_term:put(Key, Value),
            nil;
        _ ->
            error({load_key_held, Key})
    end.

-module(module_preload_ffi).
-export([load_project/0]).

%% The modules of the package this file was compiled into (its beam files'
%% folder) that are not loaded: code:all_available/0 lists the modules of the
%% code path with whether each is loaded, and loads none.
%% code:ensure_modules_loaded/1 loads them in parallel (OTP 26 and later) and
%% returns {error, [{Module, Reason}]} for a module it could not load.
load_project() ->
    Package = filename:dirname(filename:dirname(code:which(?MODULE))),
    ok = code:ensure_modules_loaded(
        [list_to_atom(Name)
         || {Name, File, false} <- code:all_available(),
            is_list(File),
            lists:prefix(Package ++ "/", File)]),
    nil.

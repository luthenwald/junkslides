%% Durable write for the S4 spike: simplifile has no fsync, so this writes
%% the bytes and syncs them before closing. Prototype of the future store FFI.
-module(s4_store_ffi).
-export([write_synced/2]).

write_synced(Path, Bytes) ->
    case file:open(Path, [write, raw, binary]) of
        {ok, File} ->
            Result = case file:write(File, Bytes) of
                ok -> file:sync(File);
                Error -> Error
            end,
            ok = file:close(File),
            case Result of
                ok -> {ok, nil};
                {error, _} -> {error, nil}
            end;
        {error, _} -> {error, nil}
    end.

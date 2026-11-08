%% Durable writes for junkslides_server/store. simplifile has no fsync, so this
%% writes the bytes to a new file and syncs them to disk before closing.
%% Spike S4 measured the rename that follows as atomic for readers.
-module(junkslides_server_store_ffi).
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
                {error, Reason} -> {error, atom_to_binary(Reason)}
            end;
        {error, Reason} -> {error, atom_to_binary(Reason)}
    end.

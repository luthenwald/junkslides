%% Durable writes for junkslides_server/store. simplifile has no fsync, so this
%% writes the bytes to a new file and syncs them to disk before closing.
%% Spike S4 measured the rename that follows as atomic for readers.
%% simplifile cannot say where a symbolic link leads either; read_link does.
-module(junkslides_server_store_ffi).
-export([write_synced/2, read_link/1]).

read_link(Path) ->
    case file:read_link_all(Path) of
        {ok, Target} when is_binary(Target) -> {ok, Target};
        {ok, Target} -> {ok, unicode:characters_to_binary(Target)};
        {error, _} -> {error, nil}
    end.

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

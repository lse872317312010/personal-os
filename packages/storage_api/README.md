# storage_api

Pure Dart persistence ports. Implementations may use SQLite, encrypted files,
or memory, but those details cannot cross this boundary.

`EventStore.appendAll` is atomic and ordered. The API deliberately exposes no
update/delete operation because M1 events are immutable.


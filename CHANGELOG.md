## Unreleased
- Add `Client.start` for non-linked processes.
- Add `async` option to `start` and `start_link`.
- Roll `handle_connect_failure` functionality into `handle_disconnect`.
  - The first parameter of `handle_disconnect` is now a map with the keys:
    `:reason`, `:conn`, and `:attempt_number`.
  - `handle_disconnect` now has another return option for when wanted to
    reconnect with different URI options or headers:
    `{:reconnect, new_conn, new_state}`
  - Added the `:handle_initial_conn_failure` option to the options for `start`
    and `start_link` that will allow `handle_disconnect` to be called if we can
    establish a connection during those functions.
  - Removed `handle_connect_failure` entirely.

## 0.1.3
- `Client.start_link` will no longer cause the calling process to exit on
  connection failure and will return a proper error tuple instead.
- Change `WebSockex.Conn.RequestError` to `WebSockex.RequestError`.
- Add `handle_connect_failure` to be invoked after initiating a connection
  fails. Fixes #5

## 0.1.2
- Rework how disconnects are handled which should improve the
  `handle_disconnect` callback reliability.

## Unreleased
- Add `Client.start` for non-linked processes.
- Add `async` option to `start` and `start_link`.

## 0.1.3
- `WebSockex.start_link` will no longer cause the calling process to exit on
  connection failure and will return a proper error tuple instead.
- Change `WebSockex.Conn.RequestError` to `WebSockex.RequestError`.
- Add `handle_connect_failure` to be invoked after initiating a connection
  fails. Fixes #5

## 0.1.2
- Rework how disconnects are handled which should improve the
  `handle_disconnect` callback reliability.

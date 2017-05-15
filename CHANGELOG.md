## unreleased
- `WebSockex.start_link` will no longer cause the calling process to exit on
  connection failure and will return a proper error tuple instead.
- Change `WebSockex.Conn.RequestError` to `WebSockex.RequestError`.

## 0.1.2
- Rework how disconnects are handled which should improve the
  `handle_disconnect` callback reliability.

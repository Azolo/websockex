## Unreleased
### Breaking Changes
- The parameters for the `handle_connect/2` callback have been reversed. The
  order is now `(conn, state)`.

### Enhancements
- Added initial connection timeouts.
  (`:socket_connect_timeout` and `:socket_recv_timeout`)
  - Can be used as `start` or `start_link` option or as a `Conn.new` option.
  - `:socket_connect_timeout` - The timeout for opening a TCP connection.
  - `:socket_recv_timeout` - The timeout for receiving a HTTP response header.
- `start` and `start_link` can now take a `Conn` struct in place of a url.
- Added the ability to handle system messages while opening a connection.
- Added the ability to handle parent exit messages while opening a connection.
- Improve `:sys.get_status`, `:sys.get_state`, `:sys.replace_state` functions.
  - These are undocumented, but are meant primarly for debugging.

### Bug Fixes
- Ensure `terminate/2` callback is called consistently.
- Ensure when termination when a parent exit signal is received.
- Add the `system_code_change` function so that the `code_change` callback is
  actually used.

## 0.2.0
### Major Changes
- Moved all the `WebSockex.Client` module functionality into the base
  `WebSockex` module.
- Roll `handle_connect_failure` functionality into `handle_disconnect`.
- Roll `init` functionality into `handle_connect`

### Detailed Changes
- Roll `init` functionality into `handle_connect`
  - `handle_connect` will be invoked upon establishing any connection, i.e.,
    the intial connection and when reconnecting.
  - The `init` callback is removed entirely.
- Moved all the `WebSockex.Client` module functionality into the base
  `WebSockex` module.
  - Changed the `Application` module to `WebSockex.Application`.
- Add `WebSockex.start` for non-linked processes.
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

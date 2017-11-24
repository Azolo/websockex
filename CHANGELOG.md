## Unreleased
### Enhancements
- Allow `:via` and `:global` tuples for named registration. This includes
  handling for `cast/2` and `send_frame/2`.
- Add access to response headers during `handle_connect/2` via `Conn.resp_headers`.
- Add `Conn.parse_url/1` to handle url to URI conversion.
- Allow `Conn.new/2` to use a url string instead of a `URI` struct.
- Automatically add a "/" path to a pathless url.
  - The HTTP request will break without a valid path!

### Bug Fixes
- No longer invoke `handle_disconnect` if there is reason to exit from invoking
  a callback. (e.g. an exception was raised)
- Properly handle unexpected SSL socket termination.
  - This _seems_ pretty important, but I don't know...
- Return a descriptive error when trying to use `send_frame/2` in a callback.

## 0.4.0
### Breaking Changes
- `send_frame/2` is now synchronous and returns an error when connection is
  opening or closing.

### Enhancements
- Added debug printing for the `:sys` module.
- Rework `Conn.new` to accept other protocols.
- Added an `InvalidFrameError` for frames unrecognized by `Frame.encode_frame`.
- Go through the disconnect cycle when there's an error while with the
  `{:reply, frame, state}` callback response.
- Send a close frame with the close code `1011` when there is an unexpected
  error. (Like an `Exception` in the middle of a callback)
- Add a more specific error when the `:websockex` application hasn't been
  started yet.
- Added a `:name` options for local registration.

### Bug Fixes
- Fix a couple of places where the call stack wasn't being properly tail-call
  optimized.

## 0.3.1
### Enhancements
- Handle system messages and parent exits while closing the connection.
- The output from `:sys.get_status` didn't look pretty in `:observer` now it
  does!
- `format_status/2` now an optional callback.

### Bug Fixes
- SSL frames sent right after connecting will now be handled instead of being
  left in a dead Task mailbox.
- Fixed some places where `dialyzer` told me I had my specs screwed up.

## 0.3.0
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

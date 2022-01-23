for app <- [:cowboy, :plug],
    do: Application.ensure_all_started(app)

ExUnit.start(capture_log: true)

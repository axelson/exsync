Synchronize with the code server
This can be used in a Phoenix/Plug application to avoid stepping on the Phoenix.CodeReloader's toes
This avoids rendering a page when some modules are not available due to recompilation
TODO:
- [ ] I think with this code there's a race condition that should be handled if we want to be a replacement for CodeReloader
  - If a reload and a file change come in at the same time we need to make sure that `sync` blocks until the file change is finished
  - Although this is difficult because of the async file-based infrastructure that exsync is built on
  - The cleanest way to solve this is to use a single GenServer instead of 3
- [ ] Document how to use ExSync in a Phoenix project

The main problem with using ExSync in a Phoenix project is that requests can come in while code is being recompiled. This happens most often when a file is edited (which triggers the SrcMonitor and then the BeamMonitor) and then the browser is reloaded before compilation is finished. Code will then execute in an inbetween state where some modules are not available because they are being reloaded by the BeamMonitor. Instead we should wait until all the source and beam files have been processed.

That could involve waiting for both the SrcMonitor and BeamMonitor to finish (which can be a little tricky because of the throttling that we're doing now), but perhaps it would be easier if we consolidated both of those into a single GenServer.

I don't think it makes sense to try to fully replace Phoenix.CodeReloader because of how deeply integrated (and non-configurable) it is. Instead ExSync.ReloaderPlug would be used in addition to Phoenix.CodeReloader. It will block until the source and beam files are done being processed.

Commits notes

- Change the BeamMonitor to use the configured backend

ExSync
======

Yet another Elixir reloader.

## System Support

ExSync deps on [FileSystem](https://github.com/falood/file_system)

## Usage

1. Create a new application:

```bash
mix new my_app
```

2. Add exsync to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:exsync, "~> 0.2", only: :dev},
  ]
end
```

Optionally add this snippet to your `.iex.exs` (in the root of your project) or your `~/.iex.exs`:
```
if Code.ensure_loaded?(ExSync) && function_exported?(ExSync, :register_group_leader, 0) do
  ExSync.register_group_leader()
end
```

This will prevent the ExSync logs from overwriting your IEx prompt.
Alternatively you can always just run `ExSync.register_group_leader()` in your
IEx prompt.

## Usage for umbrella project

1. Create an umbrella project

```bash
mix new my_umbrella_app --umbrella
```

2. Add exsync to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:exsync, "~> 0.2", only: :dev},
  ]
end
```

3. start your umbrella project with `exsync` task

```bash
iex -S mix exsync
```

## Config

All configuration for this library is handled via the application environment.

`:addition_dirs` - Additional directories to monitor

For example, to monitor the `priv` directory, add this to your `config.exs`:

```elixir
config :exsync, addition_dirs: ["/priv"]
```

`:extensions` - List of file extensions to watch for changes. Defaults to: `[".erl", ".hrl", ".ex", ".eex"]`

`:extra_extensions` - List of additional extensions to watch for changes (cannot be used with `:extensions`)

For example, to watch `.js` and `.css` files add this to your `config.exs`:

```elixir
config :exsync, extra_extensions: [".js", ".css"]
```

`:logging_enabled` - Set to false to disable logging (default true)

`:reload_callback` - A callback [MFA](https://codereviewvideos.com/blog/what-is-mfa-in-elixir/) that is called when a set of files are done reloading. Can be used to implement your own special handling to react to file reloads.

`:reload_timeout` - Amount of time to wait in milliseconds before triggering the `:reload_callback`. Defaults to 150ms.

For example, to call `MyApp.MyModule.handle_reload()` add this to your `config.exs`:

```elixir
config :exsync,
  reload_timeout: 75,
  reload_callback: {MyApp.MyModule, :handle_reload, []}
```

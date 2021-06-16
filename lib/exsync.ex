require Logger

defmodule ExSync do
  defdelegate register_group_leader, to: ExSync.Logger.Server

  @doc """
  Blocks until code is finished recompiling
  """
  def sync do
    ExSync.ReloaderServer.sync()
  end

  def set_reload_callback(module, function, arguments \\ [])
      when is_atom(module) and is_atom(function) and is_list(arguments) do
    Application.put_env(:exsync, :reload_callback, {module, function, arguments})
  end

  def call_reload_callback do
    {mod, fun, args} = ExSync.Config.reload_callback()
    apply(mod, fun, args)
  end
end

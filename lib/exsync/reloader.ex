defmodule ExSync.Reloader do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def reload_and_unload_modules(reload_set, unload_set) do
    GenServer.call(__MODULE__, {:reload_and_unload_modules, reload_set, unload_set}, :infinity)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, nil}
  end

  @doc """
  Synchronizes with the code server if it is alive.

  If it is not running, it also returns true.
  """
  def sync do
    pid = Process.whereis(__MODULE__)
    ref = Process.monitor(pid)
    GenServer.cast(pid, {:sync, self(), ref})

    receive do
      ^ref -> :ok
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end

  @impl GenServer
  def handle_call({:reload_and_unload_modules, reload_set, unload_set}, _from, state) do
    Enum.each(reload_set, fn module_path ->
      ExSync.Utils.reload(module_path)
    end)

    Enum.each(unload_set, fn module_path ->
      ExSync.Utils.unload(module_path)
    end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:sync, pid, ref}, state) do
    send(pid, ref)
    {:noreply, state}
  end
end

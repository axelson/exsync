defmodule ExSync.BeamWatcher do
  @moduledoc false

  @throttle_timeout_ms 100

  alias ExSync.SyncWatcher

  defmodule State do
    @enforce_keys [
      :throttle_timer,
      :finished_reloading_timer,
      :unload_set,
      :reload_set,
      :waiting_on_sync
    ]
    defstruct [
      :throttle_timer,
      :finished_reloading_timer,
      :unload_set,
      :reload_set,
      :waiting_on_sync
    ]
  end

  def subscribe do
    {:ok, watcher_pid} =
      FileSystem.start_link(
        dirs: ExSync.Config.beam_dirs(),
        backend: Application.get_env(:file_system, :backend)
      )

    :ok = FileSystem.subscribe(watcher_pid)

    state = %State{
      finished_reloading_timer: false,
      throttle_timer: nil,
      unload_set: MapSet.new(),
      reload_set: MapSet.new(),
      waiting_on_sync: false
    }

    {watcher_pid, state}
  end

  def sync(%State{} = state) do
    if state.finished_reloading_timer do
      {:waiting, %State{state | waiting_on_sync: true}}
    else
      {:done, state}
    end
  end

  def handle_file_event({path, events}, %State{} = state) do
    %State{finished_reloading_timer: finished_reloading_timer} = state

    # Debounce the finished reloading timer
    if finished_reloading_timer, do: Process.cancel_timer(finished_reloading_timer)

    finished_reloading_timer =
      Process.send_after(self(), {__MODULE__, :reload_complete}, ExSync.Config.reload_timeout())

    action = action(Path.extname(path), path, events)

    state =
      track_module_change(action, path, state)
      |> maybe_schedule_throttle_timer()

    %State{state | finished_reloading_timer: finished_reloading_timer}
  end

  def handle_file_event(:stop, %State{} = state) do
    ExSync.Logger.debug("beam watcher stopped")
    state
  end

  def handle_event(:throttle_timer_complete, state) do
    state = reload_and_unload_modules(state)
    %State{state | throttle_timer: nil}
  end

  def handle_event(:reload_complete, state) do
    if callback = ExSync.Config.reload_callback() do
      ExSync.Logger.debug("Reload complete, calling reload callback")
      {mod, fun, args} = callback
      Task.start(mod, fun, args)
    else
      ExSync.Logger.debug("Reload complete")
    end

    SyncWatcher.done(__MODULE__)

    %State{state | finished_reloading_timer: false}
  end

  defp reload_and_unload_modules(%State{} = state) do
    %State{reload_set: reload_set, unload_set: unload_set} = state

    ExSync.Logger.debug("ExSync BeamWatcher start reload")

    Enum.each(reload_set, fn module_path ->
      ExSync.Utils.reload(module_path)
    end)

    Enum.each(unload_set, fn module_path ->
      ExSync.Utils.unload(module_path)
    end)

    ExSync.Logger.debug("ExSync BeamWatcher finish reload")

    %State{state | reload_set: MapSet.new(), unload_set: MapSet.new()}
  end

  defp action(".beam", path, events) do
    # TODO: Hopefully this is still reliable even though the File.exists? call
    # is running some time after the events were received
    case {:created in events, :removed in events, :modified in events, File.exists?(path)} do
      # update
      {_, _, true, true} -> :reload_module
      # temp file
      {true, true, _, false} -> :nothing
      # remove
      {_, true, _, false} -> :unload_module
      # create and other
      _ -> :nothing
    end
  end

  defp action(_extname, _path, _events), do: :nothing

  defp track_module_change(:nothing, _module, state), do: state

  defp track_module_change(:reload_module, module, state) do
    %State{reload_set: reload_set, unload_set: unload_set} = state

    %State{
      state
      | reload_set: MapSet.put(reload_set, module),
        unload_set: MapSet.delete(unload_set, module)
    }
  end

  defp track_module_change(:unload_module, module, state) do
    %State{reload_set: reload_set, unload_set: unload_set} = state

    # TODO: How should we properly handle the case where :unload_module and
    # :reload_module has come in? Can we really rely on the ordering? Should one
    # take precedance over the other?

    %State{
      state
      | reload_set: MapSet.delete(reload_set, module),
        unload_set: MapSet.put(unload_set, module)
    }
  end

  defp maybe_schedule_throttle_timer(%State{throttle_timer: nil} = state) do
    %State{reload_set: reload_set, unload_set: unload_set} = state

    if Enum.empty?(reload_set) && Enum.empty?(unload_set) do
      state
    else
      throttle_timer =
        Process.send_after(self(), {__MODULE__, :throttle_timer_complete}, @throttle_timeout_ms)

      %State{state | throttle_timer: throttle_timer}
    end
  end

  defp maybe_schedule_throttle_timer(%State{} = state), do: state
end

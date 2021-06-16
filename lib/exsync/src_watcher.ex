defmodule ExSync.SrcWatcher do
  @moduledoc false

  @throttle_timeout_ms 100

  alias ExSync.SyncWatcher

  defmodule State do
    defstruct [:throttle_timer, :waiting_on_sync]
  end

  def subscribe do
    {:ok, watcher_pid} =
      FileSystem.start_link(
        dirs: ExSync.Config.src_dirs(),
        backend: Application.get_env(:file_system, :backend)
      )

    :ok = FileSystem.subscribe(watcher_pid)

    state = %State{
      throttle_timer: nil,
      waiting_on_sync: nil
    }

    {watcher_pid, state}
  end

  def sync(%State{} = state) do
    # If the throttle_timer is active, then wait for it to complete
    # But that's hard to do because we're no longer a process...
    # So store info in the state?
    if state.throttle_timer do
      {:waiting, %State{state | waiting_on_sync: true}}
    else
      {:done, state}
    end
  end

  def handle_file_event({path, events}, %State{} = state) do
    matching_extension? = Path.extname(path) in ExSync.Config.src_extensions()

    # This varies based on editor and OS - when saving a file in neovim on linux,
    # events received are:
    #   :modified
    #   :modified, :closed
    #   :attribute
    # Rather than coding specific behaviors for each OS, look for the modified event in
    # isolation to trigger things.
    matching_event? = :modified in events

    if matching_extension? && matching_event? do
      maybe_schedule_recomplete(state)
    else
      state
    end
  end

  def handle_event(:throttle_timer_complete, %State{} = state) do
    ExSync.Logger.debug("ExSync SrcWatcher start recomplete")
    # TODO: Should this be handled in a task?
    ExSync.Utils.recomplete()
    ExSync.Logger.debug("ExSync SrcWatcher finish recomplete")

    # FIXME: This feels hacky
    # Maybe SrcWatcher and BeamWatcher should actually stay as different processes?
    if state.waiting_on_sync do
      SyncWatcher.done(__MODULE__)
    end

    %State{state | throttle_timer: nil, waiting_on_sync: false}
  end

  defp maybe_schedule_recomplete(%State{throttle_timer: nil} = state) do
    throttle_timer =
      Process.send_after(self(), {__MODULE__, :throttle_timer_complete}, @throttle_timeout_ms)

    %State{state | throttle_timer: throttle_timer}
  end

  defp maybe_schedule_recomplete(state), do: state
end

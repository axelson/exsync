defmodule ExSync.ReloaderServerWatcher do
  @moduledoc """
  Monitors source file and beam file changes and reloads and unloads modules as necessary

  Uses `ExSync.SrcWatcher` and `ExSync.BeamWatcher` to coordinate the reloading process.

  This needs to be a single GenServer to avoid race conditions
  """
  use GenServer

  require Logger

  alias ExSync.BeamWatcher
  alias ExSync.SrcWatcher
  alias ExSync.SyncWatcher

  defmodule State do
    defstruct [
      :src_watcher_pid,
      :src_watcher_state,
      :beam_watcher_pid,
      :beam_watcher_state,
      :sync_watcher_state
    ]
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def sync do
    GenServer.call(__MODULE__, :sync, :infinity)
  end

  @impl GenServer
  def init(_opts) do
    # Subscribe to both file system sets of directories
    {src_watcher_pid, src_watcher_state} =
      if ExSync.Config.src_watcher_enabled() do
        SrcWatcher.subscribe()
      else
        {nil, nil}
      end

    {beam_watcher_pid, beam_watcher_state} = BeamWatcher.subscribe()
    sync_watcher_state = SyncWatcher.init()

    state = %State{
      src_watcher_pid: src_watcher_pid,
      src_watcher_state: src_watcher_state,
      beam_watcher_pid: beam_watcher_pid,
      beam_watcher_state: beam_watcher_state,
      sync_watcher_state: sync_watcher_state
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info(
        {:file_event, src_watcher_pid, event},
        %State{src_watcher_pid: src_watcher_pid} = state
      ) do
    src_watcher_state = SrcWatcher.handle_file_event(event, state.src_watcher_state)

    {:noreply, %State{state | src_watcher_state: src_watcher_state}}
  end

  def handle_info(
        {:file_event, beam_watcher_pid, event},
        %State{beam_watcher_pid: beam_watcher_pid} = state
      ) do
    beam_watcher_state = BeamWatcher.handle_file_event(event, state.beam_watcher_state)
    {:noreply, %State{state | beam_watcher_state: beam_watcher_state}}
  end

  def handle_info({SrcWatcher, event}, state) do
    src_watcher_state = SrcWatcher.handle_event(event, state.src_watcher_state)
    {:noreply, %State{state | src_watcher_state: src_watcher_state}}
  end

  def handle_info({BeamWatcher, event}, state) do
    beam_watcher_state = BeamWatcher.handle_event(event, state.beam_watcher_state)
    {:noreply, %State{state | beam_watcher_state: beam_watcher_state}}
  end

  def handle_info({SyncWatcher, event}, state) do
    sync_watcher_state = SyncWatcher.handle_event(event, state.sync_watcher_state)
    {:noreply, %State{state | sync_watcher_state: sync_watcher_state}}
  end

  def handle_info({:sync_done, froms}, state) do
    Enum.each(froms, &GenServer.reply(&1, :ok))

    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:sync, from, %State{} = state) do
    {sync_watcher_state, src_watcher_state, beam_watcher_state} =
      SyncWatcher.sync(
        state.sync_watcher_state,
        state.src_watcher_state,
        state.beam_watcher_state,
        from
      )

    {:noreply,
     %State{
       state
       | sync_watcher_state: sync_watcher_state,
         src_watcher_state: src_watcher_state,
         beam_watcher_state: beam_watcher_state
     }}
  end
end

defmodule ExSync.SyncWatcher do
  alias ExSync.BeamWatcher
  alias ExSync.SrcWatcher

  defmodule State do
    defstruct [:froms, :src_watcher_done, :beam_watcher_done]
  end

  def init, do: initial_state()

  def sync(%State{froms: []}, src_watcher_state, beam_watcher_state, from) do
    state = %State{}

    {src_watcher_state, src_watcher_done} =
      case SrcWatcher.sync(src_watcher_state) do
        {:waiting, src_watcher_state} -> {src_watcher_state, false}
        {:done, src_watcher_state} -> {src_watcher_state, true}
      end

    {beam_watcher_state, beam_watcher_done} =
      case BeamWatcher.sync(beam_watcher_state) do
        {:waiting, src_watcher_state} -> {src_watcher_state, false}
        {:done, src_watcher_state} -> {src_watcher_state, true}
      end

    state =
      %State{
        state
        | froms: [from],
          src_watcher_done: src_watcher_done,
          beam_watcher_done: beam_watcher_done
      }
      |> send_message_if_done()

    {state, src_watcher_state, beam_watcher_state}
  end

  def sync(%State{froms: froms} = state, _, _, from) do
    %State{state | froms: [from | froms]}
  end

  def done(SrcWatcher) do
    send(self(), {__MODULE__, {:sync_done, SrcWatcher}})
  end

  def done(BeamWatcher) do
    send(self(), {__MODULE__, {:sync_done, BeamWatcher}})
  end

  def handle_event({:sync_done, SrcWatcher}, %State{} = state) do
    %State{state | src_watcher_done: true}
    |> send_message_if_done()
  end

  def handle_event({:sync_done, BeamWatcher}, %State{} = state) do
    %State{state | beam_watcher_done: true}
    |> send_message_if_done()
  end

  def send_message_if_done(%State{src_watcher_done: true, beam_watcher_done: true, froms: froms}) do
    send(self(), {:sync_done, froms})
    initial_state()
  end

  def send_message_if_done(%State{} = state), do: state

  defp initial_state do
    %State{froms: [], src_watcher_done: false, beam_watcher_done: false}
  end
end

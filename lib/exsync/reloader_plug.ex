defmodule ExSync.ReloaderPlug do
  def init(_opts), do: nil

  def call(conn, _opts) do
    ExSync.SrcMonitor.sync()
    ExSync.BeamMonitor.sync()

    conn
  end
end

defmodule ExSync.ReloaderPlug do
  @moduledoc """

  """

  def init(_opts), do: nil

  def call(conn, _opts) do
    ExSync.Logger.debug("ExSync ReloaderPlug running")
    # ExSync.sync()
    ExSync.Logger.debug("ExSync ReloaderPlug done")

    conn
  end
end

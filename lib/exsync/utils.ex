defmodule ExSync.Utils do
  require Logger

  def recomplete do
    src_dir = ExSync.Config.app_source_dir()

    case System.cmd("mix", ["compile"], cd: src_dir, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> log_error(output)
    end
  end

  def unload(module) when is_atom(module) do
    module |> :code.purge()
    module |> :code.delete()
  end

  def unload(beam_path) do
    beam_path |> Path.basename(".beam") |> String.to_atom() |> unload
  end

  # beam file path
  def reload(beam_path) do
    file = beam_path |> to_charlist
    {:ok, binary, _} = :erl_prim_loader.get_file(file)
    module = beam_path |> Path.basename(".beam") |> String.to_atom()
    :code.load_binary(module, file, binary)
  end

  defp log_error(string) do
    Logger.error(string)
  end
end

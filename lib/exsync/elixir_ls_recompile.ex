defmodule ExSync.ElixirLSRecompile do
  require Logger

  def recompile do
    opts = [load_all_modules?: false]

    case reload_project() do
      {:ok, _mixfile_diagnostics} ->
        # if we won't do it elixir >= 1.11 warns that protocols have already been consolidated
        purge_consolidated_protocols()
        {status, _diagnostics} = compile()

        if status in [:ok, :noop] and Keyword.get(opts, :load_all_modules?) do
          load_all_modules()
        end

        Logger.info("Recompile success")

      {:error, mixfile_diagnostics} ->
        Logger.info("Recompile error: #{inspect mixfile_diagnostics, pretty: true}")

      :no_mixfile ->
        Logger.info("Recompile without mixfile")
    end
  end

  defp reload_project do
    mixfile = Path.absname(System.get_env("MIX_EXS") || "mix.exs")

    if File.exists?(mixfile) do
      # FIXME: Private API
      case Mix.ProjectStack.peek() do
        %{file: ^mixfile, name: module} ->
          # FIXME: Private API
          Mix.Project.pop()
          purge_module(module)

        _ ->
          :ok
      end

      Mix.Task.clear()

      # Override build directory to avoid interfering with other dev tools
      # FIXME: Private API
      # Mix.ProjectStack.post_config(build_path: ".elixir_ls/build")

      # We can get diagnostics if Mixfile fails to load
      {status, diagnostics} =
        case Kernel.ParallelCompiler.compile([mixfile]) do
          {:ok, _, warnings} ->
            {:ok, Enum.map(warnings, &mixfile_diagnostic(&1, :warning))}

          {:error, errors, warnings} ->
            {
              :error,
              Enum.map(warnings, &mixfile_diagnostic(&1, :warning)) ++
                Enum.map(errors, &mixfile_diagnostic(&1, :error))
            }
        end

      if status == :ok do
        # The project may override our logger config, so we reset it after loading their config
        logger_config = Application.get_all_env(:logger)
        Mix.Task.run("loadconfig")
        Application.put_all_env([logger: logger_config], persistent: true)
      end

      {status, diagnostics}
    else
      msg =
        "No mixfile found in project. " <>
          "To use a subdirectory, set `elixirLS.projectDir` in your settings"

      Logger.info(msg <> ". Looked for mixfile at #{inspect(mixfile)}")

      :no_mixfile
    end
  end

  defp compile do
    case Mix.Task.run("compile", ["--return-errors", "--ignore-module-conflict"]) do
      {status, diagnostics} when status in [:ok, :error, :noop] and is_list(diagnostics) ->
        {status, diagnostics}

      status when status in [:ok, :noop] ->
        {status, []}

      _ ->
        {:ok, []}
    end
  end

  defp purge_module(module) do
    :code.purge(module)
    :code.delete(module)
  end

  def mixfile_diagnostic({file, line, message}, severity) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "ElixirLS",
      file: file,
      position: line,
      message: message,
      severity: severity
    }
  end

  defp purge_consolidated_protocols do
    config = Mix.Project.config()
    path = Mix.Project.consolidation_path(config)

    with {:ok, beams} <- File.ls(path) do
      Enum.map(beams, &(&1 |> Path.rootname(".beam") |> String.to_atom() |> purge_module()))
    else
      {:error, :enoent} ->
        # consolidation_path does not exist
        :ok

      {:error, reason} ->
        Logger.warning("Unable to purge consolidated protocols from #{path}: #{inspect(reason)}")
    end

    # NOTE this implementation is based on https://github.com/phoenixframework/phoenix/commit/b5580e9
    # calling `Code.delete_path(path)` may be unnecessary in our case
    Code.delete_path(path)
  end

  def load_all_modules do
    apps =
      cond do
        Mix.Project.umbrella?() ->
          Mix.Project.apps_paths() |> Map.keys()

        app = Keyword.get(Mix.Project.config(), :app) ->
          [app]

        true ->
          []
      end

    Enum.each(apps, fn app ->
      true = Code.prepend_path(Path.join(Mix.Project.build_path(), "lib/#{app}/ebin"))

      case Application.load(app) do
        :ok -> :ok
        {:error, {:already_loaded, _}} -> :ok
      end
    end)
  end

end

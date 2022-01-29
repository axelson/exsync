defmodule ExSync.IExRecompile do
  @moduledoc """
  Recompile strategy based on `IEx.Helpers.recompile/1`

  Uses code from Elixir licensed Apache License Version 2.0
  """
  require Logger

  def recompile() do
    if mix_started?() do
      config = Mix.Project.config()
      consolidation = Mix.Project.consolidation_path(config)
      reenable_tasks(config)

      # No longer allow consolidations to be accessed.
      Code.delete_path(consolidation)
      purge_protocols(consolidation)

      # Pass ["--force"] as an argument to force recompilation
      {result, _} = Mix.Task.run("compile", [])
      compile_deps()

      # Reenable consolidation and allow them to be loaded.
      Code.prepend_path(consolidation)
      purge_protocols(consolidation)

      result
    else
      IO.puts(IEx.color(:eval_error, "Mix is not running. Please start IEx with: iex -S mix"))
      :error
    end
  end

  defp mix_started? do
    List.keyfind(Application.started_applications(), :mix, 0) != nil
  end

  # TODO: Rename to be compilation centric
  defp reenable_tasks(config) do
    Mix.Task.reenable("compile")
    Mix.Task.reenable("compile.all")
    Mix.Task.reenable("compile.protocols")
    compilers = config[:compilers] || Mix.compilers()
    Enum.each(compilers, &Mix.Task.reenable("compile.#{&1}"))
  end

  defp purge_protocols(path) do
    case File.ls(path) do
      {:ok, beams} ->
        Enum.each(beams, fn beam ->
          module = beam |> Path.rootname() |> String.to_atom()
          :code.purge(module)
          :code.delete(module)
        end)

      {:error, _} ->
        :ok
    end
  end

  # Based on Phoenix.CodeReloader
  defp compile_deps do
    compilers = [:elixir]
    mix_compile_deps(Mix.Dep.cached(), compilers, timestamp())
  end

  defp mix_compile_deps(deps, compilers, timestamp) do
    for dep <- deps,
      dep.opts[:path] != nil,
      dep.app != :exsync do
      Mix.Dep.in_dependency(dep, fn _ ->
        Logger.info("dep.app: #{inspect(dep.app)}")
        mix_compile_unless_stale_config(dep, compilers, timestamp)
      end)
    end
  end

  defp timestamp, do: System.system_time(:second)

  defp mix_compile_unless_stale_config(dep, compilers, timestamp) do
    manifests = Mix.Tasks.Compile.Elixir.manifests()
    configs = Mix.Project.config_files()
    config = Mix.Project.config()

    case Mix.Utils.extract_stale(configs, manifests) do
      [] ->
        # If the manifests are more recent than the timestamp,
        # someone updated this app behind the scenes, so purge all beams.
        if Mix.Utils.stale?(manifests, [timestamp]) do
          Logger.info("Purging modules for #{dep.app}!")
          purge_modules(Path.join(Mix.Project.app_path(config), "ebin"))
        end

        mix_compile(compilers, config)

      files ->
        raise """
        could not compile application: #{Mix.Project.config()[:app]}.

        You must restart your server after changing the following files:

          * #{Enum.map_join(files, "\n  * ", &Path.relative_to_cwd/1)}

        """
    end
  end

  defp mix_compile(compilers, config) do
    all = config[:compilers] || Mix.compilers()

    compilers =
      for compiler <- compilers, compiler in all do
        Mix.Task.reenable("compile.#{compiler}")
        compiler
      end

    # We call build_structure mostly for Windows so new
    # assets in priv are copied to the build directory.
    Mix.Project.build_structure(config)
    results = Enum.map(compilers, &Mix.Task.run("compile.#{&1}", []))

    # Results are either {:ok, _} | {:error, _}, {:noop, _} or
    # :ok | :error | :noop. So we use proplists to do the unwrapping.
    cond do
      :proplists.get_value(:error, results, false) ->
        exit({:shutdown, 1})

      :proplists.get_value(:ok, results, false) && config[:consolidate_protocols] ->
        Mix.Task.reenable("compile.protocols")
        Mix.Task.run("compile.protocols", [])
        :ok

      true ->
        :ok
    end
  end

  defp purge_modules(path) do
    with {:ok, beams} <- File.ls(path) do
      Enum.map(beams, &(&1 |> Path.rootname(".beam") |> String.to_atom() |> purge_module()))
    end
  end

  defp purge_module(module) do
    :code.purge(module)
    :code.delete(module)
  end
end

defmodule TestCluster do
  def start_nodes(prefix, amount, options \\ [])
      when (is_binary(prefix) or is_atom(prefix)) and is_integer(amount) do
    hidden = Keyword.get(options, :hidden, false)

    nodes =
      Enum.map(1..amount, fn idx ->
        {:ok, name} =
          :slave.start_link(
            '127.0.0.1',
            :"#{prefix}#{idx}",
            '-loader inet -hosts 127.0.0.1 -setcookie "#{:erlang.get_cookie()}"' ++
              if(hidden, do: ' -hidden', else: '')
          )

        name
      end)

    rpc = &({_, []} = :rpc.multicall(nodes, &1, &2, &3))

    rpc.(:code, :add_paths, [:code.get_path()])

    rpc.(Application, :ensure_all_started, [:mix])
    rpc.(Application, :ensure_all_started, [:logger])

    rpc.(Logger, :configure, [[level: Logger.level()]])
    rpc.(Mix, :env, [Mix.env()])

    loaded_apps =
      for {app_name, _, _} <- Application.loaded_applications() do
        base = Application.get_all_env(app_name)

        environment =
          options
          |> Keyword.get(:environment, [])
          |> Keyword.get(app_name, [])
          |> Keyword.merge(base, fn _, v, _ -> v end)

        for {key, val} <- environment do
          rpc.(Application, :put_env, [app_name, key, val])
        end

        app_name
      end

    ordered_apps = Keyword.get(options, :applications, loaded_apps)

    for app_name <- ordered_apps, app_name in loaded_apps do
      rpc.(Application, :ensure_all_started, [app_name])
    end

    for file <- Keyword.get(options, :files, []) do
      rpc.(Code, :require_file, [file])
    end

    nodes
  end

  def retry_until_false(f, timeout \\ 5000), do: retry_until_true(fn -> !f.() end, timeout)

  @doc """
    Some operations need time to converge so we need to wait
    until it completes. But wait as little time as possible.
  """
  def retry_until_true(f, timeout \\ 5000) do
    target_time = :erlang.monotonic_time(:millisecond) + timeout

    Stream.unfold(false, fn stop? ->
      if :erlang.monotonic_time(:millisecond) > target_time or stop? do
        nil
      else
        result = f.()
        if !result, do: Process.sleep(20)
        {result, result}
      end
    end)
    |> Enum.any?()
  end
end

:ok = LocalCluster.start()
ExUnit.start()

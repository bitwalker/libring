defmodule ConsistentHashRing.App do
  @moduledoc false
  use Application
  require Logger

  def start(_type, _args) do
    import Supervisor.Spec

    # Start the ring supervisor
    children = [
      worker(ConsistentHashRing.Worker, [], restart: :transient)
    ]
    {:ok, pid} = Supervisor.start_link(children, strategy: :simple_one_for_one, name: ConsistentHashRing.Supervisor)

    # Add any preconfigured rings
    Enum.each(Application.get_env(:libring, :rings, []), fn
      {name, config} ->
        {:ok, _pid} = ConsistentHashRing.Managed.new(name, config)
        Logger.info "[libring] started managed ring #{inspect name}"
      name when is_atom(name) ->
        {:ok, _pid} = ConsistentHashRing.Managed.new(name)
        Logger.info "[libring] started managed ring #{inspect name}"
    end)

    # Application started
    {:ok, pid}
  end
end

defmodule HashRing.App do
  @moduledoc false
  use Application
  require Logger

  def start(_type, _args) do
    # Start the ring supervisor
    {:ok, pid} = DynamicSupervisor.start_link(__MODULE__, nil, name: HashRing.Supervisor)

    # Add any preconfigured rings
    Enum.each(Application.get_env(:libring, :rings, []), fn
      {name, config} ->
        {:ok, _pid} = HashRing.Managed.new(name, config)
        Logger.info "[libring] started managed ring #{inspect name}"
      name when is_atom(name) ->
        {:ok, _pid} = HashRing.Managed.new(name)
        Logger.info "[libring] started managed ring #{inspect name}"
    end)

    # Application started
    {:ok, pid}
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end

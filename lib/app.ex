defmodule HashRing.App do
  @moduledoc false
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    # Start the ring supervisor
    children = [
      worker(HashRing.Worker, [], restart: :transient)
    ]
    {:ok, pid} = Supervisor.start_link(children, strategy: :simple_one_for_one, name: HashRing.Supervisor)

    # Add any preconfigured rings
    Enum.each(Application.get_env(:libring, :rings, []), fn
      {name, config} ->
        :ok = HashRing.Managed.new(name, config)
      name when is_atom(name) ->
        :ok = HashRing.Managed.new(name)
    end)

    # Application started
    {:ok, pid}
  end
end

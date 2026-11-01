defmodule HashRing.ManagedTest do
  use ExUnit.Case, async: true
  doctest HashRing.Managed

  test "multi-node lookup wraps through both managed read paths" do
    {:ok, pid} = HashRing.Managed.new(:managed_wraparound)
    on_exit(fn -> DynamicSupervisor.terminate_child(HashRing.Supervisor, pid) end)
    :ok = HashRing.Managed.add_nodes(pid, [:a@localhost, :b@localhost])
    assert HashRing.Managed.key_to_nodes(pid, 14, 2) == [:a@localhost, :b@localhost]

    assert HashRing.Managed.key_to_nodes(:managed_wraparound, 14, 2) == [
             :a@localhost,
             :b@localhost
           ]
  end
end

# Uses only ExUnit so consumer compatibility is independent of development dependencies.
ExUnit.start()

defmodule ConsumerSmokeTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  test "runs on the requested consumer runtime" do
    if expected = System.get_env("EXPECTED_ELIXIR") do
      assert System.version() == expected
    end

    if expected = System.get_env("EXPECTED_OTP") do
      assert to_string(:erlang.system_info(:otp_release)) == expected
    end
  end

  test "stateless routing and membership work without tooling dependencies" do
    ring = HashRing.new("a") |> HashRing.add_node("b", 64)
    assert Enum.sort(HashRing.nodes(ring)) == ["a", "b"]
    assert HashRing.key_to_node(ring, "key") in ["a", "b"]
    assert length(HashRing.key_to_nodes(ring, "key", 1)) == 1
    assert HashRing.nodes(HashRing.remove_node(ring, "b")) == ["a"]
    assert HashRing.key_to_node(HashRing.new(), "key") == {:error, {:invalid_ring, :no_nodes}}
  end

  test "managed application startup and both read paths work" do
    {:ok, pid} = HashRing.Managed.new(:consumer_smoke)
    on_exit(fn -> DynamicSupervisor.terminate_child(HashRing.Supervisor, pid) end)
    assert :ok = HashRing.Managed.add_nodes(:consumer_smoke, ["a", {"b", 64}])
    assert HashRing.Managed.nodes(pid) == HashRing.Managed.nodes(:consumer_smoke)

    assert HashRing.Managed.key_to_node(pid, "key") ==
             HashRing.Managed.key_to_node(:consumer_smoke, "key")

    assert HashRing.Managed.key_to_nodes(pid, "key", 1) ==
             HashRing.Managed.key_to_nodes(:consumer_smoke, "key", 1)

    assert :ok = HashRing.Managed.remove_node(:consumer_smoke, "b")
    assert HashRing.Managed.nodes(:consumer_smoke) == ["a"]
  end

  test "invalid patterns use the supported Logger warning API" do
    assert capture_log(fn ->
             refute HashRing.Utils.ignore_node?(:node, ["["], [])
             assert HashRing.Utils.ignore_node?(:node, [], ["["])
           end) =~ "invalid"
  end
end

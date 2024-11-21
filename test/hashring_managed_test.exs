defmodule HashRing.ManagedTest do
  use ExUnit.Case, async: true
  doctest HashRing.Managed

  describe "child_spec" do
    test "starts a ring", ctx do
      name = String.to_atom("#{ctx.module}#{ctx.test}")
      assert {:ok, _pid} = start_supervised({HashRing.Managed, [name: name]})
    end
  end
end

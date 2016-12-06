defmodule HashRingUtilsTest do
  use ExUnit.Case, async: true
  doctest HashRing.Utils
  alias HashRing.Utils

  test "ignore_node?/3 with blacklist" do
    blacklist = [
      ~r/^.+_maint_.*$/
    ]
    assert Utils.ignore_node?(:"disp1_maint_18090@127.0.0.1", blacklist, [])
  end

  test "ignore_node?/3 with whitelist" do
    blacklist = [
      ~r/^.+_maint_.*$/
    ]
    whitelist = [
      ~r/^disp1.*$/
    ]
    refute Utils.ignore_node?(:"disp1_maint_18090@127.0.0.1", blacklist, whitelist)
  end
end

defmodule HashRingUtilsTest do
  use ExUnit.Case, async: true
  doctest HashRing.Utils
  alias HashRing.Utils

  test "ignore_node?/3 with blacklist" do
    blacklist = [
      ~r/^.+_maint_.*$/
    ]
    # in blacklist
    assert Utils.ignore_node?(:"disp1_maint_18090@127.0.0.1", blacklist, [])
    # not in blacklist
    refute Utils.ignore_node?(:"disp1_18090@127.0.0.1", blacklist, [])
  end

  test "ignore_node?/3 with whitelist" do
    whitelist = [
      ~r/^disp1.*$/
    ]
    # in whitelist
    refute Utils.ignore_node?(:"disp1_maint_18090@127.0.0.1", [], whitelist)
    # not in whitelist
    assert Utils.ignore_node?(:"maint_18090@127.0.0.1", [], whitelist)
  end

  test "ignore_node?/3 with whitelist and blacklist" do
    blacklist = [
      ~r/^.+_maint_.*$/
    ]
    whitelist = [
      ~r/^disp1.*$/
    ]
    # only in blacklist
    assert Utils.ignore_node?(:"maint_18090@127.0.0.1", blacklist, whitelist)
    # in whitelist and blacklist whitelist takes precedence
    refute Utils.ignore_node?(:"disp1_maint_18090@127.0.0.1", blacklist, whitelist)
    # only in whitelist
    refute Utils.ignore_node?(:"disp1_18090@127.0.0.1", blacklist, whitelist)
    # neither in blacklist nor in whitelist
    assert Utils.ignore_node?(:"18090@127.0.0.1", blacklist, whitelist)
  end

  test "ignore_node?/3 with whitelists and blacklists" do
    blacklist = [
      ~r/^.+_maint1_.*$/,
      ~r/^.+_maint2_.*$/
    ]
    whitelist = [
      ~r/^disp1.*$/,
      ~r/^disp2.*$/
    ]
    # only in blacklist1
    assert Utils.ignore_node?(:"disp3_maint1_18090@127.0.0.1", blacklist, whitelist)
    # only in blacklist2
    assert Utils.ignore_node?(:"disp3_maint2_18090@127.0.0.1", blacklist, whitelist)
    # in blacklist and whitelist1 whitelist takes precedence
    refute Utils.ignore_node?(:"disp1_maint1_18090@127.0.0.1", blacklist, whitelist)
    # in blacklist and whitelist2 whitelist takes precedence
    refute Utils.ignore_node?(:"disp2_maint2_18090@127.0.0.1", blacklist, whitelist)
    # only in whitelist1
    refute Utils.ignore_node?(:"disp1@127.0.0.1", blacklist, whitelist)
    # only in whitelist2
    refute Utils.ignore_node?(:"disp2@127.0.0.1", blacklist, whitelist)
    # neither in blacklist nor in whitelist
    assert Utils.ignore_node?(:"18090@127.0.0.1", blacklist, whitelist)
  end

end

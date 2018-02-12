defmodule HashRing.Utils do
  @moduledoc false
  require Logger

  @type pattern_list :: [String.t | Regex.t]
  @type blacklist :: pattern_list
  @type whitelist :: pattern_list

  @doc """
  An internal function for determining if a given node should be
  included in the ring or excluded, based on a provided blacklist
  and/or whitelist. Both lists should contain either literal strings,
  literal regexes, or regex strings.

  This function only works with nodes which are atoms or strings, and
  will raise an exception if other node name types are used, such as tuples.
  """
  @spec ignore_node?(term(), blacklist, whitelist) :: boolean
  def ignore_node?(node, blacklist, whitelist)

  def ignore_node?(_node, [], []),
    do: false
  def ignore_node?(node, blacklist, whitelist) when is_atom(node),
    do: ignore_node?(Atom.to_string(node), blacklist, whitelist)
  def ignore_node?(node, blacklist, []) when is_binary(node) and is_list(blacklist) do
    Enum.any?(blacklist, fn
      ^node ->
        true
      %Regex{} = pattern ->
        Regex.match?(pattern, node)
      pattern when is_binary(pattern) ->
        case Regex.compile(pattern) do
          {:ok, rx} ->
            Regex.match?(rx, node)
          {:error, reason} ->
            :ok = Logger.warn "[libring] ignore_node?/3: invalid blacklist pattern (#{inspect pattern}): #{inspect reason}"
            false
        end
    end)
  end
  def ignore_node?(node, [], whitelist) when is_binary(node) and is_list(whitelist) do
    Enum.any?(whitelist, fn
      ^node ->
        false
      %Regex{} = pattern ->
        not Regex.match?(pattern, node)
      pattern when is_binary(pattern) ->
        case Regex.compile(pattern) do
          {:ok, rx} ->
            not Regex.match?(rx, node)
          {:error, reason} ->
            :ok = Logger.warn "[libring] ignore_node?/3: invalid whitelist pattern (#{inspect pattern}): #{inspect reason}"
            true
        end
    end)
  end
  def ignore_node?(node, blacklist, whitelist) when is_list(whitelist) and is_list(blacklist) do
    # Criteria for ignoring nodes when both blacklisting and whitelisting is active
    blacklisted? =
      ignore_node?(node, blacklist, [])
    whitelisted? =
      not ignore_node?(node, [], whitelist)
    cond do
      # If it is blacklisted and also whitelisted, then do not ignore
      blacklisted? and whitelisted? ->
        false
      # If it is blacklisted and not also whitelisted, then ignore
      blacklisted? ->
        true
      # If it is not blacklisted and is whitelisted, then do not ignore
      whitelisted? ->
        false
      # If it is not blacklisted and not whitelisted, then ignore
      :else ->
        true
    end
  end
end

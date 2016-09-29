Application.ensure_all_started(:libring)

# The raw datastructure
ring = HashRing.new(:'a@nohost')
ring = HashRing.add_node(ring, :'b@nohost')

# The managed version of the ring is a GenServer
# which means there is overhead when manipulating
# the ring or mapping keys to the ring. This translates
# into being roughly 4-5x slower
{:ok, _pid} = HashRing.Managed.new(:test)
:ok = HashRing.Managed.add_node(:test, :'a@nohost')
:ok = HashRing.Managed.add_node(:test, :'b@nohost')


# NOTE: Uncomment the following after adding voicelayer/hash-ring to your deps
# In my tests, HashRing performs 5-10x better at mapping keys to to the ring,
# and HashRing.Managed is roughly 2x better.
# I'm not entirely sure why this is, as hash_ring is implemented with a NIF, but I
# suspect my gb_tree based implementation is just much more efficient at searching the
# ring, and hash_ring uses a naive search or something, anyway, feel free to test yourself
#_ = :hash_ring.start_link()
#:hash_ring.create_ring("test", 128)
#:hash_ring.add_node("test", "a@nohost")
#:hash_ring.add_node("test", "b@nohost")

# The following is for sile/hash_ring, HashRing performs roughly 2x better,
# when used directly, since sile/hash_ring does not implement a managed process,
# there is no way to compare the HashRing.Managed API, but it is roughly 4x slower
# than sile/hash_ring
#nodes = :hash_ring.list_to_nodes([:a, :b])
#ring2 = :hash_ring.make(nodes)

Benchee.run(%{time: 10}, %{
      "HashRing.key_to_node (direct)" => fn ->
        for i <- 1..100, do: HashRing.key_to_node(ring, {:myapp, i})
      end,
      "HashRings.key_to_node (via process)" => fn ->
        for i <- 1..100, do: HashRing.Managed.key_to_node(:test, {:myapp, i})
      end,
      #"voicelayer/hash_ring.find_node" => fn ->
      #  for i <- 1..100, do: :hash_ring.find_node("test", :erlang.term_to_binary({:myapp, i}))
      #end,
      #"sile/hash_ring.find_node" => fn ->
      #  for i <- 1..100, do: :hash_ring.find_node(:erlang.term_to_binary({:myapp, i}), ring2)
      #end,
})

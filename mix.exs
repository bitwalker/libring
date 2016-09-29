defmodule HashRing.Mixfile do
  use Mix.Project

  def project do
    [app: :libring,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: "A fast consistent hash ring implementation in Elixir",
     package: package,
     docs: docs(),
     deps: deps()]
  end

  def application do
    [applications: [:logger, :crypto],
     mod: {HashRing.App, []}]
  end

  defp deps do
    [
     {:ex_doc, "~> 0.13", only: :dev},
     {:benchee, "~> 0.4", only: :dev},
     # Uncomment the following for benchmarks
     # {:hash_ring, github: "voicelayer/hash-ring", only: :dev},
     # {:hash_ring, ">= 0.0.0", only: :dev},
    ]
  end

  defp package do
    [files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
     maintainers: ["Paul Schoenfelder"],
     licenses: ["MIT"],
     links: %{ "GitHub": "https://github.com/bitwalker/libring" }]
  end

  defp docs do
    [main: "readme",
     formatter_opts: [gfm: true],
     extras: [
       "README.md"
     ]]
  end
end

defmodule HashRing.Mixfile do
  use Mix.Project

  def project do
    [app: :libring,
     version: "1.3.1",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     description: "A fast consistent hash ring implementation in Elixir",
     package: package(),
     docs: docs(),
     deps: deps(),
     dialyzer: [
       flags: ~w(-Wunmatched_returns -Werror_handling -Wrace_conditions -Wno_opaque -Wunderspecs)
     ]]
  end

  def application do
    [applications: [:crypto],
     mod: {HashRing.App, []}]
  end

  defp deps do
    [
     {:ex_doc, "~> 0.13", only: :dev},
     {:benchee, "~> 0.4", only: :dev},
     {:dialyxir, "~> 0.3", only: :dev},
     {:eqc_ex, "~> 1.4", only: [:dev, :test]},
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

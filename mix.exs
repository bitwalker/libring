defmodule HashRing.Mixfile do
  use Mix.Project

  def project do
    [
      app: :libring,
      version: "1.5.0",
      elixir: "~> 1.6",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      description: "A fast consistent hash ring implementation in Elixir",
      package: package(),
      docs: docs(),
      deps: deps(),
      dialyzer: [
        flags: ~w(-Wunmatched_returns -Werror_handling -Wrace_conditions -Wno_opaque -Wunderspecs)
      ],
      preferred_cli_env: [
        docs: :docs,
        "hex.publish": :docs,
        dialyzer: :test,
        "eqc.mini": :test
      ]
    ]
  end

  def application do
    [applications: [:logger, :crypto],
     mod: {HashRing.App, []}]
  end

  defp deps do
    [
     {:ex_doc, "~> 0.21", only: [:docs]},
     {:benchee, "~> 1.0", only: [:dev]},
     {:dialyxir, "~> 1.0", only: [:test]},
     {:eqc_ex, "~> 1.4", only: [:test]},
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

defmodule HashRing.Mixfile do
  use Mix.Project

  @source_url "https://github.com/bitwalker/libring"
  @version "1.6.0"

  def project do
    [
      app: :libring,
      version: @version,
      elixir: "~> 1.6",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "A fast consistent hash ring implementation in Elixir",
      package: package(),
      docs: docs(),
      deps: deps(),
      dialyzer: [
        flags: ~w(-Wunmatched_returns -Werror_handling -Wrace_conditions -Wno_opaque -Wunderspecs)
      ],
      preferred_cli_env: [
        docs: :docs,
        dialyzer: :test,
        "hex.publish": :docs
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {HashRing.App, []}
    ]
  end

  defp deps do
    [
      # Uncomment ONLY ONE of the following dep for benchmarks
      # {:hash_ring, github: "voicelayer/hash-ring", only: :dev},
      # {:hash_ring, ">= 0.0.0", only: :dev},

      {:ex_doc, ">= 0.0.0", only: [:docs]},
      {:benchee, "~> 1.0", only: [:dev]},
      {:dialyxir, "~> 1.0", only: [:test], runtime: false},
      {:stream_data, "~> 0.5", only: [:test]}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["Paul Schoenfelder"],
      licenses: ["MIT"],
      links: %{GitHub: @source_url}
    ]
  end

  defp docs do
    [
      extras: [{:"README.md", [title: "Overview"]}],
      main: "readme",
      formatter_opts: [gfm: true],
      source_url: @source_url,
      source_ref: @version
    ]
  end
end

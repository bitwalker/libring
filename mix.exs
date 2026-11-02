defmodule HashRing.Mixfile do
  use Mix.Project

  @source_url "https://github.com/bitwalker/libring"
  @version "1.8.0"
  @preferred_envs [docs: :docs, dialyzer: :test, "hex.publish": :docs]

  def project do
    [
      app: :libring,
      version: @version,
      elixir: "~> 1.11",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: "A fast consistent hash ring implementation in Elixir",
      package: package(),
      docs: docs(),
      deps: deps(),
      dialyzer: [
        flags: [:unmatched_returns, :error_handling, :no_opaque, :underspecs],
        plt_local_path: "_build/plts",
        plt_core_path: "_build/plts"
      ]
    ] ++ legacy_cli_config()
  end

  def cli, do: [preferred_envs: @preferred_envs]

  # Mix versions before 1.15 do not read cli/0.
  defp legacy_cli_config do
    if Version.match?(System.version(), "< 1.15.0"),
      do: [preferred_cli_env: @preferred_envs],
      else: []
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

      {:ex_doc, "~> 0.40", only: [:docs], runtime: false},
      {:benchee, "~> 1.0", only: [:dev]},
      {:dialyxir, "~> 1.0", only: [:test], runtime: false},
      {:stream_data, "~> 1.0", only: [:test]}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "CHANGELOG.md", "LICENSE.md"],
      maintainers: ["Paul Schoenfelder"],
      licenses: ["MIT"],
      links: %{GitHub: @source_url}
    ]
  end

  defp docs do
    [
      extras: [{:"README.md", [title: "Overview"]}, "CHANGELOG.md"],
      main: "readme",
      formatter_opts: [gfm: true],
      source_url: @source_url,
      source_ref: System.get_env("DOCS_SOURCE_REF", "main")
    ]
  end
end

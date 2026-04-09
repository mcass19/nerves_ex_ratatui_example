defmodule NervesExRatatuiExample.MixProject do
  use Mix.Project

  @app :nerves_ex_ratatui_example
  @version "0.1.0"
  @all_targets [:rpi, :rpi0, :rpi0_2, :rpi2, :rpi3, :rpi4, :rpi5]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      archives: [nerves_bootstrap: "~> 1.15"],
      listeners: listeners(Mix.target(), Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {NervesExRatatuiExample.Application, []}
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.13", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.4.0"},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      {:nerves_runtime, "~> 0.13.12"},

      # Dependencies for all targets except :host
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},

      # TUI
      {:ex_ratatui, "~> 0.6.1"},

      # Dependencies for specific targets
      {:nerves_system_rpi, "~> 2.0", runtime: false, targets: :rpi},
      {:nerves_system_rpi0, "~> 2.0", runtime: false, targets: :rpi0},
      {:nerves_system_rpi0_2, "~> 2.0", runtime: false, targets: :rpi0_2},
      {:nerves_system_rpi2, "~> 2.0", runtime: false, targets: :rpi2},
      {:nerves_system_rpi3, "~> 2.0", runtime: false, targets: :rpi3},
      {:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4},
      {:nerves_system_rpi5, "~> 2.0", runtime: false, targets: :rpi5}
    ]
  end

  def release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end

  defp listeners(_, _), do: []
end

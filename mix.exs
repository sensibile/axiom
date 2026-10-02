defmodule Axiom.MixProject do
  use Mix.Project

  def cli, do: [preferred_envs: [check: :test]]

  def project do
    [
      app: :axiom,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: ["lib"],
      deps: deps(),
      dialyzer: [
        plt_local_path: ".cache/plt/project.plt",
        plt_core_path: ".cache/plt",
        plt_add_apps: [:mix]
      ],
      aliases: [check: ["format --check-formatted", "compile --warnings-as-errors", "test"]]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp deps do
    # Project-local copies of already cached Hex packages; no global installation.
    runtime =
      for name <- [:postgrex, :db_connection, :decimal, :telemetry, :jason] do
        {name, path: "vendor/#{name}", override: true}
      end

    tools =
      for name <- [:credo, :dialyxir, :erlex, :file_system, :bunt] do
        {name, path: "vendor/#{name}", only: [:dev, :test], runtime: false, override: true}
      end

    runtime ++ tools
  end
end

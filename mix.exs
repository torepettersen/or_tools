defmodule OrTools.MixProject do
  use Mix.Project

  def project do
    [
      app: :or_tools,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_env: &make_env/0,
      deps: deps()
    ]
  end

  defp make_env do
    %{
      "FINE_INCLUDE_DIR" => Fine.include_dir(),
      "ORTOOLS_PREFIX" => System.get_env("ORTOOLS_PREFIX", "/usr/local")
    }
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:fine, "~> 0.1.0", runtime: false},
      {:elixir_make, "~> 0.9.0", runtime: false}
    ]
  end
end

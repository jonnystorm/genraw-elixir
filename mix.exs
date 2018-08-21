defmodule GenRaw.MixProject do
  use Mix.Project

  def project do
    [ app: :genraw_ex,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [ extra_applications: [:logger],
      env: [
        procket_path: "/usr/local/bin/procket",
      ],
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [ {:procket, git: "https://github.com/msantos/procket.git"},
    ]
  end
end

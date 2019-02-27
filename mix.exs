defmodule GenRaw.MixProject do
  use Mix.Project

  def project do
    [ app: :gen_raw_ex,
      version: "0.2.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # ExDoc
      name: "GenRaw",
      source_url: "https://gitlab.com/jonnystorm/genraw-elixir",
      docs: [
        main: "GenRaw",
        extras: ~w(README.md),
        output: "public",
        markdown_processor: ExDoc.Markdown.Cmark,
      ],
      # Dialyxir
      dialyzer: [
        add_plt_apps: [
          :logger,
          :procket,
        ],
        ignore_warnings: "dialyzer.ignore",
        flags: [
          :unmatched_returns,
          :error_handling,
          :race_conditions,
          :underspecs,
        ],
      ],
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
    [ { :procket,
        git: "https://github.com/msantos/procket.git"
      },
      {:ex_doc, "~> 0.19", only: :dev, runtime: false},
      {:cmark, "~> 0.6", only: :dev},
    ]
  end
end

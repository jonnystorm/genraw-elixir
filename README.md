# GenRaw

An Elixir GenServer for using raw packet sockets.

This module is largely a demo of Michael Santos's excellent
[`procket`](https://github.com/msantos/procket) library for
Erlang. It really just encodes my knowledge about how to use
`procket`, but perhaps someone else will find it valuable.

**N.B.**: Using `procket` with Erlang ports is [**broken**
in OTP 21](https://bugs.erlang.org/browse/ERL-692).

## Installation

In your `mix.exs`, simply add

```elixir
def deps do
  [ { :genraw_ex,
      git: "https://gitlab.com/jonnystorm/genraw-elixir.git"
    },
  ]
end
```

Please see [procket](https://github.com/msantos/procket) for
how to set appropriate permissions on the `procket` binary.

## Configuration

By default, GenRaw assumes the `procket` binary is at
`/usr/local/bin/procket`:

```elixir
iex> Application.get_all_env :genraw_ex
[procket_path: "/usr/local/bin/procket"]
```

Feel free to change this in your `config.exs`:

```elixir
config :genraw_ex,
  procket_path: "/usr/bin/procket"
```


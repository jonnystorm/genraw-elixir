# GenRaw

An Elixir GenServer for using raw packet sockets.

This module is largely a demo of Michael Santos's excellent
[`procket`](https://github.com/msantos/procket) library for
Erlang. It really just encodes my knowledge about how to use
`procket`, but perhaps someone else will find it valuable.

**N.B.**: Using `procket` with Erlang ports is [**broken**
in OTP 21.0](https://bugs.erlang.org/browse/ERL-692).
However, this was fixed in OTP 21.1.

Documentation is available at
[https://jonnystorm.gitlab.io/genraw-elixir](
 https://jonnystorm.gitlab.io/genraw-elixir
)

## Installation

In your `mix.exs`, simply add

```elixir
def deps do
  [ { :gen_raw_ex,
      git: "https://gitlab.com/jonnystorm/genraw-elixir.git"
    },
  ]
end
```

Please see [procket](https://github.com/msantos/procket) for
how to set appropriate permissions on the `procket` binary.

In case you observe `{:error, :einval}` when sending data,
some interfaces may require giving the `CAP_SYS_RAWIO`
capability to your `beam.smp`, in addition to `CAP_NET_RAW`.
I discovered this while working on an Asus C101PA with
Marvell wireless NIC.

## Configuration

By default, GenRaw assumes the `procket` binary is at
`/usr/local/bin/procket`:

```elixir
iex> Application.get_all_env :gen_raw_ex
[procket_path: "/usr/local/bin/procket"]
```

Feel free to change this in your `config.exs`:

```elixir
config :gen_raw_ex,
  procket_path: "/usr/bin/procket"
```


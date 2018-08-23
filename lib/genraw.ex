# Copyright © 2018 Jonathan Storm <jds@idio.link> This work
# is free. You can redistribute it and/or modify it under
# the terms of the Do What The Fuck You Want To Public
# License, Version 2, as published by Sam Hocevar. See the
# COPYING.WTFPL file for more details.

defmodule GenRaw do
  use GenServer

  alias GenRaw.Utility

  defp procket_path,
    do: Application.get_env(:genraw_ex, :procket_path)

  @impl true
  def init([interface]) do
    erl_if   = :binary.bin_to_list interface
    progname = :binary.bin_to_list procket_path()

    {:ok, fd} =
      :procket.open 0,       # no port
        progname:  progname,
        family:    :packet,  # AF_PACKET
        type:      :raw,     # SOCK_RAW
        protocol:  0x0300    # little-endian ETH_P_ALL

    if_index = :packet.ifindex(fd, erl_if)

    :ok = :packet.bind(fd, if_index)

    {:ok, %{fd: fd}}
  end

  @impl true
  def terminate(_, state),
    do: :procket.close state.fd

  @impl true
  def handle_call(:recv, _, state) do
    result = _recv state.fd

    {:reply, result, state}
  end

  def handle_call({:snd, data}, _, state) do
    result = _snd(state.fd, data)

    {:reply, result, state}
  end

  def handle_call(:fd, _, state),
    do: {:reply, state.fd, state}

  defp _recv(fd),
    do: :procket.recv(fd, 4096)

  def recv(pid) when is_pid(pid),
    do: GenServer.call(pid, :recv)

  defp _snd(fd, data),
    do: :procket.sendto(fd, data)

  def snd(pid, data)
      when is_pid(pid)
       and is_binary(data),
    do: GenServer.call(pid, {:snd, data})

  defp _capture(fd) do
    with {:ok, data} <- _recv fd do
      captured = Utility.parse_frame data

      {:erlang.system_time, captured}
      |> inspect
      |> Code.format_string!([line_length: 80])
      |> IO.puts
    end

    _capture fd
  end

  def capture(pid) do
    pid
    |> GenServer.call(:fd)
    |> _capture
  end

  def start_link(interface),
    do: GenServer.start_link(__MODULE__, [interface])

  def stop(pid),
    do: GenServer.stop pid
end

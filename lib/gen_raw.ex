# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule GenRaw do
  @moduledoc """
  An Elixir GenServer for using raw packet sockets.

  This module is largely a demo of Michael Santos's
  excellent `procket` library for Erlang. It really just
  encodes my knowledge about how to use `procket`, but
  perhaps someone else will find it valuable.

  **N.B.**: Using `procket` with Erlang ports is broken in
  OTP 21.0. However, this was fixed in OTP 21.1.
  """

  use GenServer

  alias GenRaw.Utility

  defp procket_path,
    do: Application.get_env(:gen_raw_ex, :procket_path)

  def handle_info(
    {port, {:data, data}},
    %{port: port} = state
  ) do
    if state.q_len < state.max_q_len do
      next_state =
        %{state |
          queue: :queue.in(data, state.queue),
          q_len: state.q_len + 1,
        }

      {:noreply, next_state}
    else
      next_state =
        %{state|dropped: state.dropped + 1}

      {:noreply, next_state}
    end
  end

  def handle_call({:open, _}, _from, %{fd: _} = state),
    do: {:reply, {:error, :ealready}, state}

  def handle_call({:open, target0}, _from, state) do
    active?   = target0 != nil
    target    = target0 || self()
    progname  = :binary.bin_to_list(procket_path())
    {:ok, fd} =
      :procket.open(0,      # no port
        progname: progname,
        family:   :packet,  # AF_PACKET
        type:     :raw,     # SOCK_RAW
        protocol: 0x0300    # little-endian ETH_P_ALL
      )

    port = Port.open({:fd, fd, fd}, [:binary])

    _ = Port.connect(port, target)

    next_state =
      state
      |> Map.put(:fd, fd)
      |> Map.put(:port, port)
      |> Map.put(:active, active?)

    if active? do
      {:reply, {:ok, port}, next_state}
    else
      {:reply, :ok, next_state}
    end
  end

  def handle_call(:close, _from, %{fd: fd} = state) do
    _ = Port.close(state.port)

    result = :procket.close(fd)

    next_state = Map.drop(state, [:fd, :port, :active])

    {:reply, result, next_state}
  end

  def handle_call(:close, _from, state),
    do: {:reply, {:error, :enotconn}, state}

  def handle_call(
    {:receive, _},
    _from,
    %{active: true} = state
  ),
    do: {:reply, {:error, :eopnotsupp}, state}

  def handle_call(
    {:receive, count0},
    _from,
    %{active: false} = state
  ) do
    count = min(state.q_len, count0)

    {out_q, next_q} =
      :queue.split(count, state.queue)

    next_state =
      %{state |
        queue:    next_q,
        q_len:    state.q_len - count,
        serviced: state.serviced + count,
      }

    out = :queue.to_list(out_q)

    {:reply, {:ok, out}, next_state}
  end

  def handle_call({:receive, _}, _from, state),
    do: {:reply, {:error, :enotconn}, state}

  def handle_call(
    {:receive_parsed, _, _},
    _from,
    %{active: true} = state
  ),
    do: {:reply, {:error, :eopnotsupp}, state}

  def handle_call(
    {:receive_parsed, filter, count},
    _from,
    %{active: false} = state
  ) do
    {reply, next_state} =
      _find_match(state, filter, count, [])

    {:reply, reply, next_state}
  end

  def handle_call({:receive_parsed, _, _}, _from, state),
    do: {:reply, {:error, :enotconn}, state}

  def handle_call(
    {:send, if_name, data},
    _from,
    %{fd: fd} = state
  ) do
    erl_if   = :binary.bin_to_list(if_name)
    if_index = :packet.ifindex(fd, erl_if)
    result   = :packet.send(fd, if_index, data)

    {:reply, result, state}
  end

  def handle_call({:send, _, _}, _from, state),
    do: {:reply, {:error, :enotconn}, state}

  def handle_call(:status, _from, %{fd: _} = state),
    do: {:reply, :open, state}

  def handle_call(:status, _from, state),
    do: {:reply, :closed, state}

  def handle_call(:stats, _from, state) do
    reply =
      %{queue_length: state.q_len,
        max_queue_length: state.max_q_len,
        serviced: state.serviced,
        dropped: state.dropped,
      }

    {:reply, reply, state}
  end

  def init(_args) do
    state =
      %{queue:     :queue.new,
        q_len:     0,
        serviced:  0,
        dropped:   0,
        max_q_len: 50,
      }

    {:ok, state}
  end

  def terminate(_, state) do
    if fd = state[:fd] do
      Port.close(state.port)
      :procket.close(fd)
    end
  end

  defp _find_match(state, _filter, count, acc)
      when length(acc) == count
  do
    next_state =
      %{state |
        serviced: state.serviced + length(acc),
      }

    {{:ok, Enum.reverse(acc)}, next_state}
  end

  defp _find_match(state, filter, count, acc)
      when length(acc) < count
  do
    case :queue.out(state.queue) do
      {{:value, data}, next_q} ->
        next_state =
          %{state |
            queue: next_q,
            q_len: state.q_len - 1,
          }

        parsed = Utility.parse_frame(data)

        if filter.(parsed) do
          next_acc = [parsed|acc]

          _find_match(next_state, filter, count, next_acc)
        else
          _find_match(next_state, filter, count, acc)
        end

      {:empty, _} ->
        next_state =
          %{state |
            serviced: state.serviced + length(acc),
          }

        if length(acc) > 0,
          do: {{:ok, Enum.reverse(acc)}, next_state},
        else: {{:error, :eagain}, state}
    end
  end

  ####################### Public API #######################

  @type opts :: keyword

  @doc """
  Start a GenRaw process, linking it to the current process.
  """
  @spec start_link(opts)
    :: {:ok, pid}
     | {:error, any}
  def start_link(opts \\ [])

  def start_link(opts)
      when is_list(opts),
    do: GenServer.start_link(__MODULE__, [], opts)

  @doc """
  Start a GenRaw process without linking it to the current
  process.
  """
  @spec start(opts)
    :: {:ok, pid}
     | {:error, any}
  def start(opts \\ [])

  def start(opts)
      when is_list(opts),
    do: GenServer.start(__MODULE__, [], opts)

  @type count  :: pos_integer
  @type data   :: binary

  @doc """
  Receive a PDU.

  If no PDU is in queue, then `{:error, :eagain}` is
  returned.

  Calling `receive/1` on a GenRaw process opened with
  `active: true` will return `{:error, :eopnotsupp}`.

  ## Example

      iex> GenRaw.receive(pid)
      {:error, :eagain}
      iex> GenRaw.receive(pid)
      { :ok,
        [ <<255, 255, 255, 255, 255, 255,
            192, 255, 51, 192, 255, 51,
            0, 4,
            116,101,115,116
          >>,
        ]
      }

  """
  @spec receive(pid, count)
      :: {:ok, [data]}
       | {:error, any}
  def receive(pid, count \\ 1)

  def receive(pid, count)
      when is_pid(pid)
       and is_integer(count) and count > 0,
    do: GenServer.call(pid, {:receive, count})

  @type filter :: (... -> boolean)

  @type pdu
    :: keyword(
         %{required(atom) => non_neg_integer|binary}
       )

  @doc """
  Receive a parsed PDU.

  When `filter` is provided, unmatched PDUs will be dropped
  until a matching PDU is found. When no PDU in the queue
  matches, `{:error, :eagain}` is returned.

  Calling this function on a GenRaw process opened with
  `active: true` will return `{:error, :eopnotsupp}`.

  ## Example

      iex> filter =
      ...>   &match?([dix: %{src: <<0xc0ff33c0ff33::48>>}, _], &1)
      iex>
      iex> GenRaw.receive(pid, 1, filter)
      { :ok, [[
          dix: %{
            dst: <<255, 255, 255, 255, 255, 255>>,
            src: <<192, 255, 51, 192, 255, 51>>,
            type: 4,
          },
          data: "test",
        ]]
      }

  """
  @spec receive_parsed(pid, count, filter)
      :: {:ok, [pdu]}
       | {:error, any}
  def receive_parsed(
    pid,
    count \\ 1,
    filter \\ fn _ -> true end
  )

  def receive_parsed(pid, count, filter)
      when is_pid(pid)
       and is_integer(count) and count > 0
       and is_function(filter)
  do
    GenServer.call(pid, {:receive_parsed, filter, count})
  end

  @doc """
  Retrieve a list of available interfaces.

  ## Example

      iex> GenRaw.interfaces
      {:ok, ["lo", "eth0"]}

  """
  @spec interfaces
    :: {:ok, [binary]}
     | {:error, any}
  def interfaces do
    with {:ok, erl_ifs} <- :inet.getiflist,

         ifs <-
           Enum.map(erl_ifs, &:binary.list_to_bin/1),

      do: {:ok, ifs}
  end

  @type if_name :: binary

  @doc """
  Send `data` from interface `if_name`.

  Sending a frame containing less than 14 bytes will return
  `{:error, :emsgsize}`.

  On my system, sending more than 4193920 bytes will return
  `{:error, :einval}`, but I don't guard for it. Of course,
  this doesn't mean you should actually send 4193920 bytes,
  and interfaces are not normally configured to accept more
  than 1532 bytes anyway (MTU + 802.3 + 802.1Q + etc.).

  ## Example

      iex> data  = "test"
      iex> frame =
      ...>   <<0xffffffffffff::48,
      ...>     0xc0ff33c0ff33::48,
      ...>     byte_size(data)::16,
      ...>     data,
      ...>   >>
      iex> GenRaw.send(pid, "eth0", frame)
      :ok

  """
  @spec send(pid, if_name, data)
    :: :ok
     | {:error, any}
  def send(pid, if_name, data)
      when is_pid(pid)
       and is_binary(if_name)
       and is_binary(data)
       and byte_size(data) >= 14
  do
    with {:ok, ifs} <- interfaces() do
      if if_name in ifs do
        GenServer.call(pid, {:send, if_name, data})
      else
        {:error, :enoent}
      end
    end
  end

  def send(_pid, _if_name, data)
      when byte_size(data) < 14,
    do: {:error, :emsgsize}

  @doc """
  Stop the GenRaw process at `pid`.
  """
  @spec stop(pid)
    :: :ok
  def stop(pid),
    do: GenServer.stop(pid)

  @doc """
  Open a raw socket with GenRaw process `pid`.

  This function is equivalent to
  `socket(AF_PACKET, SOCK_RAW, ETH_P_ALL)`.  See `man 2
  socket` for details.

  To observe the resulting socket in a shell, try
  `ss -elnp0`.

  ### Active mode

  Setting `active: true` in `opts` will send data directly
  to the owner process. In this case, `open/2` returns
  `{:ok, port}` on success. The data message format is

      {port, {:data, data}}

  where `port` is the port returned by `open/2` and `data`
  is a binary.
  """
  @spec open(pid, opts)
    :: :ok
     | {:ok, port}
     | {:error, any}
  def open(pid, opts \\ [])

  def open(pid, opts)
      when is_pid(pid)
       and is_list(opts)
  do
    active? = Keyword.get(opts, :active)
    target  =
      if is_boolean(active?) and active?,
        do: self()

    GenServer.call(pid, {:open, target})
  end

  @type status :: :open | :closed

  @doc """
  Get the status of GenRaw process `pid`.

  ## Example

      iex> GenRaw.status(pid)
      :closed
      iex> GenRaw.open(pid)
      :ok
      iex> GenRaw.status(pid)
      :open

  """
  @spec status(pid)
    :: status
  def status(pid)
      when is_pid(pid),
    do: GenServer.call(pid, :status)

  @type stats
    :: %{queue_length: non_neg_integer,
         max_queue_length: pos_integer,
         serviced: non_neg_integer,
         dropped: non_neg_integer,
       }

  @doc """
  Get queue statistics for GenRaw process `pid`.

  ## Example

      iex> GenRaw.stats(pid)
      %{queue_length: 31,
        max_queue_length: 50,
        serviced: 82384,
        dropped: 37,
      }

  """
  @spec stats(pid)
    :: stats
  def stats(pid)
      when is_pid(pid),
    do: GenServer.call(pid, :stats)

  @doc """
  Close a raw socket at GenRaw process `pid`.
  """
  @spec close(pid)
    :: :ok
     | {:error, any}
  def close(pid),
    do: GenServer.call(pid, :close)
end

defmodule GenRaw do
  use GenServer

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

    port  = Port.open({:fd, fd, fd}, [:binary])
    state =
      %{fd:      fd,
        port:    port,
        queue:   :queue.new,
        qlen:    0,
        qmax:    100,
        drops:   0,
        capture: nil,
      }

    {:ok, state}
  end

  @impl true
  def terminate(_, state) do
    Port.close state.port
    :procket.close state.fd
  end

  @impl true
  def handle_info({_port, {:data, data}}, state)
  do
    if cap_pid = state.capture do
      result = Utility.parse_frame data

      send(cap_pid, {:capture, self(), result})
    end

    if state.qlen < state.qmax do
      next_state =
        %{state |
          queue: :queue.in(data, state.queue),
          qlen:  state.qlen + 1,
        }

      {:noreply, next_state}
    else
      # Tail drop
      next_state =
        %{state|drops: state.drops + 1}

      {:noreply, next_state}
    end
  end

  @impl true
  def handle_call(:recv, _, state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        {:reply, {:error, :eagain}, state}

      {{:value, v}, next_queue} ->
        next_state =
          %{state |
            queue: next_queue,
            qlen:  state.qlen - 1,
          }

        {:reply, {:ok, v}, next_state}
    end
  end

  def handle_call({:snd, data}, _, state) do
      case :procket.sendto(state.fd, data) do
        :ok ->
          {:reply, :ok, state}

        {:error, _} = error ->
          {:reply, error, state}
      end
  end

  def handle_call(:capture, {pid, _}, state) do
    next_state = %{state|capture: pid}

    {:reply, :ok, next_state}
  end

  def recv(pid) when is_pid(pid),
    do: GenServer.call(pid, :recv)

  def snd(pid, data)
      when is_pid(pid)
       and is_binary(data),
    do: GenServer.call(pid, {:snd, data})

  defp _capture do
    receive do
      {:capture, _, result} ->
        captured =
          case result do
            {:ok, captured} ->
              captured

            {:error, {_, captured}} ->
              captured
          end

        {:erlang.system_time, captured}
        |> inspect
        |> Code.format_string!([line_length: 80])
        |> IO.puts

        _capture()
    end
  end

  def capture(pid) do
    :ok = GenServer.call(pid, :capture)

    _capture()
  end

  def start_link(interface),
    do: GenServer.start_link(__MODULE__, [interface])

  def stop(pid),
    do: GenServer.stop pid
end

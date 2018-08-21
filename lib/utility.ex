defmodule Utility do
  require Logger

  @doc """
  Parse an EthernetV2 (DIX) header. Please see
  `http://decnet.ipv7.net/docs/dundas/aa-k759b-tk.pdf` for
  details.

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                                      Destination Address     >|
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |<                              |                              >|
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |<        Source Address                                        |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |         EtherType/len         |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  """
  def parse_dix(
    <<dst::48,
      src::48,
      type::16,
      rest::bytes,
    >>
  ) do
    parsed =
      [ dst:  <<dst::48>>,
        src:  <<src::48>>,
        type: type,
      ]

    {parsed, type, rest}
  end

  @doc """
  Parse an IP header binary. Please see
  `https://en.wikipedia.org/wiki/IPv4#Header` for details.

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |Version|  IHL  |Type of Service|          Total Length         |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |         Identification        |Flags|      Fragment Offset    |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |  Time to Live |    Protocol   |         Header Checksum       |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                       Source Address                          |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                    Destination Address                        |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                    Options                    |    Padding    |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  """
  def parse_ip(
    <<ver::4,
      ihl::4,
      dscp::8,
      len::16,
      id::16,
      flags::3,
      offset::13,
      ttl::8,
      proto::8,
      cksum::16,
      src::32,
      dst::32,
      _::bytes,
    >> = data
  ) do
    opts_len = (ihl - 5) * 4
    parsed   =
      [ ver: ver,
        ihl: ihl,
        dscp: dscp,
        len: len,
        id: id,
        flags: flags,
        offset: offset,
        ttl: ttl,
        proto: proto,
        cksum: <<cksum::16>>,
        src: <<src::32>>,
        dst: <<dst::32>>,
        opts: :binary.part(data, 20, opts_len),
      ]

    rest_pos = 20 + opts_len

    <<_::binary-size(rest_pos),
      rest::bytes
    >> = data

    {parsed, proto, rest}
  end

  @doc """
  Parses a TCP header. Please see
  `https://en.wikipedia.org/wiki/Transmission_Control_Protocol#TCP_segment_structure`
  for details.

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |          Source Port          |       Destination Port        |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                        Sequence Number                        |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                    Acknowledgment Number                      |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |  Data |     |N|C|E|U|A|P|R|S|F|                               |
  | Offset| Rsvd| |W|C|R|C|S|S|Y|I|            Window             |
  |       |     |S|R|E|G|K|H|T|N|N|                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |           Checksum            |         Urgent Pointer        |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                    Options                    |    Padding    |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                             data                              |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  """
  def parse_tcp(
    <<spt::16,
      dpt::16,
      seq::32,
      ack::32,
      offset::4,
      rsvd::3,
      flags::9,
      win::16,
      cksum::16,
      ptr::16,
      _::bytes,
    >> = data
  ) do
    opts_len = (offset - 5) * 4
    parsed   =
      [ spt:    spt,
        dpt:    dpt,
        seq:    seq,
        ack:    ack,
        offset: offset,
        rsvd:   rsvd,
        flags:  flags,
        win:    win,
        cksum:  <<cksum::16>>,
        ptr:    ptr,
        opts:   :binary.part(data, 20, opts_len),
      ]

    rest_pos = 20 + opts_len

    <<_::binary-size(rest_pos),
      rest::bytes
    >> = data

    {parsed, nil, rest}
  end

  @doc """
  Parse a UDP header. Please see
  `https://en.wikipedia.org/wiki/User_Datagram_Protocol#Packet_structure`
  for details.

   0                   1                   2                   3
   0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |          Source Port          |       Destination Port        |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |            Length             |           Checksum            |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                             data                              |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  """
  def parse_udp(
    <<spt::16,
      dpt::16,
      len::16,
      cksum::16,
      rest::bytes,
    >>
  ) do
    parsed =
      [ spt: spt,
        dpt: dpt,
        len: len,
        cksum: <<cksum::16>>,
      ]

    {parsed, nil, rest}
  end

  defp get_parser(proto) do
    parser =
      %{dix: &parse_dix/1,
         ip: &parse_ip/1,
        tcp: &parse_tcp/1,
        udp: &parse_udp/1,
      }[proto]

    if parser do
      wrapped =
        fn pdu ->
          try do
            {:ok, parser.(pdu)}
          rescue
            exception ->
              Logger.debug "Parser raised #{inspect exception}\n#{inspect __STACKTRACE__}"

              {:error, :einval}
          end
        end

      {:ok, wrapped}
    else
      {:error, :eprotonosupport}
    end
  end

  defp get_next_proto(_, nil),
    do: nil

  defp get_next_proto(nil, proto_hint),
    do: {:ok, proto_hint}

  defp get_next_proto(proto, proto_hint) do
    next_proto =
      %{dix: %{
          0x0800 => :ip,
        },
        ip: %{
          6   => :tcp,
          17  => :udp,
        },
      }[proto][proto_hint]

    if next_proto do
      {:ok, next_proto}
    else
      {:error, :eprotonosupport}
    end
  end

  defp parse_pdu(pdu, last_proto, proto_hint, acc)
  do
    with {:ok, proto} <-
           get_next_proto(last_proto, proto_hint),

         {:ok, parser} <- get_parser(proto),

         {:ok, {parsed, next_proto_hint, rest}} <-
           parser.(pdu)
    do
      next_acc = [{proto, parsed}|acc]

      parse_pdu(rest, proto, next_proto_hint, next_acc)
    else
      result ->
        return = Enum.reverse [{:data, pdu}|acc]

        case result do
          nil ->
            {:ok, return}

          {:error, reason} ->
            {:error, {reason, return}}
        end
    end
  end

  @doc """
  Parse a full frame, detecting EtherType and IP protocol.
  """
  def parse_frame(frame),
    do: parse_pdu(frame, nil, :dix, [])
end

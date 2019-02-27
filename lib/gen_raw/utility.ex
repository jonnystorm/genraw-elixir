# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule GenRaw.Utility do
  @moduledoc false

  require Logger

  def parse_headers(<<data::bytes>>, nil, acc),
    do: Enum.reverse([{:data, data}|acc])

  # Parse an EthernetV2 (DIX) header. Please see
  # `http://decnet.ipv7.net/docs/dundas/aa-k759b-tk.pdf` for
  # details.
  #
  #  0                   1                   2                   3
  #  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                                      Destination Address     >|
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |<                              |                              >|
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |<        Source Address                                        |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |         EtherType/len         |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  #
  def parse_headers(
    <<dst::48,
      src::48,
      type::16,
      rest::bits
    >>,
    :dix,
    acc
  ) do
    header =
      %{dst:  <<dst::48>>,
        src:  <<src::48>>,
        type: type,
      }

    next_proto = get_next_proto(:dix, type)

    parse_headers(rest, next_proto, [{:dix, header}|acc])
  end

  # Parse an IP header binary. Please see
  # `https://en.wikipedia.org/wiki/IPv4#Header` for details.
  #
  #  0                   1                   2                   3
  #  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |Version|  IHL  |Type of Service|          Total Length         |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |         Identification        |Flags|      Fragment Offset    |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |  Time to Live |    Protocol   |         Header Checksum       |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                       Source Address                          |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                    Destination Address                        |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                    Options                    |    Padding    |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  #
  def parse_headers(
    <<ver::4,
      ihl::4,
      dscp::8,
      len::16,
      id::16,
      flags::3,
      offset::13,
      ttl::8,
      proto::8,
      cksum::bytes-size(2),
      src::bytes-size(4),
      dst::bytes-size(4),
      rest0::bits,
    >>,
    :ip,
    acc
  ) do
    data_pos = 4 * ihl
    opts_len = data_pos - 20

    <<opts::bytes-size(opts_len),
      rest::bits,
    >> = rest0

    header =
      %{ver: ver,
        ihl: ihl,
        dscp: dscp,
        len: len,
        id: id,
        flags: flags,
        offset: offset,
        ttl: ttl,
        proto: proto,
        cksum: cksum,
        src: src,
        dst: dst,
        opts: opts,
      }

    next_proto = get_next_proto(:ip, proto)

    parse_headers(rest, next_proto, [{:ip, header}|acc])
  end

  def parse_headers(
    <<type::8,
      code::8,
      cksum::bytes-size(2),
      rest::bits,
    >>,
    :icmp,
    acc
  ) do
    header =
      %{type: type,
        code: code,
        cksum: cksum,
      }

    parse_headers(rest, nil, [{:icmp, header}|acc])
  end

  # Parses a TCP header. Please see
  # `https://en.wikipedia.org/wiki/Transmission_Control_Protocol#TCP_segment_structure`
  # for details.
  #
  #  0                   1                   2                   3
  #  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |          Source Port          |       Destination Port        |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                        Sequence Number                        |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                    Acknowledgment Number                      |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |  Data |     |N|C|E|U|A|P|R|S|F|                               |
  # | Offset| Rsvd| |W|C|R|C|S|S|Y|I|            Window             |
  # |       |     |S|R|E|G|K|H|T|N|N|                               |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |           Checksum            |         Urgent Pointer        |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                    Options                    |    Padding    |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                             data                              |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  #
  def parse_headers(
    <<spt::16,
      dpt::16,
      seq::32,
      ack::32,
      offset::4,
      rsvd::3,
      flags::9,
      win::16,
      cksum::bytes-size(2),
      ptr::16,
      rest0::bits,
    >>,
    :tcp,
    acc
  ) do
    data_pos = 4 * offset
    opts_len = data_pos - 20

    <<opts::bytes-size(opts_len),
      rest::bits
    >> = rest0

    header   =
      %{spt:    spt,
        dpt:    dpt,
        seq:    seq,
        ack:    ack,
        offset: offset,
        rsvd:   rsvd,
        flags:  flags,
        win:    win,
        cksum:  cksum,
        ptr:    ptr,
        opts:   opts,
      }

    parse_headers(rest, nil, [{:tcp, header}|acc])
  end

  # Parse a UDP header. Please see
  # `https://en.wikipedia.org/wiki/User_Datagram_Protocol#Packet_structure`
  # for details.
  #
  #  0                   1                   2                   3
  #  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |          Source Port          |       Destination Port        |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |            Length             |           Checksum            |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  # |                             data                              |
  # +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  #
  def parse_headers(
    <<spt::16,
      dpt::16,
      len::16,
      cksum::bytes-size(2),
      rest::bits,
    >>,
    :udp,
    acc
  ) do
    header =
      %{spt: spt,
        dpt: dpt,
        len: len,
        cksum: cksum,
      }

    parse_headers(rest, nil, [{:udp, header}|acc])
  end

  defp get_next_proto(proto, proto_hint) do
    %{dix: %{
        0x0800 => :ip,
      },
      ip: %{
        1   => :icmp,
        6   => :tcp,
        17  => :udp,
      },
    }[proto][proto_hint]
  end

  def parse_frame(frame)
      when is_binary(frame),
    do: parse_headers(frame, :dix, [])
end

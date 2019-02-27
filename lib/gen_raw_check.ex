# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

defmodule GenRawCheck do
  @moduledoc false

  def test do
    pid = :erlang.list_to_pid('<0.123.0>')

    {:ok, _} = GenRaw.receive(pid)
    {:ok, _}  = GenRaw.receive_parsed(pid)
    {:ok, _}  = GenRaw.receive_parsed(pid, &match?([_], &1))

    :ok   = GenRaw.send(pid, "test", "test")
    :ok   = GenRaw.open(pid)
    :open = GenRaw.status(pid)
  end
end

defmodule ExGitd.UploadPack do
  use GenServer.Behaviour
  alias :geef_repo, as: Repo
  alias :geef_ref, as: Ref
  alias :geef_oid, as: Oid

  # Public API
  def advertisement(pid) do
    :gen_server.call(pid, :advertisement)
  end

  def start_link(path) do
    :gen_server.start_link(__MODULE__, path, [])
  end

  def terminate(pid) do
    :gen_server.call(pid, :terminate)
  end

  # Callbacks for gen_server
  def init(path) do
    Repo.open(path)
  end

  def handle_call(:advertisement, _from, repo) do
    {:reply, advertise_refs(repo), repo}
  end

  def handle_call(:terminate, _from, repo) do
    {:stop, :normal, :ok, repo}
  end

  def handle_info(msg, state) do
    IO.puts "Unknown message #{inspect msg}"
    { :noreply, state }
  end

  defp reflist(_, [], acc) do
    Enum.sort acc, fn({_, a}, {_, b}) -> a > b end
  end

  defp reflist(repo, [h|rest], acc) do
    {:ok, ref} = Ref.lookup(repo, h)
    {:ok, ref} = Ref.resolve(ref)
    line = {Oid.fmt(Ref.target(ref)), h}
    reflist(repo, rest, [line|acc])
  end

  def reflist(repo) do
    refs = Repo.references(repo)
    reflist(repo, ["HEAD" | refs], [])
  end

  defp pkt_line([{sha, name}|rest], acc) do
    len = size(sha) + size(name) + 4 + 1 + 1
    line = :io_lib.format("~4.16.0b#{sha} #{name}\n", [len])
    pkt_line(rest, [line|acc])
  end

  defp pkt_line([], acc), do: [acc, "0000"]
  defp pkt_line(list) do
    # sort reverse-alpha so pkt_line gets it right
    sorted = Enum.sort list, fn({_, a}, {_, b}) -> a > b end
    pkt_line(sorted, [])
  end

  @spec advertise_refs(String.t) :: iolist
  def advertise_refs(repo) do
    refs = reflist(repo)
    pkt_line(refs)
  end
end

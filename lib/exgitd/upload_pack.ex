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

  defp peel_tag(repo, ref, name) do
    { :ok, obj } = :geef_object.lookup(repo, ref.target)
    case obj.type do
      :tag ->
        { :ok, peeled } = :geef_tag.peel(obj)
        [peeled.id.hex, " ", name, "^{}"]
      _ ->
        []
    end
  end

  defp pkt_tag(base, []) do
    :geef_pkt.line(base)
  end
  defp pkt_tag(base, peeled) do
    [:geef_pkt.line(base), :geef_pkt.line(peeled)]
  end

  defp pkt_ref(repo, name) do
    {:ok, ref} = Ref.lookup(repo, name)
    {:ok, ref} = ref.resolve
    base = [ref.target.hex, " ", name]
    case name do
      <<"refs/tags/", _ :: binary>> ->
        pkt_tag(base, peel_tag(repo, ref, name))
      _ ->
        :geef_pkt.line(base)
    end
  end

  @spec advertise_refs(pid()) :: iolist
  defp advertise_refs(repo) do
    refnames = Repo.references(repo)
    refnames = Enum.sort refnames, &1 < &2
    refs = Enum.map ["HEAD" | refnames], pkt_ref repo, &1
    [refs, "0000"]
  end
end

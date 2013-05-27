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

  defp resolve_ref(repo, name) do
    {:ok, ref} = Ref.lookup(repo, name)
    {:ok, ref} = ref.resolve
    [ref.target.hex, " ", name]
  end

  @spec advertise_refs(pid()) :: iolist
  defp advertise_refs(repo) do
    refnames = Repo.references(repo)
    refnames = Enum.sort refnames, &1 < &2
    refs = Enum.map ["HEAD" | refnames], resolve_ref repo, &1
    refs = Enum.map refs, :geef_pkt.line &1
    [refs, "0000"]
  end
end

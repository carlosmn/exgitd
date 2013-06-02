defmodule ExGitd.UploadPack do
  alias :geef_repo, as: Repo
  alias :geef_ref, as: Ref
  alias :geef_oid, as: Oid
  alias :geef_odb, as: Odb

  @behaviour :gen_fsm

  defrecordp :state, repo: nil, odb: nil, advertised: [], common: [], want: [], done: false

  # Public API
  def response(pid) do
    :gen_fsm.sync_send_event(pid, :response)
  end

  def start_link(path) do
    :gen_fsm.start_link(__MODULE__, path, [])
  end

  @doc """
  Pass in more data. As much of the input will be consumed as possible
  and the internal state will be updated. `:more` is returned until
  the process is ready to send data to the client, at which point it
  returns `:response` or `:pack`. `:pack` means that the negotiation is done.

  The unconsumed input is always returned as the second field.
  """
  @spec continue(pid(), iolist()) :: {:more | :response, binary()}
  def continue(_pid, <<>>), do: {:more, <<>>}
  def continue(pid, data) do
    case :geef_pkt.parse(data) do
      {:error, :ebufs} ->
        {:more, data}
      other ->
        do_continue(pid, other)
    end
  end

  defp do_continue(_pid, {:error, :ebufs} = err), do: err
  defp do_continue(pid, {pkt, rest}) do
    case :gen_fsm.sync_send_event(pid, pkt) do
      :more ->
        continue(pid, rest)
      other ->
        other
    end
  end

  def stop(pid) do
    :gen_fsm.send_all_state_event(pid, :stop)
  end

  # Callbacks
  @doc false
  def init(path) do
    {:ok, repo} = Repo.open(path)
    {:ok, :advertisement, state(repo: repo)}
  end

  @doc false
  def terminate(:normal, _, _state) do
    :ok
  end

  @doc false
  def handle_event(:stop, _state_name, state) do
    {:stop, :normal, state}
  end

  @doc false
  def advertisement(:response, _from, state(repo: repo) = state) do
    {data, advertised} = advertise_refs(repo)
    {:reply, data, :want, state(state, advertised: advertised)}
  end

  @doc false
  def want({:want, id}, _from, state(want: want) = state) do
    {:reply, :more, :want, state(state, want: [id | want])}
  end

  @doc false
  def want(:flush, _from, state) do
    {:reply, :more, :have, state}
  end

  @doc false
  def have({:have, id}, _from, state) do
    {:reply, :more, :have, check_common(state, id)}
  end

  @doc false
  def have(:flush, _from, state) do
    {:reply, :response, :have, state}
  end

  @doc false
  def have(:done, _from, state) do
    {:reply, :pack, :pack, state}
  end

  @doc false
  def have(:response, _from, state(common: []) = state) do
    {:reply, "NACK", :have, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @doc false
  def code_change(_old_vsn, state_name, state, _extra) do
    {:ok, state_name, state}
  end

  @doc false
  def handle_info(_message, state_name, state) do
    {:next_state, state_name, state}
  end

  @doc false
  def handle_sync_event(_event, _from, state_name, state) do
    {:next_state, state_name, state}
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

  defp pkt_ref(repo, name, {data, tips}) do
    {:ok, ref} = Ref.lookup(repo, name)
    {:ok, ref} = ref.resolve
    target = ref.target
    unpeeled = :geef_pkt.line([target.hex, " ", name])
    case name do
      <<"refs/tags/", _ :: binary>> ->
        peeled = peel_tag(repo, ref, name) |> :geef_pkt.line
        data = [data, unpeeled, peeled]
        {data, [target | tips]}
      _ ->
        {[data, unpeeled], [target | tips]}
    end
  end

  @spec advertise_refs(pid()) :: iolist
  defp advertise_refs(repo) do
    refnames = Repo.references(repo) |> Enum.sort &1 < &2
    {refs, advertised} = Enum.reduce ["HEAD" | refnames], {[], []}, pkt_ref repo, &1, &2
    {[refs, "0000"], advertised}
  end

  defp check_common(state(repo: repo, common: common, odb: odb) = state, id) do
    if odb == nil do
      {:ok, odb} = Repo.odb(repo)
      state = state(state, odb: odb)
    end
    case Odb.exists(odb, id) do
      true ->
        state(state, common: [id | common])
      _ ->
        state
    end
  end

end

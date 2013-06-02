defmodule ExGitd do
  use Application.Behaviour
  alias :ranch, as: Ranch

  defp start_ranch do
    Application.Behaviour.start(Ranch)
    case Ranch.start_listener(:exgitd, 1, :ranch_tcp, [ {:port, 9418} ], ExGitd.Protocol, []) do
      {:ok, pid} ->
	{:ok, pid}
      {:error, {:already_started, pid}} ->
	{:ok, pid}
    end
  end

  def start(), do: start(nil, [])

  def start(_type, args) do
    start_ranch()
    __MODULE__.Sup.start_link(args)
  end

  def stop(_state) do
    Ranch.stop_listener(:exgitd)
  end
end

defmodule ExGitd.Sup do
  use Supervisor.Behaviour

  def start_link(opts // []) do
    :supervisor.start_link({ :local, __MODULE__}, __MODULE__, opts)
  end

  def init(_opts) do
    supervise([], strategy: :one_for_one)
  end
end

# For use with ranch
defmodule ExGitd.Protocol do
  alias :ranch, as: Ranch
  alias ExGitd.UploadPack, as: UP
  alias :geef_pkt, as: Pkt

  defrecord :geef_request, Record.extract(:geef_request,
                                          from: "deps/geef/src/geef_records.hrl")

  @behaviour :ranch_protocol

  @base System.get_env("HOME") <> "/git"


  def start_link(pid, sock, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [pid, sock, transport, opts])
    { :ok, pid }
  end

  def init(pid, sock, transport, _opts // []) do
    :ok = Ranch.accept_ack(pid)
    loop(sock, transport, nil, <<>>)
  end

  # Call this while we haven't parsed the request
  def loop(sock, transport, nil, data_in) do
    case transport.recv(sock, 0, 50000) do
      { :ok, new_data } ->
        data = [data_in, new_data]
        case Pkt.parse_request(data) do
          { :error, :ebufs } ->
            loop(sock, transport, nil, data)
          { :ok, :geef_request[path: path]} ->
            path = @base <> path
            { :ok, pid } = UP.start_link(path)
	          transport.send(sock, UP.response(pid))
            loop(sock, transport, pid, [])
        end
      _ ->
        { :error, :recv }
    end
  end

  def loop(sock, transport, pid, data_in) do
    case transport.recv(sock, 0, 50000) do
      { :ok, new_data } ->
        data = [data_in, new_data]
        case UP.continue(pid, data) do
          {:more, data} ->
	          loop(sock, transport, pid, data)
          {:response, data} ->
            transport.send(sock, UP.response(pid))
            loop(sock, transport, pid, data)
        end
      _ ->
	      UP.stop(pid)
	      :ok = transport.close(sock)
    end
  end
end

defmodule ExGitd do
  use Application.Behaviour
  alias :ranch, as: Ranch

  defp start_ranch do
    Application.Behaviour.start(Ranch)
    case Ranch.start_listener(:tcp_greeter, 1, :ranch_tcp, [ {:port, 5555} ], ExGitd.Protocol, []) do
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

  @behaviour :ranch_protocol

  def start_link(pid, sock, transport, opts) do
    pid = spawn_link(__MODULE__, :init, [pid, sock, transport, opts])
    { :ok, pid }
  end

  def init(pid, sock, transport, _opts // []) do
    :ok = Ranch.accept_ack(pid)
    {:ok, pid} = UP.start_link(".")
    loop(sock, transport, pid)
  end

  def loop(sock, transport, pid) do
    case transport.recv(sock, 0, 50000) do
      { :ok, data } ->
	transport.send(sock, UP.advertisement(pid))
	loop(sock, transport, pid)
      _ ->
	UP.terminate(pid)
	:ok = transport.close(sock)
    end
  end
end

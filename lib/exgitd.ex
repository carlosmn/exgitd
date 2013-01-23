defmodule ExGitd do
  use Application.Behaviour
  alias :ranch, as: Ranch

  def start(_type, args) do
    Application.Behaviour.start(Ranch)
    { :ok, _ } = Ranch.start_listener(:tcp_greeter, 1, :ranch_tcp,
    [ { :port, 5555} ], ExGitd.Protocol, [])
    __MODULE__.Sup.start_link(args)
  end
end

defmodule ExGitd.Sup do
  use Supervisor.Behaviour

  def start_link(opts // []) do
    { :ok, pid } = :supervisor.start_link({ :local, __MODULE__}, __MODULE__, opts)
  end

  def init(_opts) do
    tree = [ worker(ExGitd.UploadPack, []) ]
    supervise(tree, strategy: :one_for_one)
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
    loop(sock, transport)
  end

  def loop(sock, transport) do
    case transport.recv(sock, 0, 50000) do
      { :ok, data } ->
	transport.send(sock, UP.advertise_refs("."))
	loop(sock, transport)
      _ ->
	:ok = transport.close(sock)
    end
  end
end

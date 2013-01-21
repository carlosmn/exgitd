defmodule Exgitd do
  alias :geef, as: Git

  def reflist(_, [], acc) do
    Enum.sort acc, fn({_, a}, {_, b}) -> a < b end
  end

  def reflist(repo, [h|rest], acc) do
    ref = repo.lookup(h)
    p = {Git.oid_fmt(ref.id), h}
    reflist(repo, rest, [p|acc])
  end

  def reflist(path) do
    repo = Git.repository(path)
    refs = repo.references
    reflist(repo, refs, [])
  end
end

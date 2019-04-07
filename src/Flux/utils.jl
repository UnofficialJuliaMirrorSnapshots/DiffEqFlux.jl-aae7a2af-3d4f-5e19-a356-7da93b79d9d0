function destructure(m)
  xs = []
  mapleaves(m) do x
    x isa TrackedArray && push!(xs, x)
    return x
  end
  return vcat(vec.(xs)...)
end

function restructure(m, xs)
  i = 0
  mapleaves(m) do x
    x isa TrackedArray || return x
    x = reshape(xs[i.+(1:length(x))], size(x))
    i += length(x)
    return x
  end
end

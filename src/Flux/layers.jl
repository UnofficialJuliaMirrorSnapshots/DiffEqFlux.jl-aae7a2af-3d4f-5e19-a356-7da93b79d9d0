using Flux.Tracker: @grad
using DiffEqSensitivity: adjoint_sensitivities_u0

## Reverse-Mode via Flux.jl

function diffeq_rd(p,prob,args...;u0=prob.u0,kwargs...)
  if DiffEqBase.isinplace(prob)
    # use Array{TrackedReal} for mutation to work
    _prob = remake(prob,u0=convert.(eltype(p),u0),p=p)
  else
    # use TrackedArray for efficiency of the tape
    _prob = remake(prob,u0=convert(typeof(p),u0),p=p)
  end
  solve(_prob,args...;kwargs...)
end

## Forward-Mode via ForwardDiff.jl

function diffeq_fd(p,f,n,prob,args...;u0=prob.u0,kwargs...)
  _prob = remake(prob,u0=convert.(eltype(p),u0),p=p)
  f(solve(_prob,args...;kwargs...))
end

diffeq_fd(p::TrackedVector,args...;kwargs...) = Flux.Tracker.track(diffeq_fd, p, args...; kwargs...)
Flux.Tracker.@grad function diffeq_fd(p::TrackedVector,f,n,prob,args...;u0=prob.u0,kwargs...)
  _f = function (p)
    _prob = remake(prob,u0=convert.(eltype(p),u0),p=p)
    f(solve(_prob,args...;kwargs...))
  end
  _p = Flux.data(p)
  if n === nothing
    result = DiffResults.GradientResult(_p)
    ForwardDiff.gradient!(result, _f, _p)
    DiffResults.value(result),Δ -> (Δ .* DiffResults.gradient(result), ntuple(_->nothing, 3+length(args))...)
  else
    y = zeros(n)
    result = DiffResults.JacobianResult(y,_p)
    ForwardDiff.jacobian!(result, _f, _p)
    DiffResults.value(result),Δ -> (DiffResults.jacobian(result)' * Δ, ntuple(_->nothing, 3+length(args))...)
  end
end

## Reverse-Mode using Adjoint Sensitivity Analysis
# Always reduces to Array

function diffeq_adjoint(p,prob,args...;u0=prob.u0,kwargs...)
  _prob = remake(prob,u0=u0,p=p)
  Array(solve(_prob,args...;kwargs...))
end

diffeq_adjoint(p::TrackedVector,prob,args...;u0=prob.u0,kwargs...) =
  Flux.Tracker.track(diffeq_adjoint, p, u0, prob, args...; kwargs...)

@grad function diffeq_adjoint(p,u0,prob,args...;backsolve=true,kwargs...)
  _prob = remake(prob,u0=Flux.data(u0),p=Flux.data(p))
  sol = solve(_prob,args...;kwargs...)
  Array(sol), Δ -> begin
    Δ = Flux.data(Δ)
    ts = sol.t
    df(out, u, p, t, i) = @. out = - @view Δ[:, i]
    du0, dp = adjoint_sensitivities_u0(sol,args...,df,ts;sensealg=SensitivityAlg(quad=false,backsolve=backsolve),kwargs...)
    (dp', du0, ntuple(_->nothing, 1+length(args))...)
  end
end

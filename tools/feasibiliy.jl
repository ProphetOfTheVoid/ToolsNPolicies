using JuMP
using Gurobi
using JSON, JSON3
using LinearAlgebra
using Printf
using JuMP.Containers

include("build_model.jl")
include("load_instance_lotsizing_backlog.jl")

model = build_model("material/small_instance.json")
vals = JSON.parsefile("metrics/solution.json")

point = Dict{VariableRef,Float64}()
for v in all_variables(model)
    point[v] = Float64(vals[name(v)])   # fails with KeyError if a name does not match
end

violations = primal_feasibility_report(model, point; atol=1e-6)
println("Violated constraints: ", length(violations))
println("Recomputed objective: ", value(v -> point[v], objective_function(model)))
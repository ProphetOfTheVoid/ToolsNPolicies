using JuMP
using Gurobi
using JSON, JSON3
using LinearAlgebra
using Printf
using JuMP.Containers

include(joinpath(@__DIR__, "build_model.jl"))
include(joinpath(@__DIR__, "load_instance_lotsizing_backlog.jl"))

# --- Configuration (edit before every run) ---
const INSTANCE_FILE = "material/140_instance.json"
const METRICS_FILE = "metrics/metrics.jsonl"
const TIME_LIMIT = 350.0   # seconds, whole model
const MIP_GAP = 1e-4      # Gurobi default: the baseline should be as tight as possible
const SEED = 2

_instance_name(path) = "ins" * uppercasefirst(replace(splitext(basename(path))[1], "_instance" => ""))
_fmt(x) = (x isa AbstractFloat && isinteger(x)) ? string(Int(x)) : string(x)

const RUN_LABEL = join([
    "baseline",
    _instance_name(INSTANCE_FILE),
    "tl" * _fmt(TIME_LIMIT),
    "gap" * _fmt(MIP_GAP),
    "s" * _fmt(SEED),
], "|")


# Returns f(), or nothing if it throws or yields a non-finite number
function try_metric(f)
    try
        val = f()
        return (val isa Real && !isfinite(val)) ? nothing : val
    catch
        return nothing
    end
end

function run_baseline()
    println("Building the full model...")
    t_start = time_ns()
    model = build_model(INSTANCE_FILE)

    set_optimizer(model, Gurobi.Optimizer)
    set_attribute(model, "OutputFlag", 1)
    set_attribute(model, "Threads", 1)
    set_attribute(model, "Seed", SEED)
    set_attribute(model, "TimeLimit", TIME_LIMIT)
    set_attribute(model, "MIPGap", MIP_GAP)

    optimize!(model)
    wall_time = (time_ns() - t_start) / 1e9

    status = termination_status(model)
    has_vals = has_values(model)

    record = (
        run_label=RUN_LABEL,
        call=1,
        termination_status=string(status),
        primal_status=try_metric(() -> string(primal_status(model))),
        has_values=has_vals,
        objective=has_vals ? try_metric(() -> objective_value(model)) : nothing,
        objective_bound=try_metric(() -> objective_bound(model)),
        relative_gap=try_metric(() -> relative_gap(model)),
        solver_time=try_metric(() -> solve_time(model)),
        wall_time=wall_time,
        node_count=try_metric(() -> node_count(model)),
        n_fixed=0,
        n_core=nothing,
        n_relaxed=nothing,
        time_limit=TIME_LIMIT,
        mip_gap=MIP_GAP,
        seed=SEED,
    )

    mkpath(dirname(METRICS_FILE))
    open(METRICS_FILE, "a") do io
        println(io, JSON3.write(record))
    end

    println("\nBaseline finished: status = $status, objective = $(record.objective), ",
        "bound = $(record.objective_bound), gap = $(record.relative_gap)")
    return record
end

run_baseline()
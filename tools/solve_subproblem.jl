# ATOMIC BOX

using JuMP, Gurobi, JSON3

const METRICS_FILE = "metrics/metrics.jsonl"
const SEED = 0
const POLICY_NAME = ""   # optional: if empty, the name of the running script is used
const _SUBPROBLEM_CALL_COUNT = Ref(0)

# --- Automatic run label ---
function _main_value(names::Symbol...)
    for n in names
        isdefined(Main, n) && return getfield(Main, n)
    end
    return nothing
end

_fmt(x) = (x isa AbstractFloat && isinteger(x)) ? string(Int(x)) : string(x)

function _instance_label(path)
    path === nothing && return "insUnknown"
    name = replace(splitext(basename(string(path)))[1], "_instance" => "")
    return "ins" * uppercasefirst(name)
end

function _policy_label()
    !isempty(POLICY_NAME) && return POLICY_NAME
    return isempty(PROGRAM_FILE) ? "policyUnknown" : splitext(basename(PROGRAM_FILE))[1]
end

function _build_run_label(sub_time_limit, sub_mip_gap)
    parts = String[_policy_label(), _instance_label(_main_value(:BACKLOG_FILE, :INSTANCE_FILE))]
    bs = _main_value(:BLOCK_SIZE)
    bs !== nothing && push!(parts, "bs" * _fmt(bs))
    ov = _main_value(:OVERLAP, :OVERLAP_SIZE, :BLOCK_OVERLAP)
    ov !== nothing && push!(parts, "ov" * _fmt(ov))
    push!(parts, "tl" * _fmt(sub_time_limit), "gap" * _fmt(sub_mip_gap), "s" * _fmt(SEED))
    return join(parts, "|")
end


function _try_metric(f)
    try
        val = f()
        return (val isa Real && !isfinite(val)) ? nothing : val
    catch
        return nothing
    end
end

function _log_subproblem_metrics(run_label, m, status, has_vals, obj_val, wall_time,
    n_fixed, n_core, n_relaxed)
    try
        mkpath(dirname(METRICS_FILE))
        _SUBPROBLEM_CALL_COUNT[] += 1
        record = (
            run_label=run_label,
            call=_SUBPROBLEM_CALL_COUNT[],
            termination_status=string(status),
            primal_status=_try_metric(() -> string(primal_status(m))),
            has_values=has_vals,
            objective=isnan(obj_val) ? nothing : obj_val,
            objective_bound=_try_metric(() -> objective_bound(m)),
            relative_gap=_try_metric(() -> relative_gap(m)),
            solver_time=_try_metric(() -> solve_time(m)),
            wall_time=wall_time,
            node_count=_try_metric(() -> node_count(m)),
            n_fixed=n_fixed,
            n_core=n_core,
            n_relaxed=n_relaxed,
        )
        open(METRICS_FILE, "a") do io
            println(io, JSON3.write(record))
        end
    catch err
        # Logging must never break the solve
        @warn "Could not write subproblem metrics" exception = err
    end
end


function solve_subproblem(
    base_model::Model,
    fixed_vars::Dict{VariableRef,Float64},
    core_vars::Set{VariableRef},
    relaxed_vars::Set{VariableRef};
    sub_time_limit,
    sub_mip_gap,
    sub_work_limit
)
    t_start = time_ns()

    m, ref_map = copy_model(base_model)
    set_optimizer(m, Gurobi.Optimizer)
    set_attribute(m, "OutputFlag", 1)
    set_attribute(m, "Threads", 1)
    set_attribute(m, "Seed", SEED)

    # Fix variables in fixed_vars to their specified values
    for (v, val) in fixed_vars
        v_cloned = ref_map[v]
        fix(v_cloned, val; force=true)
    end

    # Core variables are set to binary
    for v in core_vars
        v_cloned = ref_map[v]
        if !is_binary(v_cloned)
            set_binary(v_cloned)
        end
    end

    # Future variables are relaxed to continuous
    for v in relaxed_vars
        v_cloned = ref_map[v]
        if is_binary(v_cloned)
            unset_binary(v_cloned)
            set_lower_bound(v_cloned, 0.0)
            set_upper_bound(v_cloned, 1.0)
        end
    end

    # Optimization settings
    set_attribute(m, "TimeLimit", sub_time_limit)
    set_attribute(m, "MIPGap", sub_mip_gap)
    set_attribute(m, "WorkLimit", sub_work_limit)
    optimize!(m)

    status = termination_status(m)
    has_vals = has_values(m)

    sol_dict = Dict{VariableRef,Float64}()
    obj_val = NaN

    if has_vals
        obj_val = objective_value(m)
        for v in all_variables(base_model)
            sol_dict[v] = value(ref_map[v])
        end
    end

    wall_time = (time_ns() - t_start) / 1e9
    _log_subproblem_metrics(_build_run_label(sub_time_limit, sub_mip_gap),
        m, status, has_vals, obj_val, wall_time,
        length(fixed_vars), length(core_vars), length(relaxed_vars))

    return status, has_vals, sol_dict, obj_val
end
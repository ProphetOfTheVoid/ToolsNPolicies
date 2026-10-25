using JuMP
using Gurobi
using JSON, JSON3
using LinearAlgebra
using Printf
using JuMP.Containers

include(joinpath(@__DIR__, "build_model.jl"))
include(joinpath(@__DIR__, "get_block_variables.jl"))
include(joinpath(@__DIR__, "plan_blocks.jl"))
include(joinpath(@__DIR__, "solve_subproblem.jl"))
include(joinpath(@__DIR__, "write_solution.jl"))
include(joinpath(@__DIR__, "check_subproblem_result.jl"))
include(joinpath(@__DIR__, "apply_fixing_policy.jl"))
include(joinpath(@__DIR__, "load_instance_lotsizing_backlog.jl"))

BLOCK_SIZE = 20
OVERLAP = 8
STEP_SIZE = BLOCK_SIZE - OVERLAP

function solve_lsp(
    instance_path::String="material/140_instance.json";
    output_path::String="material/solution.json",
    sub_time_limit::Real=60.0,
    sub_mip_gap::Real=0.001,
    sub_work_limit::Real=Inf,
)
    model = build_model(instance_path)

    periods = get_periods(model, :y)
    num_periods = length(periods)

    if BLOCK_SIZE <= 0 || STEP_SIZE <= 0
        throw(ArgumentError("block_size and step_size must be positive."))
    end

    vars_by_period = variables_by_period(model, :y)
    fixed_vars = Dict{VariableRef,Float64}()

    last_sol_dict = Dict{VariableRef,Float64}()

    # Generate overlapping windows in chronological order.
    window_starts = collect(1:STEP_SIZE:num_periods)

    for (window_index, start_index) in enumerate(window_starts)
        end_index = min(start_index + BLOCK_SIZE - 1, num_periods)
        current_periods = periods[start_index:end_index]
        future_periods = periods[(end_index+1):end]

        # Only binary variables in the current window remain binary.
        # Binary variables in future periods are relaxed to continuous.
        core_vars, relaxed_vars = partition_by_block(
            vars_by_period,
            current_periods,
            future_periods,
        )

        status, has_vals, sol_dict, obj_val = solve_subproblem(
            model,
            fixed_vars,
            core_vars,
            relaxed_vars;
            sub_time_limit=sub_time_limit,
            sub_mip_gap=sub_mip_gap,
            sub_work_limit=sub_work_limit,
        )

        if !subproblem_succeeded(status, has_vals)
            println(
                "Rolling-horizon procedure stopped: subproblem ",
                window_index,
                " has no usable solution. Previous fixing decisions ",
                "may have made this portion of the problem infeasible; ",
                "this does not necessarily imply that the original ",
                "instance is infeasible.",
            )
            return nothing
        end

        last_sol_dict = sol_dict

        # Permanently fix the first step_size periods of this window,
        # or all remaining periods if the window is shorter.
        periods_to_fix = current_periods[1:min(STEP_SIZE, length(current_periods))]

        fix_vars = Set{VariableRef}()
        for period in periods_to_fix
            union!(fix_vars, vars_by_period[period])
        end

        fixed_vars = apply_fixing_policy!(
            fixed_vars,
            sol_dict,
            fix_vars,
        )
    end

    # All binary variables should now be fixed. Preserve all other
    # variables as continuous variables using the last subproblem solution.
    continuous_vars = Dict{VariableRef,Float64}(
        var => value for (var, value) in last_sol_dict
                         if !haskey(fixed_vars, var)
    )

    return write_solution(fixed_vars, continuous_vars, output_path)
end

solution_path = solve_lsp()
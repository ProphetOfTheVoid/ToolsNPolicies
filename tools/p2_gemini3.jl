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

using JuMP

const BLOCK_SIZE = 20
const OVERLAP = 8
const STEP_SIZE = BLOCK_SIZE - OVERLAP

function solve_lsp(instance_path::String; output_path::String="metrics/solution.json")::String
    model = build_model(instance_path)
    periods = get_periods(model, :y)
    num_periods = length(periods)
    vars_by_period = variables_by_period(model, :y)

    fixed_vars = Dict{VariableRef,Float64}()
    num_windows = get_blocks_to_cover_horizon(num_periods, STEP_SIZE)

    last_sol_dict = nothing

    for i in 1:num_windows
        start = (i - 1) * STEP_SIZE + 1
        end_period = min(num_periods, start + BLOCK_SIZE - 1)
        current_periods = periods[start:end_period]
        future_periods = periods[(end_period+1):end]

        core_vars, relaxed_vars = partition_by_block(vars_by_period, current_periods, future_periods)

        status, has_vals, sol_dict, obj_val = solve_subproblem(
            model,
            fixed_vars,
            core_vars,
            relaxed_vars;
            sub_time_limit=60.0,
            sub_mip_gap=0.001,
            sub_work_limit=1000.0
        )

        if !subproblem_succeeded(status, has_vals)
            println("The fixing decisions made in previous windows likely made this portion of the problem infeasible.")
            return output_path
        end

        num_to_fix = min(3, length(current_periods))
        periods_to_fix = current_periods[1:num_to_fix]

        core_to_fix = Set{VariableRef}()
        for p in periods_to_fix
            if haskey(vars_by_period, p)
                for v in vars_by_period[p]
                    push!(core_to_fix, v)
                end
            end
        end

        fixed_vars = apply_fixing_policy!(fixed_vars, sol_dict, core_to_fix)
        last_sol_dict = sol_dict
    end

    continuous_vars = Dict{VariableRef,Float64}()
    if last_sol_dict !== nothing
        for (v, val) in last_sol_dict
            if !haskey(fixed_vars, v)
                continuous_vars[v] = val
            end
        end
    end

    write_solution(fixed_vars, continuous_vars, output_path)
    return output_path
end

solve_lsp("material/140_instance.json")
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

# --- Configuration and Constants ---
const BACKLOG_FILE = "material/small_instance.json"
const BLOCK_SIZE = 5
const OUTPUT_FILE = "solution.json"
const SUB_TIME_LIMIT = 10.0  # seconds
const SUB_MIP_GAP = 0.01    # 1% gap
const SUB_WORK_LIMIT = 10000 # arbitrary limit

# --- Core Logic ---

function solve_rolling_horizon_lsp()
    # 1. Build the instance
    println("Step 1: Building the model...")
    LSP = build_model(BACKLOG_FILE)

    # 2. Identify the full time horizon and blocks
    periods = get_periods(LSP, :y)
    T_total = length(periods)
    num_blocks_needed = num_blocks(T_total, BLOCK_SIZE)

    println("Total periods: $T_total. Number of blocks: $num_blocks_needed.")

    # Initialize state variables
    fixed_vars::Dict{VariableRef, Float64} = Dict{VariableRef, Float64}()
    continuous_solution::Dict{VariableRef, Float64} = Dict{VariableRef, Float64}()
    
    # 3. Retrieve variables grouped by period
    vars_by_period = variables_by_period(LSP, :y)

    # 4. Set the first block as the current block (Block index starts at 1)
    # 5. Initialize fixed_vars (already done)

    println("Starting rolling horizon process...")

    # 10. Repeat steps 4 to 9 until all blocks are elaborated
    for block_index in 1:num_blocks_needed
        
        # 5. Get periods for current and future blocks
        current_periods, future_periods = get_block_periods(periods, block_index, BLOCK_SIZE)

        # 6. Partition variables
        core_vars, relaxed_vars = partition_by_block(vars_by_period, current_periods, future_periods)

        println("\n--- Processing Block $block_index (Periods: $(current_periods[1]) to $(current_periods[end])) ---")

        # 7. Solve the current subproblem
        status, has_vals, sub_sol_dict, sub_obj_val = solve_subproblem(
            LSP, 
            fixed_vars, 
            core_vars, 
            relaxed_vars; 
            sub_time_limit=SUB_TIME_LIMIT, 
            sub_mip_gap=SUB_MIP_GAP, 
            sub_work_limit=SUB_WORK_LIMIT
        )
        
        # 8. Check success and apply fixing policy
        if !subproblem_succeeded(status, has_vals)
            # Halt and report infeasibility
            @info "ERROR: The subproblem failed to produce a usable solution. The problem is likely infeasible given the constraints fixed in previous blocks."
            return nothing
        end

        # Apply fixing policy: Fix the binary variables of the current block (core_vars)
        new_fixed_vars = apply_fixing_policy!(
            fixed_vars, 
            sub_sol_dict, 
            core_vars
        )
        
        # Update the overall state:
        # 1. Update fixed variables
        fixed_vars = new_fixed_vars
        
        # 2. Update continuous solution dictionary with all solved values
        # We take the union of current continuous solutions and the latest sub-solution
        # Note: We must ensure we capture all continuous variables (x, I, I_neg, etc.)
        for (v, val) in sub_sol_dict
            # We only update if the variable is continuous or was previously solved
            if !is_binary(v) || JuMP.is_integer(v) 
                 continuous_solution[v] = val
            end
        end
        
        # 9. Shift to the following block (handled by the loop increment)
    end

    # 11. Upon completion, write the result
    println("\nSuccessfully solved all blocks. Writing solution...")
    write_solution(fixed_vars, continuous_solution, OUTPUT_FILE)
    
    return OUTPUT_FILE
end

# Execute the main function
# The resulting return value is the path to the output file.
solve_rolling_horizon_lsp()
using JuMP, Gurobi, JSON

# --- Setup and Initialization ---
const FILENAME = "material/small_instance.json"
const OUTPUT_PATH = "solution_output.json"

# Solver parameters (using placeholder values)
const SUB_TIME_LIMIT = 3600.0 # seconds
const SUB_MIP_GAP = 0.001
const SUB_WORK_LIMIT = 1000

# 1. Build the instance
try
    model = build_model(FILENAME)
catch e
    println("Error building the model. Ensure the instance file '$FILENAME' is correct.")
    exit()
end

# 2. Identify the full time horizon
all_periods = get_periods(model, :y)
T_last = last(all_periods)

# Determine the number of windows
num_windows = num_blocks(length(all_periods), 3)

# Initialize state variables
block_index = 1
fixed_vars::Dict{VariableRef, Float64} = Dict{VariableRef, Float64}()
last_solution_dict::Dict{VariableRef, Float64} = Dict{VariableRef, Float64}()

# 10. Repeat until all windows are processed
while block_index <= num_windows
    println("--- Processing Block $block_index/$num_windows ---")

    # 5. Get period sets
    current_block_periods, future_periods = get_block_periods(
        all_periods, block_index, 5, 3
    )

    # 6. Partition variables
    # variables_by_period must be called only once outside the loop 
    # but for structural clarity, we re-fetch it conceptually.
    var_by_period = variables_by_period(model, :y)
    
    core_vars, relaxed_vars = partition_by_block(
        var_by_period, current_block_periods, future_periods
    )

    # 7. Solve the current subproblem
    # Note: The solver must use the original model structure but operate on a copy.
    status, has_vals, solution_dict, obj_val = solve_subproblem(
        model, 
        fixed_vars, 
        core_vars, 
        relaxed_vars; 
        sub_time_limit=SUB_TIME_LIMIT, 
        sub_mip_gap=SUB_MIP_GAP, 
        sub_work_limit=SUB_WORK_LIMIT
    )
    
    # 8. Check success and apply fixing policy
    if !subproblem_succeeded(status, has_vals)
        # Policy requirement: Report specific failure message
        println("Error: The fixings decided in previous windows likely made this portion of the problem infeasible — this does not necessarily mean the original instance itself is infeasible.")
        break # Halt the procedure
    end

    # Success: Update the stored continuous solution
    last_solution_dict = solution_dict

    # Determine which variables to fix: first 3 periods of the current window
    periods_to_fix = current_block_periods[1:min(3, length(current_block_periods))]
    
    # Identify the variables corresponding to these periods within the core set
    core_vars_to_fix = Set{VariableRef}()
    for t in periods_to_fix
        if haskey(var_by_period, t)
            # We only fix the y variables (binary)
            vars_in_t = var_by_period[t]
            for v in vars_in_t
                # Ensure the variable is indeed binary before fixing it
                if is_binary(v)
                    push!(core_vars_to_fix, v)
                end
            end
        end
    end

    # Apply the fixing policy
    fixed_vars = apply_fixing_policy!(
        fixed_vars, 
        solution_dict, 
        core_vars_to_fix
    )

    # 9. Shift to the following window
    block_index += 1

end

# 11. Write the result upon completion (if the loop completed naturally)
if block_index > num_windows
    write_solution(fixed_vars, last_solution_dict, OUTPUT_PATH)
    println("Solution successfully written to $OUTPUT_PATH")
else
    println("Solution process halted due to infeasibility.")
end
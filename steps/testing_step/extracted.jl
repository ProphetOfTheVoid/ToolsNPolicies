function solve_lsp(instance_path::String; 
                    sub_time_limit::Real=nothing, 
                    sub_mip_gap::Real=nothing, 
                    sub_work_limit::Real=nothing)
    
    # --- Initialization ---
    model = build_model(instance_path)
    periods = get_periods(model)
    vars_by_period = variables_by_period(model)
    
    # State tracking variables
    fixed_vars::Dict{VariableRef, Float64} = Dict{VariableRef, Float64}()
    last_sol_dict::Dict{VariableRef, Float64} = Dict{VariableRef, Float64}()
    
    block_size = 5
    num_blocks_total = num_blocks(periods, block_size)
    
    # --- Iterative Blocking Process ---
    for block_index in 1:num_blocks_total
        
        # 1. Determine period sets for the current block and future blocks
        (current_periods, future_periods) = get_block_periods(periods, block_size, block_index)
        
        # 2. Partition binary variables
        (core_vars, relaxed_vars) = partition_by_block(vars_by_period, current_periods, future_periods)
        
        # 3. Solve Subproblem
        status, has_vals, sol_dict, obj_val = solve_subproblem(
            model, 
            fixed_vars, 
            core_vars, 
            relaxed_vars;
            sub_time_limit = sub_time_limit, 
            sub_mip_gap = sub_mip_gap, 
            sub_work_limit = sub_work_limit
        )
        
        # 4. Check Success
        if !subproblem_succeeded(status, has_vals)
            # Policy requirement: Stop and report failure
            println("FAILURE: The fixing decisions made in previous blocks led to an infeasible subproblem in block $block_index.")
            return "" # Return empty string on failure
        end
        
        # 5. Apply Fixing Policy
        # Note: fixed_vars is mutated and updated by this function call
        fixed_vars = apply_fixing_policy!(fixed_vars, sol_dict, core_vars)
        
        # Store results for the next iteration and final output
        last_sol_dict = sol_dict
    end
    
    # --- Final Solution Assembly ---
    
    # 1. Continuous Variables Dictionary (Non-binary vars from the last solved subproblem)
    continuous_vars::Dict{VariableRef, Float64} = Dict{VariableRef, Float64}()
    
    # Identify the references of all binary variables fixed during the process
    fixed_variable_refs = keys(fixed_vars) 
    
    # Iterate through the values of the last solved subproblem (last_sol_dict)
    for (v_ref, value) in last_sol_dict
        # If the variable reference was not part of the binary variables we fixed
        # (i.e., it's a continuous variable like x, I, I_neg, or cost aggregates)
        if !(v_ref in fixed_variable_refs)
            continuous_vars[v_ref] = value
        end
    end
    
    # 2. Write final solution
    output_path = write_solution(fixed_vars, continuous_vars, "solution_output.json")
    return output_path
end

# Execution Block
# Note: We assume all necessary tools (build_model, get_periods, etc.) 
# are pre-loaded/available in the environment scope.
solve_lsp("material/small_instance.json")
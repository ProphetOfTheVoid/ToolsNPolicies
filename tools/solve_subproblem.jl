# ATOMIC BOX

using JuMP, Gurobi

function solve_subproblem(
    base_model::Model, 
    fixed_vars::Dict{VariableRef, Float64}, 
    core_vars::Set{VariableRef}, 
    relaxed_vars::Set{VariableRef}; 
    sub_time_limit, 
    sub_mip_gap, 
    sub_work_limit
)

    m, ref_map = copy_model(base_model)
    set_optimizer(m, Gurobi.Optimizer)
    set_attribute(m, "OutputFlag", 1)
    set_attribute(m, "Threads", 1)
    
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
    
    sol_dict = Dict{VariableRef, Float64}()
    obj_val = NaN

    if has_vals
        obj_val = objective_value(m)
        for v in all_variables(base_model)
            sol_dict[v] = value(ref_map[v])
        end
    end
    
    return status, has_vals, sol_dict, obj_val
end
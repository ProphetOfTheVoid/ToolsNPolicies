
function apply_fixing_policy!(
    fixed_vars::Dict{VariableRef, Float64},
    current_solution::Dict{VariableRef, Float64},
    core_vars_to_fix::Set{VariableRef}
)
    for v in core_vars_to_fix
        val = current_solution[v]
        rounded_val = round(val)
        fixed_vars[v] = rounded_val
    end
    
    return fixed_vars
end
# Retreives all instances of a variable from the JuMP model and groups them by period
# Introduced because the AI didn't know how to query the JuMP model
function variables_by_period(model::Model, var_symbol::Symbol)
    var_container = model[var_symbol]
    result = Dict{Any, Vector{VariableRef}}()

    for idx in Iterators.product(axes(var_container)...)
        v = var_container[idx...]
        t = idx[end]  # period is assumed to be the last axis
        push!(get!(result, t, VariableRef[]), v)
    end

    return result
end

# Splits a set of variables into two sets: those belonging to the current block (core_vars)
# and those belonging to the future blocks (relaxed_vars).
# For this function to work correctly, the variables MUST BE ORDERED BEFOREHAND (i.e. summon this function after "variables_by_period")
# Should probably be merged into variables_by_period
function partition_by_block(var_by_period::Dict, current_block_periods, future_periods)
    core_vars = Set{VariableRef}()
    for t in current_block_periods
        if haskey(var_by_period, t)
            union!(core_vars, var_by_period[t])
        end
    end

    relaxed_vars = Set{VariableRef}()
    for t in future_periods
        if haskey(var_by_period, t)
            union!(relaxed_vars, var_by_period[t])
        end
    end

    return core_vars, relaxed_vars
end

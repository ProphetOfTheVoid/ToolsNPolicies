
# Writes the solution into a JSON file
# Placeholder: only used so the AI wouldn't print to terminal and create errors
function write_solution(fixed_vars::Dict{VariableRef,Float64}, 
                        continuous_vars::Dict{VariableRef,Float64}, 
                        output_path::String)
    combined = Dict{String, Float64}()
    for (v, val) in fixed_vars
        combined[JuMP.name(v)] = val
    end
    for (v, val) in continuous_vars
        combined[JuMP.name(v)] = val
    end
    
    open(output_path, "w") do io
        write(io, JSON.json(combined))
    end
    
    return output_path
end
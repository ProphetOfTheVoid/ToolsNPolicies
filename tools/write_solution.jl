#=
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
=#


using JSON

# Chiave di ordinamento "naturale": spezza la stringa in parti testo/numero
# così prod2 viene prima di prod10 e i periodi restano in ordine 1..30
function natural_key(s::AbstractString)
    parts = Tuple{Int,Int,String}[]
    for m in eachmatch(r"\d+|\D+", s)
        t = m.match
        if all(isdigit, t)
            push!(parts, (1, parse(Int, t), ""))
        else
            push!(parts, (0, 0, t))
        end
    end
    return parts
end

# Scrive la soluzione in un file JSON, una variabile per riga
function write_solution(fixed_vars::Dict{VariableRef,Float64},
                        continuous_vars::Dict{VariableRef,Float64},
                        output_path::String)
    combined = Dict{String,Float64}()
    for (v, val) in fixed_vars
        combined[JuMP.name(v)] = val
    end
    for (v, val) in continuous_vars
        combined[JuMP.name(v)] = val
    end

    ks = sort!(collect(keys(combined)); by = natural_key)

    open(output_path, "w") do io
        println(io, "{")
        for (i, k) in enumerate(ks)
            sep = i == length(ks) ? "" : ","
            println(io, "  ", JSON.json(k), ": ", JSON.json(combined[k]), sep)
        end
        println(io, "}")
    end

    return output_path
end
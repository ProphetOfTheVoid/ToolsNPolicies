using JuMP, Gurobi

function solve_lot_blocks(; demand::Vector{Int}=[4, 6, 3, 8, 5, 7],
    block_size::Int=2,
    setup_cost::Real=10.0,
    holding_cost::Real=1.0,
    time_limit::Union{Real,Nothing}=nothing,
    output_path::String="solution.json")
    T = length(demand)
    big_m = sum(demand)

    model = Model(Gurobi.Optimizer)
    set_silent(model)
    if time_limit !== nothing
        set_time_limit_sec(model, time_limit)
    end

    @variable(model, x[1:T] >= 0)
    @variable(model, y[1:T], Bin)
    @variable(model, stock[1:T] >= 0)
    @constraint(model, [t in 1:T], x[t] <= big_m * y[t])
    @constraint(model, stock[1] == x[1] - demand[1])
    @constraint(model, [t in 2:T], stock[t] == stock[t-1] + x[t] - demand[t])
    @objective(model, Min, setup_cost * sum(y) + holding_cost * sum(stock))

    fixed = Dict{VariableRef,Float64}()
    total_blocks = cld(T, block_size)
    for b in 1:total_blocks
        first_t = (b - 1) * block_size + 1
        last_t = min(b * block_size, T)
        optimize!(model)
        if termination_status(model) != OPTIMAL
            error("Block $b was not solved to optimality")
        end
        sol = Dict(v => value(v) for v in all_variables(model))
        for t in first_t:last_t
            fixed[y[t]] = round(get(sol, y[t]))
            fix(y[t], fixed[y[t]]; force=true)
        end
    end

    continuous_values = filter(p -> !haskey(fixed, p.variable), sol)

    open(output_path, "w") do io
        println(io, "{")
        println(io, "  \"objective\": $(objective_value(model)),")
        println(io, "  \"setups\": [", join([Int(fixed[y[t]]) for t in 1:T], ", "), "],")
        println(io, "  \"production\": [", join([continuous_values[x[t]] for t in 1:T], ", "), "]")
        println(io, "}")
    end
    return nothing
end

solve_lot_blocks(output_path="solution.json")
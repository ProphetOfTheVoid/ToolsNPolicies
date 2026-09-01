# BUILDS THE MODEL OF THE LSP WITH BACKLOG

function build_model(filename::String; )
    products, periods, machines, d, c, g, f, I0, R, p, r, compat, K, Q, b =
        load_instance_lotsizing_backlog(filename)


    T_last = last(periods)
    for j in products
        max_b = maximum(b[j, t] for t in periods)
        b[j, T_last] = 20 * max_b
    end

    LSP = Model() 

    @variable(LSP, x[machines, products, t in periods] >= 0)
    @variable(LSP, y[machines, products, t in periods], Bin)
    @variable(LSP, I[products, t in periods] >= 0)
    @variable(LSP, I_neg[products, t in periods] >= 0)

    @variable(LSP, tot_setup_cost)
    @variable(LSP, tot_inv_cost)
    @variable(LSP, tot_prod_cost)
    @variable(LSP, tot_backlog_cost)

    @objective(LSP, Min,
        sum(c[j,t]*x[i,j,t] + g[j,t]*y[i,j,t] for i in machines, j in products, t in periods) +
        sum(f[j,t]*I[j,t] for j in products, t in periods) +
        sum(b[j,t]*I_neg[j,t] for j in products, t in periods))

    @constraint(LSP, balance[j in products, t in periods],
        I[j,t] - I_neg[j,t] ==
        (t > first(periods) ? I[j,t-1] - I_neg[j,t-1] : I0[j]) +
        sum(x[i,j,t] for i in machines) - d[j,t])

    @constraint(LSP, storage_capacity[t in periods],
        sum(I[j,t] for j in products) <= Q)

    @constraint(LSP, machine_capacity[i in machines, j in products, t in periods],
        x[i,j,t] <= K * y[i,j,t])

    @constraint(LSP, compatibility[i in machines, j in products, t in periods],
        y[i,j,t] <= compat[i,j])

    @constraint(LSP, resource_capacity[i in machines, t in periods],
        sum(p[j]*x[i,j,t] + r[j]*y[i,j,t] for j in products) <= R[i])

    @constraint(LSP, final_inventory[j in products],
        I[j, last(periods)] == I0[j])

    @constraint(LSP, tot_setup_cost == sum(g[j,t]*y[i,j,t] for i in machines, j in products, t in periods))
    @constraint(LSP, tot_inv_cost   == sum(f[j,t]*I[j,t]   for j in products, t in periods))
    @constraint(LSP, tot_prod_cost  == sum(c[j,t]*x[i,j,t] for i in machines, j in products, t in periods))
    @constraint(LSP, tot_backlog_cost == sum(b[j,t]*I_neg[j,t] for j in products, t in periods))

    return LSP
end
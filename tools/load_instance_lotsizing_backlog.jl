# Upload the instance data from a JSON file


function load_instance_lotsizing_backlog(filename)
    raw_data = read(filename, String)
    data = JSON3.read(raw_data)
    
    products = data.products
    periods = data.periods
    machines = data.machines
    
    K = data.max_prod_K
    Q = data.total_inv_Q
    
    nP = length(products)
    nT = length(periods)
    nM = length(machines)

    # Trasforms the flat vector in a matrix nP x nT
    prepare_mat(vec) = reshape(collect(vec), nT, nP)'
    


    d = DenseAxisArray(prepare_mat(data.demand), products, periods)
    c = DenseAxisArray(prepare_mat(data.prod_cost), products, periods)
    g = DenseAxisArray(prepare_mat(data.setup_cost), products, periods)
    f = DenseAxisArray(prepare_mat(data.inv_cost), products, periods)

    p = DenseAxisArray(collect(data.prod_time_b), products)
    r = DenseAxisArray(collect(data.setup_time_s), products)

    b = DenseAxisArray(prepare_mat(data.backlog_cost), products, periods)

    I0 = DenseAxisArray(collect(data.init_inv), products)
    R  = DenseAxisArray(collect(data.machine_cap), machines)





    compat_flat = collect(data.compat)              # array piatto
    compat_mat = reshape(compat_flat, length(products), length(machines))'  # trasponi
    compat = DenseAxisArray(compat_mat, machines, products)


    return products, periods, machines, d, c, g, f, I0, R, p, r, compat, K, Q, b
end

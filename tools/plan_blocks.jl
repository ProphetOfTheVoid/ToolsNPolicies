
# Returns the ordered list of all periods from the JuMP model
function get_periods(model::Model, var_symbol::Symbol=:y)
    var_container = model[var_symbol]
    period_axis = axes(var_container)[end]
    return sort(collect(period_axis))
end

# Splits an ordered list of periods into blocks, given the block size
# To be merged with get_periods?
function get_block_periods(all_periods::Vector, block_index::Int, block_size::Int, step_size::Int=block_size)
    total = length(all_periods)
    start_idx = (block_index - 1) * step_size + 1
    
    if start_idx > total
        return Int[], Int[]
    end
    
    end_idx = min(start_idx + block_size - 1, total)
    
    current_block_periods = all_periods[start_idx:end_idx]
    future_periods = all_periods[end_idx+1:end]
    
    return current_block_periods, future_periods
end

# computes the number of blocks needed to cover the horizon
# works eve if the last block is smaller (i.e. incomplete)
function num_blocks(total_periods::Int, step_size::Int)
    return div(total_periods-1, step_size) + 1
end
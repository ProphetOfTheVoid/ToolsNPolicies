# check_syntax.jl
#
# Usage: julia check_syntax.jl <path_to_code.jl>
#
# Performs a fast, dependency-free check on Julia code WITHOUT executing it
# and WITHOUT needing any of its called functions (build_model,
# solve_subproblem, etc.) to actually be defined or any package (JuMP,
# Gurobi, ...) to be installed.
#
# Two stages, but note: Julia's modern (JuliaSyntax-based) parser does NOT
# always throw on a syntax error — for some "local" syntax errors, it
# instead embeds an `Expr(:error, ...)` node directly in the returned AST
# and keeps parsing the rest of the file. So a parse-level problem can show
# up nested inside an otherwise-successfully-parsed top-level statement,
# rather than only as a thrown exception from Meta.parseall. Each error we
# report carries its OWN stage ("parse" or "lowering"), rather than one
# single stage for the whole file, to reflect this.
#
#   "parse"    -> a token/grammar-level syntax error (e.g. two semicolons
#                 in a signature, invalid `*v` prefix, bad string escapes).
#                 Found either as a thrown exception from Meta.parseall
#                 (a genuinely fatal, whole-file-halting case), or as an
#                 embedded Expr(:error, ...) node within an otherwise-parsed
#                 statement (a "recovered" case — parsing continued past it).
#   "lowering" -> syntactically valid but invalid once Julia expands syntax
#                 sugar/macros (e.g. `const` declared on a function-local
#                 variable).
#
# NOTE: this does NOT catch bugs that only manifest when the code actually
# runs with real argument types (e.g. a MethodError from an un-splatted
# generator passed to vcat, or an invalid field access like `.variable` on
# a Pair). That requires real execution (level 3), with the actual tool
# implementations and packages available.

"""
    find_local_consts!(expr, in_function, line_ref, results)

Recursively walks a Julia Expr tree looking for `const` declarations nested
inside a `function ... end` body. Unlike `Meta.lower`, which halts at the
FIRST lowering error it hits inside a given top-level statement, this keeps
walking and records EVERY occurrence found.
"""
function find_local_consts!(expr, in_function::Bool, line_ref::Ref{Int}, results)
    if expr isa LineNumberNode
        line_ref[] = expr.line
        return
    end
    if !(expr isa Expr)
        return
    end

    if expr.head === :function
        for (i, arg) in enumerate(expr.args)
            find_local_consts!(arg, i == 1 ? in_function : true, line_ref, results)
        end
        return
    end

    if expr.head === :const && in_function
        push!(results, (line=line_ref[], statement=string(expr)))
        return
    end

    for arg in expr.args
        find_local_consts!(arg, in_function, line_ref, results)
    end
end

"""
    find_parse_errors!(expr, line_ref, results)

Recursively walks a Julia Expr tree looking for `Expr(:error, ...)` nodes —
the parser's "recovered" representation of a local syntax error found
somewhere inside an otherwise-parseable statement (e.g. `*v`). Collects
every occurrence, with a cleaned-up diagnostic message instead of the raw
nested struct dump.
"""
function find_parse_errors!(expr, line_ref::Ref{Int}, results)
    if expr isa LineNumberNode
        line_ref[] = expr.line
        return
    end
    if !(expr isa Expr)
        return
    end

    if expr.head === :error
        msg = (!isempty(expr.args) && expr.args[1] isa Exception) ?
              sprint(showerror, expr.args[1]) : string(expr.args)
        push!(results, (line=line_ref[], message=msg))
        return
    end

    for arg in expr.args
        find_parse_errors!(arg, line_ref, results)
    end
end

function source_line(lines::Vector{<:AbstractString}, n::Int)
    return (1 <= n <= length(lines)) ? strip(lines[n]) : ""
end

function check_file(path::String)
    code = read(path, String)
    lines = split(code, '\n')

    # --- Fatal parse errors: Meta.parseall itself throws ---
    # This happens for syntax errors severe enough that the parser cannot
    # recover at all — the whole file is lost, not just one statement.
    local parsed
    try
        parsed = Meta.parseall(code)
    catch e
        return (ok=false,
            errors=[(line=-1, statement="", stage="parse",
                message=sprint(showerror, e))])
    end

    errors = NamedTuple{(:line, :statement, :stage, :message),Tuple{Int,String,String,String}}[]
    current_line = -1

    for expr in parsed.args
        if expr isa LineNumberNode
            current_line = expr.line
            continue
        end

        # 1. Recovered parse errors embedded in this statement's AST.
        parse_results = NamedTuple{(:line, :message),Tuple{Int,String}}[]
        find_parse_errors!(expr, Ref(current_line), parse_results)

        # 2. Local `const` declarations nested in this statement.
        const_results = NamedTuple{(:line, :statement),Tuple{Int,String}}[]
        find_local_consts!(expr, false, Ref(current_line), const_results)

        if !isempty(parse_results) || !isempty(const_results)
            for pr in parse_results
                push!(errors, (line=pr.line, statement=source_line(lines, pr.line),
                    stage="parse", message=pr.message))
            end
            for cr in const_results
                push!(errors, (line=cr.line, statement=cr.statement,
                    stage="lowering",
                    message="unsupported `const` declaration on local variable"))
            end
            # Skip the generic Meta.lower fallback below — we already know
            # why this statement is broken, in more precise terms than a
            # generic lowering error would give us.
            continue
        end

        # 3. Fallback: anything else Meta.lower catches, not yet catalogued.
        try
            lowered = Meta.lower(Main, expr)
            if lowered isa Expr && lowered.head == :error
                push!(errors, (line=current_line, statement=string(expr),
                    stage="lowering", message=string(lowered.args[1])))
            end
        catch e
            push!(errors, (line=current_line, statement=string(expr),
                stage="lowering", message=sprint(showerror, e)))
        end
    end

    return (ok=isempty(errors), errors=errors)
end

result = check_file(ARGS[1])

# Emit as simple key=value + repeated blocks — easy to parse from Python
# without needing a JSON package on the Julia side.
println("ok=", result.ok)
println("error_count=", length(result.errors))
for err in result.errors
    println("error_begin")
    println("line=", err.line)
    println("stage=", err.stage)
    println("statement=", err.statement)
    println("message_start")
    println(err.message)
    println("message_end")
    println("error_end")
end
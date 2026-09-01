import json, time
from utils import load_file, setup_prompt, query_llm

# GLOBAL VARIABLES
MODEL = "gemma4:latest"
PROMPT_PATH = "prompt.txt"
POLICY_PATH = "p2_detailed.txt"
BACKLOG_INSTANCE_PATH = "material/small_instance.json"
FIX_PATH = "tools/apply_fixing_policy.jl"
BUILD_PATH = "tools/build_model.jl"
CHECK_PATH = "tools/check_subproblem_result.jl"
RETREIVE_PATH = "tools/get_block_variables.jl"
PLAN_PATH = "tools/plan_blocks.jl"
SOLVE_PATH = "tools/solve_subproblem.jl"
WRITE_PATH = "tools/write_solution.jl"
#-----------------------------------------

#-----------------------------------------
def main():
    # Summonign functions that prepare everything
    policy = load_file(POLICY_PATH)
    backlog = load_file(BACKLOG_INSTANCE_PATH)
    retreive_tool = load_file(RETREIVE_PATH)
    build_tool = load_file(BUILD_PATH)
    fix_tool = load_file(FIX_PATH)
    solve_tool = load_file(SOLVE_PATH)
    check_tool = load_file(CHECK_PATH)
    plan_tool = load_file(PLAN_PATH)
    write_tool = load_file(WRITE_PATH)
    prompt = setup_prompt(PROMPT_PATH, policy, backlog, build_tool, check_tool, fix_tool, solve_tool, retreive_tool, plan_tool, write_tool)

    with open("a.txt", "w", encoding="utf-8") as f:
        f.write(prompt)

    #print(prompt)
    print(f"Current policy: {POLICY_PATH}")
    print(f"Current instance: {BACKLOG_INSTANCE_PATH}")
    print(f"Summoning the AI:\n")
    start = time.time()

    output = query_llm(MODEL, prompt)
    #output = ""

    with open("output.txt", "w", encoding="utf-8") as f:
        f.write(output)

    end = time.time()
    print(f"Elasped time for LLM query: {(end-start)/60} minutes")

if __name__=="__main__":
    main()
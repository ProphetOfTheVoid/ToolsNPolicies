import time
from utils import load_file, setup_prompt, setup_prompt_filter, extract_descriptors, setup_prompt_12, setup_prompt_4, setup_prompt_3, query_llm, extract_julia_code, fix_commented_invocation
from steps.testing_step.run_syntax_check import check_julia_syntax
from steps.testing_step.run_check_lv3 import run_level3

MODEL = "gemma4:latest"
FLAG_FILTER = True
FLAG_GEN = True
FLAG_TEST = False

# GLOBAL VARIABLES FOR STEP 0
FILTER_PROMPT_PATH = "steps/filter_step/prompt_filter.txt"
FILTER_OUTPUT_PATH = "steps/filter_step/output_filter.txt"
FILTERED_TOOLS_PATH = "steps/filter_step/filtered_tools.txt"

# GLOBAL VARIABLES FOR STEP 1
PROMPT_PATH = "steps/generation_step/prompt.txt"
POLICY_PATH = "material/policies/policy_p2.txt"
BACKLOG_INSTANCE_PATH = "material/mini_instance.json"
OUTPUT_PATH = "steps/generation_step/output.txt"
TOOL_LIST_PATH = "steps/generation_step/tool_list.txt"

# GLOBAL VARIABLES FOR STEP 2
CHECK_PROMPT_PATH_12 = "steps/testing_step/prompt_12.txt"
CHECK_PROMPT_PATH_4 = "steps/testing_step/prompt_4.txt"
CHECK_OUTPUT_PATH_12 = "steps/testing_step/output_12.txt"
CHECK_OUTPUT_PATH_4 = "steps/testing_step/output_4.jl"
EXTRACTED_CODE_PATH = "steps/testing_step/extracted.jl"
KNOWN_PATTERNS_PATH = "steps/testing_step/known_patterns.txt"
CHECK_OUTPUT_PATH_3 = "steps/testing_step/output_3.jl"
CHECK_PROMPT_PATH_3 = "steps/testing_step/prompt_3.txt"
#-----------------------------------------

#-----------------------------------------
def main():

    print(f"Starting code. The following steps will be executed:")
    print(f"Filter Step:   {FLAG_FILTER}")
    print(f"Generation Step:   {FLAG_GEN}")
    print(f"Testing Step lv 1, 2, 4:      {FLAG_TEST}\n")

    if(FLAG_FILTER):
        policy = load_file(POLICY_PATH)
        tools = load_file(TOOL_LIST_PATH)

        prompt_filter = setup_prompt_filter(FILTER_PROMPT_PATH, policy, tools)
        output_filter = query_llm(MODEL, prompt_filter)

        print(f"Summoning the Filter:\n")
        start = time.time()    
        with open(FILTER_OUTPUT_PATH, "w", encoding="utf-8") as f:
            f.write(output_filter)
        end = time.time()

        filtered_tools = extract_descriptors(output_filter, tools)
        with open(FILTERED_TOOLS_PATH, "w", encoding="utf-8") as f:
            f.write(filtered_tools)

        print(f"Elasped time for filtering query: {(end-start)/60} minutes")
    
    if (FLAG_GEN):
        # Prepare the prompt
        policy = load_file(POLICY_PATH)
        backlog = load_file(BACKLOG_INSTANCE_PATH)
        tools = load_file(FILTERED_TOOLS_PATH)

        prompt_gen = setup_prompt(PROMPT_PATH, policy, backlog, tools)

        #DEBUG: the post-setup prompt is stored for consultation    
        with open("prompt_complete.txt", "w", encoding="utf-8") as f:
            f.write(prompt_gen)
    
        print(f"Current policy: {POLICY_PATH}")
        print(f"Current instance: {BACKLOG_INSTANCE_PATH}")

    
        print(f"Summoning the Generator:\n")
        start = time.time()
        output_gen = query_llm(MODEL, prompt_gen)
        end = time.time()

        
        with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
            f.write(output_gen)

        print(f"Elasped time for generation query: {(end-start)/60} minutes")

    if(FLAG_TEST):
        
        # Loading from where the generation should have stored
        output_gen = load_file(OUTPUT_PATH)    
        extracted_code = extract_julia_code(output_gen)
        fixed_inv_code = fix_commented_invocation(extracted_code)

        if(fixed_inv_code[1]):
            print(f"Removed a commented invocation. Moving forward.\n")

        with open(EXTRACTED_CODE_PATH, "w", encoding="utf-8") as f:
            f.write(fixed_inv_code[0])

        # Run the check lv. 1-2
        extracted_code = load_file(EXTRACTED_CODE_PATH)
        outcome = check_julia_syntax(EXTRACTED_CODE_PATH)

        if(not outcome.ok):
            print(f"Summoning the Supervisor to check on lv. 1-2 errors:\n")
            # Prepare the prompt for supervisor call for lv 1-2
            prompt_12 = setup_prompt_12("steps/testing_step/prompt_12.txt", outcome.format_for_supervisor(), extracted_code)
            
            start = time.time()
            output_12 = query_llm(MODEL, prompt_12)
            end = time.time()
            print(f"Elasped time for Supervisor query lv 1-2: {(end-start)/60} minutes")

            # Save the output
            with open(CHECK_OUTPUT_PATH_12, "w", encoding="utf-8") as f:
                f.write(output_12)
        
        # Run the check lv. 4 <-> Prepare the prompt for supervisor call lv 4
        print(f"Summoning the Supervisor to check on lv. 4 errors:\n")

        if outcome.ok:
            #lv 1-2 did not trigger
            code_to_check = load_file(EXTRACTED_CODE_PATH)
        else:
            #lv 1-2 triggered
            code_to_check = load_file(CHECK_OUTPUT_PATH_12)        
        known_patterns = load_file(KNOWN_PATTERNS_PATH)
        prompt_4 = setup_prompt_4(CHECK_PROMPT_PATH_4, known_patterns, code_to_check)
    
        start = time.time()
        output_4 = query_llm(MODEL, prompt_4)
        end = time.time()

        extracted_code = extract_julia_code(output_4)
        with open(CHECK_OUTPUT_PATH_4, "w", encoding="utf-8") as f:
            f.write(extracted_code)
        
        print(f"Elasped time for Supervisor query lv 4: {(end-start)/60} minutes")
        
        # Run the check lv. 3
        code_to_check = load_file(CHECK_OUTPUT_PATH_4)
        outcome = run_level3(code_to_check)

        if outcome.is_environment_problem:
            # licensed expired, Julia not found, etc.
            # No supervisor
            print(outcome.format_for_supervisor())
        elif not outcome.ok:
            print(f"Summoning the Supervisor to check on lv. 3 errors:\n")
            
            tools = load_file(FILTERED_TOOLS_PATH)
            prompt_3 = setup_prompt_3(CHECK_PROMPT_PATH_3, outcome.format_for_supervisor(), tools, code_to_check)

            #DEBUG
            #with open("p.txt", "w", encoding="utf-8") as f:
            #    f.write(prompt_3)

            start = time.time()
            output_3 = query_llm(MODEL, prompt_3)
            end = time.time()

            #DEBUG
            with open("temp.txt", "w", encoding="utf-8") as f:
                f.write(output_3)


            extracted_code = extract_julia_code(output_3)
            with open(CHECK_OUTPUT_PATH_3, "w", encoding="utf-8") as f:
                f.write(extracted_code)

            print(f"Elasped time for Supervisor query lv 3: {(end-start)/60} minutes")

        
if __name__=="__main__":
    main()
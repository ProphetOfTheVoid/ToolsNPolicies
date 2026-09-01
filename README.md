# AI-driven code creator for multi-index time-dependent MIP problems
The core concept: employing artificial intelligence to generate code which, if executed, provides a solution for a multi-index time-dependent MIP problem (e.g. Lot Sizing Problem). The provided code shall be independant from the current instance, meaning it could be stored for future usage.

The code should be ideally obtained through the application of specific *tools*, following a specific *policy*. The output is the implementation of the tools' invoking rules, detailed in the policy. It's a sequence of tool summoning procedures, interleaved by assignment steps to concretise the policies.

Translating this into branching problems, the AI will be provided with:
1. A tool which, if provided with a node, solves it
2. A policy detailing the heuristic leading to choosing a node (e.g. the most promising one)
The resulting code will be an iterative summoning of the tool, each time applied to a different node, chosen following the heuristic dictated by the policy. Drawing a parallel with a complete branching algorithm, with an outer cycle that moves between nodes and an inner cycle that solves them, the AI is provided with the <u>actual implementation of the inner cycle<u> and a <u>description</u> of the outer cycle.

## The policies
The policies are the rules dictating how the LLM should use the tools and the variables of the current instance. They're described through ordinary language, ideally directly from the user. For example:
- "Start by relaxing the variables of the first period."
- "Assume all variables from period 6 onwards to be integer."
- "Defauly to depth-first exploration during the first 10 nodes. Then, switch to best-first until completed."
Potentially, the policy could also request to use a specific tool. This would introduce the need to filter out currently useless (i.e. unrequested) tools. It shall be looked up later.

### Changing policy
To change policy, change the value of the global variable mentioned at the beginning of tha `main.py` file. 

## The tools
Tools are algorithms, presumably written in Julia, which solves a simplified instance of the current problem. They are the bricks upon which a bigger complete solving algorithm would be built upon. The AI should summon the tools in the code, as if they were functions, providing them with correct input parameters.

### Tool List
* `build_model.jl` contains a function to construct the JuMP model for the LSP, starting from a backlog `.json` istance file
* `get_block_variables.jl` contains:
    * `variables_by_period` groups all instances of a variable by period, gathering it directly from the Model
    * `partition_by_block` divides the grouped variables into two sets: variables belonging to the current block and variables belonging to future blocks
    * `get_period` returns the ordered list of all the periods in the instance, inferring it from the Model
* `solve_subproblem.jl` determines whether an incumbment has been found
* `apply_fixing_policy` permanently assigns values to the current block variables

### Adding a new tool
To add a new tool, the following steps are needed:
1. Create the `.jl` file containing the tool
2. Add its path to the global variables in `main.py`, load it in the `main()` function and pass it as an argument to the `setup_prompt()` invokation
3. Edit the function `setup_prompt()` contained in `utils.py` by adding an argument: the just added tool. 
4. Within the `setup_prompt()` function definition, add a `.replace()` line for the new tool, following the pattern used in the other tools. You will have to come up with a name for the placeholder (e.g. `p_tool`)
5. Go to the prompt file (e.g. `prompt.txt`), scroll down to the portion where the other placeholders for tools are written and add the placeholder you have established for the new tool. Make sure this matched exactly the placeholder name in the previous step
6. If needed, mention the new tool within the policy

## How to run the code
Run the `main.py` file, making sure all components imported through the file system are in the correct path or the paths are edited to match your current file system disposition. With the current settings, you must have an Ollama model running in the background. Changing LLM model, potentially to an API-based approach, will require to edit the `query_llm()` function.
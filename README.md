# AI-driven code creator for multi-index time-dependent MIP problems
The core concept: employing artificial intelligence to generate code which, if executed, provides a solution for a multi-index time-dependent MIP problem (e.g. Lot Sizing Problem). The provided code shall be independent of the current instance, meaning it could be stored for future usage.

The code should ideally be obtained through the application of specific *tools*, following a specific *policy*. The output is the implementation of the tools' invoking rules, detailed in the policy. It's a sequence of tool summoning procedures, interleaved by assignment steps to concretise the policies.

Translating this into branching problems, the AI will be provided with:
1. A tool which, if provided with a node, solves it
2. A policy detailing the heuristic leading to choosing a node (e.g. the most promising one)
The resulting code will be an iterative summoning of the tool, each time applied to a different node, chosen following the heuristic dictated by the policy. Drawing a parallel with a complete branching algorithm, with an outer cycle that moves between nodes and an inner cycle that solves them, the AI is provided with the <u>actual implementation of the inner cycle<u> and a <u>description</u> of the outer cycle.

## The policies
The policies are the rules dictating how the LLM should use the tools and the variables of the current instance. They're described through ordinary language, ideally directly from the user. For example:
- "Start by relaxing the variables of the first period."
- "Assume all variables from period 6 onwards to be integer."
- "Default to depth-first exploration during the first 10 nodes. Then, switch to best-first until completed."
Potentially, the policy could also request to use a specific tool. This would introduce the need to filter out currently useless (i.e. unrequested) tools. It shall be looked up later.

### Changing policy
To change policy, change the value of the global variable mentioned at the beginning of the `main.py` file. 

## The tools
Tools are algorithms, presumably written in Julia, which solve a simplified instance of the current problem. They are the bricks upon which a bigger complete solving algorithm would be built. The AI should summon the tools in the code, as if they were functions, providing them with correct input parameters.

### Adding a new tool
To add a new tool, the following steps are needed:
1. Create the `.jl` file containing the tool
2. Add its path to the global variables in `main.py`, load it in the `main()` function and pass it as an argument to the `setup_prompt()` invocation
3. Edit the function `setup_prompt()` contained in `utils.py` by adding an argument: the just-added tool. 
4. Within the `setup_prompt()` function definition, add a `.replace()` line for the new tool, following the pattern used in the other tools. You will have to come up with a name for the placeholder (e.g. `p_tool`)
5. Go to the prompt file (e.g. `prompt.txt`), scroll down to the portion where the other placeholders for tools are written and add the placeholder you have established for the new tool. Make sure this matches exactly the placeholder name in the previous step
6. If needed, mention the new tool within the policy

## How to run the code
Run the `main.py` file, making sure all components imported through the file system are in the correct path or the paths are edited to match your current file system disposition. With the current settings, you must have an Ollama model running in the background. Changing the LLM model, potentially to an API-based approach, will require editing the `query_llm()` function.

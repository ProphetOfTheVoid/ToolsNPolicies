from pathlib import Path
import ollama

def load_file(path: str) -> str:
    supported = {".jl", ".lp", ".txt", ".json"}
    extension = Path(path).suffix.lower()

    if extension not in supported:
        raise ValueError(f"\nFile format not supported: {extension}")
    else:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()

# The prompt contains a placeholder {instance} in place of the actual instance to save up space
# This function replaces the placeholder with the actual instance
def setup_prompt(prompt_path: str, policy: str, backlog: str, build_tool: str, check_tool:str, fix_tool: str, solve_tool: str, retreive_tool: str, plan_tool: str, write_tool: str) -> str:
    template = load_file(prompt_path)
    template = template.replace("{policy}", policy)
    template = template.replace("{build_tool}", build_tool)
    template = template.replace("{check_tool}", check_tool)
    template = template.replace("{fix_tool}", fix_tool)
    template = template.replace("{solve_tool}", solve_tool)
    template = template.replace("{retreive_tool}", retreive_tool)
    template = template.replace("{plan_tool}", plan_tool)
    template = template.replace("{write_tool}", write_tool)
    template = template.replace("{path}", backlog)
    return template

def query_llm(model: str, message: str) -> str:

    response = ollama.chat(
        model=model,
        messages=[
            #{"role": "system", "content": system_prompt},
            #{"role": "user", "content": user_prompt}
            {"role": "user", "content": message}
        ],
        options={
            "num_ctx": 32768  # 32768 or 16384
        },
        #format="json"
    )
    return response["message"]["content"]
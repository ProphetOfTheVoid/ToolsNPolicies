from pathlib import Path
import ollama, re

def load_file(path: str) -> str:
    supported = {".jl", ".lp", ".txt", ".json"}
    extension = Path(path).suffix.lower()

    if extension not in supported:
        raise ValueError(f"\nFile format not supported: {extension}")
    else:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()


# A descriptor starts with "tool_name(" at the beginning of a block
# (blocks are separated by blank lines). "!" is allowed in the name.
def extract_descriptors(filter_output: str, catalog_text: str) -> str:
    """Return the descriptors of the tools selected by the filter, as one string."""
    # 1. Tool names listed by the filter
    m = re.search(r"\[\[\[TOOLS\]\]\]\s*(.*?)\s*\[\[\[WHY\]\]\]", filter_output, re.DOTALL)
    if m is None:
        raise ValueError("Filter output has no [[[TOOLS]]] ... [[[WHY]]] block")
    names = set()
    for line in m.group(1).splitlines():
        nm = re.match(r"\s*([A-Za-z_]\w*!?)(?:\(.*)?\s*$", line)
        if nm:
            names.add(nm.group(1))

    # 2. Keep the catalog blocks that belong to the selected tools
    selected, found, keep = [], set(), False
    for block in re.split(r"\n\s*\n", catalog_text.strip()):
        block = block.strip()
        header = re.match(r"([A-Za-z_]\w*!?)\(", block)
        if header:  # a new tool starts here
            keep = header.group(1) in names
            if keep:
                found.add(header.group(1))
        if keep:
            selected.append(block)

    # 3. Every name returned by the filter must exist in the catalog
    missing = names - found
    if missing:
        raise ValueError(f"Tools not found in the catalog: {sorted(missing)}")

    return "\n\n".join(selected)

_JULIA_FENCE = re.compile(r"```julia\s*\n(.*?)```", re.DOTALL)
def extract_julia_code(model_output: str) -> str:
    match = _JULIA_FENCE.search(model_output)
    if match is None:
        return model_output.strip()
    return match.group(1).strip()


def fix_commented_invocation(code: str) -> tuple[str, bool]:
    lines = code.rstrip().splitlines()
 
    for i in range(len(lines) - 1, -1, -1):
        stripped = lines[i].strip()
        if not stripped:
            continue
 
        if not stripped.startswith("#"):
            return code, False
 
        indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
        content = stripped[1:]
        if content.startswith(" "):
            content = content[1:]
        lines[i] = indent + content
        return "\n".join(lines), True
 
    return code, False


# The prompt contains a placeholder {instance} in place of the actual instance to save up space
# This function replaces the placeholder with the actual instance
def setup_prompt(prompt_path: str, policy: str, backlog: str, tools: str) -> str:
    template = load_file(prompt_path)
    template = template.replace("{policy}", policy)
    template = template.replace("{tools}", tools)    
    template = template.replace("{path}", backlog)
    return template

def setup_prompt_filter(prompt_path: str, policy: str, tools: str) -> str:
    template = load_file(prompt_path)
    template = template.replace("{policy}", policy)
    template = template.replace("{tools}", tools)    
    return template

def setup_prompt_12(prompt_path: str, errors: str, code: str) -> str:
    template = load_file(prompt_path)
    template = template.replace("{errors_from_level_1_2}", errors)
    template = template.replace("{code_to_check}", code)
    return template

def setup_prompt_4(prompt_path: str, known_patterns: str, code: str) -> str:
    template = load_file(prompt_path)
    template = template.replace("{known_patterns}", known_patterns)
    template = template.replace("{code_to_check}", code)
    return template

def setup_prompt_3(prompt_path: str, errors: str, tool_documentation: str, code: str) -> str:
    template = load_file(prompt_path)
    template = template.replace("{errors_from_level_3}", errors)
    template = template.replace("{tool_documentation}", tool_documentation)
    code_with_line_numbers = "\n".join(f"{i:>3}| {line}" for i, line in enumerate(code.splitlines(), 1))
    template = template.replace("{code_to_check}", code_with_line_numbers)
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
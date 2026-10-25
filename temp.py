import json
d = json.load(open("material/140_instance.json"))
print(len(d["products"]), len(d["machines"]), len(d["periods"]))
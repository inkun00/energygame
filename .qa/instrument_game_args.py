"""QA-only: count serialized game RPC arguments without re-evaluating them."""
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/network/NetworkManager.gd")
src = path.read_text(encoding="utf-8")
pattern = re.compile(r"^(\t+)(_rpc_\w+)\.(rpc_id|rpc)\((.*)\)$", re.MULTILINE)

def split_args(raw):
    parts, depth, start, quote, escaped = [], 0, 0, "", False
    for idx, ch in enumerate(raw):
        if quote:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = ""
        elif ch in ("'", '"'):
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            parts.append(raw[start:idx].strip())
            start = idx + 1
    if raw[start:].strip():
        parts.append(raw[start:].strip())
    assert depth == 0 and not quote
    return parts

n = 0
def replace(m):
    global n
    indent, method, mode, contents = m.groups()
    args = split_args(contents)
    target = args.pop(0) if mode == "rpc_id" else "0"
    n += 1
    v = "qa_args_" + str(n)
    dest = "qa_target_" + str(n)
    refs = [f"{v}[{idx}]" for idx in range(len(args))]
    if mode == "rpc_id":
        refs.insert(0, dest)
    return "\n".join(indent + s for s in (
        f"var {dest}: int = {target}",
        f"var {v}: Array = [{', '.join(args)}]",
        f'_qa_meter("{method}", {dest}, {v})',
        f"{method}.{mode}({', '.join(refs)})"))

expected = len(re.findall(r"\.rpc(?:_id)?\(", src))
src = pattern.sub(replace, src)
assert n == expected and n >= 18, (n, expected)
header = """var _qa_bytes := 0
var _qa_deliveries := 0
var _qa_by_method: Dictionary = {}


func _qa_meter(method: String, target: int, args: Array) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var recipients: int = multiplayer.get_peers().size() if target == 0 else int(target != multiplayer.get_unique_id())
	var size := recipients * var_to_bytes(args).size()
	_qa_bytes += size
	_qa_deliveries += recipients
	_qa_by_method[method] = int(_qa_by_method.get(method, 0)) + size


func _qa_print_meter() -> void:
	print("[GAME_ARGUMENT_BYTES] role=%s bytes=%d deliveries=%d by_method=%s" % [OS.get_cmdline_user_args(), _qa_bytes, _qa_deliveries, JSON.stringify(_qa_by_method)])


"""
assert src.count("func _exit_tree() -> void:\n") == 1
src = src.replace("func _exit_tree() -> void:\n", header + "func _exit_tree() -> void:\n\t_qa_print_meter()\n")
path.write_text(src, encoding="utf-8")



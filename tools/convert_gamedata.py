# -*- coding: utf-8 -*-
"""一次性转换：ClientDatas/*.lua -> gamedata/*.json
规则（在 AGENT_PROMPT.md 中向实现方说明）：
- 纯连续数组（键恰为 1..n）-> JSON 数组
- 其余 -> JSON 对象，键一律转为字符串（数字 id 键会被字符串化）
"""
import json
import os
import sys

from lupa import LuaRuntime

SRC = os.path.join(os.path.dirname(__file__), "..", "reference", "client_lua", "ClientDatas")
DST = os.path.join(os.path.dirname(__file__), "..", "reference", "gamedata")


def lua_to_py(v):
    if v is None or isinstance(v, (bool, int, float, str)):
        if isinstance(v, float) and v.is_integer():
            return int(v)
        return v
    # lupa table
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys):
        n = len(keys)
        if sorted(keys) == list(range(1, n + 1)):
            return [lua_to_py(v[i]) for i in range(1, n + 1)]
    return {str(k): lua_to_py(v[k]) for k in keys}


def main():
    os.makedirs(DST, exist_ok=True)
    lua = LuaRuntime(unpack_returned_tuples=True)
    files = sorted(f for f in os.listdir(SRC) if f.endswith(".lua"))
    failed = []
    for f in files:
        path = os.path.join(SRC, f)
        # 去掉 UTF-8 BOM
        with open(path, "rb") as fh:
            src = fh.read()
        if src.startswith(b"\xef\xbb\xbf"):
            src = src[3:]
        try:
            table = lua.execute(src.decode("utf-8"))
            data = lua_to_py(table)
            out = os.path.join(DST, f[:-4] + ".json")
            with open(out, "w", encoding="utf-8") as fh:
                json.dump(data, fh, ensure_ascii=False, separators=(",", ":"))
        except Exception as e:
            failed.append((f, str(e)))
            continue
        print("ok", f)
    if failed:
        print("\nFAILED:")
        for f, e in failed:
            print(" ", f, e)
        sys.exit(1)
    print("\ndone:", len(files), "tables")


if __name__ == "__main__":
    main()

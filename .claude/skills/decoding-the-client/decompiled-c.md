# The saved C

The whole client's decompiled C is saved, one file per function, in `~/.genesis-prime/decompiled/`. `scripts/decompiled.py`'s docstring is its contract: the file layout, the hash, what `check` and `refresh` do and how long each takes.

- A search across the client is a grep of that folder: a constant, an opcode, a string's use, a struct offset, a callee's name. Decompiling function by function to search costs minutes where a grep costs seconds.
- Run `python3 -I scripts/decompiled.py check` once per session and after any rename. When it says stale or no copy, run `refresh`.
- A proof that cites saved C names the file by address and the hash on its first line.
- The copy is the client's code: nothing in it is committed.

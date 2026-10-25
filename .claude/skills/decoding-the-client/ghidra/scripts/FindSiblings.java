import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.TreeMap;

/** Finds vtables that hold the given function pointers at the given slots, and writes each vtable's start, how many anchors it matched and its first slots. Args: out file, slot count to print, then value:slot pairs. */
public class FindSiblings extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        int show = Integer.parseInt(args[1]);
        Memory mem = currentProgram.getMemory();
        Map<Long, Integer> hits = new TreeMap<>();
        for (int i = 2; i < args.length; i++) {
            String[] p = args[i].split(":");
            long value = Long.decode(p[0]);
            int slot = Integer.parseInt(p[1]);
            for (MemoryBlock b : mem.getBlocks()) {
                if (b.isExecute() || !b.isInitialized()) continue;
                byte[] buf = new byte[(int) b.getSize()];
                b.getBytes(b.getStart(), buf);
                long base = b.getStart().getOffset();
                for (int k = 0; k + 8 <= buf.length; k += 8) {
                    long v = 0;
                    for (int j = 7; j >= 0; j--) v = (v << 8) | (buf[k + j] & 0xff);
                    if (v == value) hits.merge(base + k - 8L * slot, 1, Integer::sum);
                }
            }
        }
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (var e : hits.entrySet()) {
                Address s = toAddr(e.getKey());
                StringBuilder sb = new StringBuilder();
                for (int k = 0; k < show; k++) sb.append(' ').append(Long.toHexString(mem.getLong(s.add(8L * k))));
                out.println(s + " matched " + e.getValue() + ":" + sb);
            }
        }
    }
}

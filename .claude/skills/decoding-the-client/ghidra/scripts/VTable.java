import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** For each address inside a vtable, walks back to the vtable's start, reads the class name from MSVC RTTI, and writes the slot index of the address and every slot. */
public class VTable extends GhidraScript {
    private Memory mem;

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        mem = currentProgram.getMemory();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(args[i]);
                Address start = a;
                while (isCode(mem.getLong(start.subtract(8)))) start = start.subtract(8);
                long col = mem.getLong(start.subtract(8));
                out.println("=== " + a + " vtable " + start + " slot " + (a.subtract(start) / 8) + " class " + className(col));
                for (int k = 0; ; k++) {
                    long v = mem.getLong(start.add(8L * k));
                    if (!isCode(v)) break;
                    out.println("  [" + k + "] " + Long.toHexString(v));
                }
            }
        }
    }

    private boolean isCode(long v) {
        try {
            Address p = toAddr(v);
            var b = mem.getBlock(p);
            return b != null && b.isExecute();
        } catch (Exception e) {
            return false;
        }
    }

    private String className(long col) {
        try {
            Address c = toAddr(col);
            int td = mem.getInt(c.add(12));
            Address name = toAddr(0x140000000L + (td & 0xffffffffL) + 16);
            StringBuilder sb = new StringBuilder();
            for (int k = 0; k < 200; k++) {
                byte b = mem.getByte(name.add(k));
                if (b == 0) break;
                sb.append((char) b);
            }
            return sb.toString();
        } catch (Exception e) {
            return "?";
        }
    }
}

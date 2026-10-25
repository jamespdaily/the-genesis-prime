import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** Reads a table of {string pointer, int32 value} rows of the given stride and count, printing each value and its string as UTF-16 or ASCII. */
public class EnumTable extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] a = getScriptArgs();
        Memory m = currentProgram.getMemory();
        Address base = toAddr(a[1]);
        int count = Integer.parseInt(a[2]);
        int stride = Integer.parseInt(a[3]);
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(a[0])))) {
            for (int i = 0; i < count; i++) {
                Address row = base.add((long) i * stride);
                long p = m.getLong(row);
                int v = m.getInt(row.add(8));
                Address s = toAddr(p);
                StringBuilder sb = new StringBuilder();
                boolean wide = m.getByte(s.add(1)) == 0;
                for (int k = 0; k < 200; k++) {
                    int c = wide ? m.getShort(s.add(k * 2L)) : m.getByte(s.add(k));
                    if (c == 0) break;
                    sb.append((char) c);
                }
                out.println(v + "\t" + sb + "\t" + (wide ? "utf16" : "ascii") + "\t" + Long.toHexString(p));
            }
        }
    }
}

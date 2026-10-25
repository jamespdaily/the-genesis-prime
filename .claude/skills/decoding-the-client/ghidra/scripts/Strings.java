import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** Prints the C string at each given address, and every string in memory that contains each given "s:" substring. */
public class Strings extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Memory mem = currentProgram.getMemory();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 1; i < args.length; i++) {
                if (args[i].startsWith("s:")) {
                    byte[] needle = args[i].substring(2).getBytes();
                    Address s = mem.findBytes(currentProgram.getMinAddress(), needle, null, true, monitor);
                    while (s != null) {
                        Address b = s;
                        while (mem.getByte(b.subtract(1)) >= 0x20) b = b.subtract(1);
                        out.println(args[i] + " " + b + " " + read(mem, b));
                        s = mem.findBytes(s.add(1), needle, null, true, monitor);
                    }
                } else {
                    out.println(args[i] + " " + read(mem, toAddr(args[i])));
                }
            }
        }
    }

    private String read(Memory mem, Address a) throws Exception {
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < 200; k++) {
            byte c = mem.getByte(a.add(k));
            if (c == 0) break;
            sb.append((char) c);
        }
        return sb.toString();
    }
}

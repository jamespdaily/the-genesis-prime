import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * Usage: RenameFunction.java <out> <addr> <name> [<addr> <name>]...
 *    or: RenameFunction.java <out> @<file of "addr name" lines>
 * Names the function that starts at each address, and writes one line per pair: the old and new name, or
 * "inside <entry>" when the address is within another function, which it leaves alone. Where no function
 * holds the address, it makes one there first, as Ghidra's analysis misses functions reached only through
 * pointers. Run it with GHIDRA_WRITE=1 so the project keeps the names.
 */
public class RenameFunction extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        List<String> pairs = new ArrayList<>();
        if (args.length == 2 && args[1].startsWith("@")) {
            for (String line : Files.readAllLines(Path.of(args[1].substring(1)))) {
                if (!line.isBlank()) pairs.addAll(List.of(line.trim().split("\\s+")));
            }
        } else {
            for (int i = 1; i < args.length; i++) pairs.add(args[i]);
        }
        int named = 0, failed = 0;
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 0; i + 1 < pairs.size(); i += 2) {
                String address = pairs.get(i), name = pairs.get(i + 1);
                Function f = getFunctionAt(toAddr(address));
                if (f == null) {
                    Function owner = getFunctionContaining(toAddr(address));
                    if (owner != null) {
                        out.println(address + " " + name + " inside " + owner.getEntryPoint());
                        failed++;
                        continue;
                    }
                    f = createFunction(toAddr(address), null);
                    if (f == null) {
                        out.println(address + " " + name + " no function could be made");
                        failed++;
                        continue;
                    }
                }
                String old = f.getName();
                f.setName(name, SourceType.USER_DEFINED);
                out.println(address + " " + old + " -> " + f.getName());
                named++;
            }
            out.println("named " + named + ", failed " + failed);
        }
    }
}

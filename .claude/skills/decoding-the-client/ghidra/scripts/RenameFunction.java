import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * Usage: RenameFunction.java <out> <addr> <name> [<addr> <name>]...
 * Names the function at each address, making one there if none exists, and writes the old and new name of each.
 * Run it with GHIDRA_WRITE=1 so the project keeps the names.
 */
public class RenameFunction extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 1; i + 1 < args.length; i += 2) {
                Function f = getFunctionAt(toAddr(args[i]));
                if (f == null) f = createFunction(toAddr(args[i]), null);
                if (f == null) {
                    out.println(args[i] + " no function");
                    continue;
                }
                String old = f.getName();
                f.setName(args[i + 1], SourceType.USER_DEFINED);
                out.println(args[i] + " " + old + " -> " + f.getName());
            }
        }
    }
}

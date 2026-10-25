import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** Writes the decompiled C of the function at each given address. */
public class Decompile extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 1; i < args.length; i++) {
                Function f = getFunctionContaining(toAddr(args[i]));
                out.println("=== " + args[i] + " " + (f == null ? "no function" : f.getEntryPoint()));
                if (f == null) continue;
                DecompileResults r = d.decompileFunction(f, 120, monitor);
                out.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "failed: " + r.getErrorMessage());
            }
        }
        d.dispose();
    }
}

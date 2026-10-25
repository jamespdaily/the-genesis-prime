import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import java.io.PrintWriter;
import java.nio.file.*;
import java.util.*;

/** Usage: FuncsRefs.java <out> <addr>... Writes, per address, the sorted unique entry points of the functions that reference it, with a count. */
public class FuncsRefs extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(args[i]);
                TreeMap<String,Integer> m = new TreeMap<>();
                for (Reference r : getReferencesTo(a)) {
                    Function f = getFunctionContaining(r.getFromAddress());
                    String k = f == null ? "none@" + r.getFromAddress() : f.getEntryPoint().toString();
                    m.merge(k, 1, Integer::sum);
                }
                out.println("=== " + a);
                for (var e : m.entrySet()) out.println(e.getKey() + " " + e.getValue());
            }
        }
    }
}

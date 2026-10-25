import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** For each address, writes the function that holds it and every reference to that function's entry, with the function or data the reference comes from. Data references also get the eight pointers around them, to show a vtable. */
public class Refs extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(args[i]);
                Function f = getFunctionContaining(a);
                Address target = f == null ? a : f.getEntryPoint();
                out.println("=== " + a + " in " + (f == null ? "none" : f.getEntryPoint() + " size " + f.getBody().getNumAddresses()));
                for (Reference r : getReferencesTo(a)) {
                    out.println("  ref to addr from " + r.getFromAddress() + " " + r.getReferenceType());
                }
                for (Reference r : getReferencesTo(target)) {
                    Address from = r.getFromAddress();
                    Function ff = getFunctionContaining(from);
                    out.println("  ref to fn from " + from + " " + r.getReferenceType() + " in " + (ff == null ? "data" : ff.getEntryPoint()));
                    if (ff == null) {
                        Address base = from.subtract(32);
                        for (int k = 0; k < 9; k++) {
                            Address p = base.add(8L * k);
                            long v = getLong(p);
                            Function pf = getFunctionAt(toAddr(v));
                            out.println("    " + p + " -> " + Long.toHexString(v) + (pf == null ? "" : " fn"));
                        }
                    }
                }
            }
        }
    }
}

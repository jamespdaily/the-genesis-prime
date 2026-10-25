import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import java.io.PrintWriter;
import java.nio.file.*;

/** For each data address, writes every reference to it with the instruction address and its containing function. */
public class DataRefs extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(args[i]);
                for (Reference r : getReferencesTo(a)) {
                    Function f = getFunctionContaining(r.getFromAddress());
                    out.println(args[i] + " <- " + r.getFromAddress() + " " + r.getReferenceType() + " in " + (f == null ? "none" : f.getName() + "@" + f.getEntryPoint()));
                }
            }
        }
    }
}

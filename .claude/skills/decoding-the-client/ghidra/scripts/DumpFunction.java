import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** Writes the disassembly of the function at the given address to a file. */
public class DumpFunction extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Function f = getFunctionAt(toAddr(args[0]));
        int limit = Integer.parseInt(args[2]);
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))) {
            out.println(f.getName() + " " + f.getBody().getNumAddresses() + " bytes");
            InstructionIterator it = currentProgram.getListing().getInstructions(f.getBody(), true);
            int n = 0;
            while (it.hasNext() && n++ < limit) {
                Instruction ins = it.next();
                out.println(ins.getAddress() + "  " + ins);
            }
        }
    }
}

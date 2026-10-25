import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** Disassembles linearly from each given address until RET or a limit, and writes the instructions to a file. */
public class DumpRange extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        int limit = Integer.parseInt(args[1]);
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 2; i < args.length; i++) {
                Address a = toAddr(args[i]);
                out.println("=== " + args[i]);
                for (int n = 0; n < limit; n++) {
                    Instruction ins = getInstructionAt(a);
                    if (ins == null) {
                        new DisassembleCommand(a, null, true).applyTo(currentProgram, monitor);
                        ins = getInstructionAt(a);
                    }
                    if (ins == null) {
                        out.println(a + "  ??");
                        break;
                    }
                    out.println(ins.getAddress() + "  " + ins);
                    if (ins.getMnemonicString().equals("RET")) break;
                    a = ins.getMaxAddress().next();
                }
            }
        }
    }
}

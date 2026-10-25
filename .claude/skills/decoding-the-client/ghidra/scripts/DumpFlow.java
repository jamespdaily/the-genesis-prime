import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.cmd.function.CreateFunctionCmd;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;

/** Disassembles each given address by following flow, makes it a function if none exists, and writes its instructions in address order. */
public class DumpFlow extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            for (int i = 1; i < args.length; i++) {
                Address a = toAddr(args[i]);
                if (getInstructionAt(a) == null) {
                    new DisassembleCommand(a, null, true).applyTo(currentProgram, monitor);
                }
                Function f = getFunctionAt(a);
                if (f == null) {
                    new CreateFunctionCmd(a).applyTo(currentProgram, monitor);
                    f = getFunctionAt(a);
                }
                out.println("=== " + args[i] + (f == null ? " (no function)" : " " + f.getName()));
                if (f == null) continue;
                InstructionIterator it = currentProgram.getListing().getInstructions(f.getBody(), true);
                while (it.hasNext()) {
                    Instruction ins = it.next();
                    out.println(ins.getAddress() + "  " + ins);
                }
            }
        }
    }
}

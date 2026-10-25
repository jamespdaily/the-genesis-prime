import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

/** Lists every instruction that loads one of the given values into EDX, with its containing function. */
public class FindOpcodeMoves extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Set<Long> wanted = new HashSet<>();
        for (String v : args[1].split(",")) wanted.add(Long.decode(v));
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            InstructionIterator it = currentProgram.getListing().getInstructions(true);
            while (it.hasNext()) {
                Instruction ins = it.next();
                if (ins.getNumOperands() != 2) continue;
                String dst = ins.getDefaultOperandRepresentation(0);
                if (!dst.equals("EDX")) continue;
                for (Object o : ins.getOpObjects(1)) {
                    if (o instanceof Scalar s && wanted.contains(s.getUnsignedValue())) {
                        Function f = getFunctionContaining(ins.getAddress());
                        out.printf("0x%X %s %s in %s%n", s.getUnsignedValue(), ins.getAddress(), ins, f == null ? "?" : f.getEntryPoint());
                    }
                }
            }
        }
    }
}

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;

/** Writes every instruction whose immediate operand, its negation, or its low 32 bits, is one of the given values, with the function that holds it. Args: out file, then a file of hex values one per line. */
public class FindImmediates extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Set<Long> wanted = new HashSet<>();
        for (String line : Files.readAllLines(Path.of(args[1]))) {
            if (!line.isBlank()) wanted.add(Long.decode(line.trim()));
        }
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            InstructionIterator it = currentProgram.getListing().getInstructions(true);
            while (it.hasNext() && !monitor.isCancelled()) {
                Instruction ins = it.next();
                for (int i = 0; i < ins.getNumOperands(); i++) {
                    for (Object o : ins.getOpObjects(i)) {
                        if (!(o instanceof Scalar s)) continue;
                        long v = s.getSignedValue();
                        long low = v & 0xffffffffL;
                        long hit;
                        if (wanted.contains(v)) hit = v;
                        else if (wanted.contains(-v)) hit = -v;
                        else if (wanted.contains(low)) hit = low;
                        else continue;
                        Function f = getFunctionContaining(ins.getAddress());
                        out.println(ins.getAddress() + "\t" + (f == null ? "none" : f.getEntryPoint()) + "\t0x" + Long.toHexString(hit) + "\t" + ins);
                    }
                }
            }
        }
    }
}

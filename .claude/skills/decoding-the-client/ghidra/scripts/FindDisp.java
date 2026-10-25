import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.scalar.Scalar;
import java.io.PrintWriter;
import java.nio.file.*;

/** Usage: FindDisp.java <out> <hex displacement>... Lists every instruction with a scalar operand equal to one of the values (memory displacements and immediates), with its function. */
public class FindDisp extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        long[] want = new long[args.length - 1];
        for (int i = 1; i < args.length; i++) want[i - 1] = Long.decode(args[i]);
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            InstructionIterator it = currentProgram.getListing().getInstructions(true);
            while (it.hasNext()) {
                Instruction ins = it.next();
                for (int op = 0; op < ins.getNumOperands(); op++) {
                    for (Object o : ins.getOpObjects(op)) {
                        if (o instanceof Scalar) {
                            long v = ((Scalar) o).getValue();
                            for (long w : want) if (v == w) {
                                Function f = getFunctionContaining(ins.getAddress());
                                out.println(ins.getAddress() + " " + (f == null ? "-" : f.getEntryPoint()) + " " + ins);
                            }
                        }
                    }
                }
            }
        }
    }
}

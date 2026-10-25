import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;
import ghidra.program.model.symbol.Reference;

import java.io.PrintWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

/**
 * Scores every function by how many opcode numbers from the given file appear as
 * immediate values, lists the largest switch tables, and dumps the constant and
 * call sequence of the best-scoring functions.
 */
public class OpcodeScan extends GhidraScript {

    private record Hit(Function f, Set<Long> known, int client, int server, int scalars, int instructions) {}

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        Map<Long, String> names = new HashMap<>();
        for (String line : Files.readAllLines(Path.of(args[0]))) {
            String[] p = line.trim().split("\\s+");
            names.put(Long.decode(p[1]), p[0]);
        }
        PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(args[1])));

        List<Hit> hits = new ArrayList<>();
        List<Object[]> switches = new ArrayList<>();
        for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
            if (monitor.isCancelled()) break;
            Set<Long> known = new HashSet<>();
            int scalars = 0, instructions = 0;
            InstructionIterator it = currentProgram.getListing().getInstructions(f.getBody(), true);
            while (it.hasNext()) {
                Instruction ins = it.next();
                instructions++;
                for (int i = 0; i < ins.getNumOperands(); i++) {
                    for (Object o : ins.getOpObjects(i)) {
                        if (o instanceof Scalar s) {
                            long v = s.getUnsignedValue();
                            if (v > 0 && v < 0x2000) {
                                scalars++;
                                if (names.containsKey(v)) known.add(v);
                            }
                        }
                    }
                }
                if (ins.getFlowType().isJump() && ins.getFlowType().isComputed()) {
                    int targets = 0;
                    for (Reference r : ins.getReferencesFrom()) if (r.getReferenceType().isFlow()) targets++;
                    if (targets > 50) switches.add(new Object[]{f, ins.getAddress(), targets});
                }
            }
            int client = 0, server = 0;
            for (long v : known) {
                String n = names.get(v);
                if (n.startsWith("Client")) client++;
                else if (n.startsWith("Server")) server++;
            }
            if (known.size() >= 20) hits.add(new Hit(f, known, client, server, scalars, instructions));
        }

        hits.sort((a, b) -> b.known.size() - a.known.size());
        out.println("== functions by distinct known opcodes (client/server)");
        for (Hit h : hits.subList(0, Math.min(30, hits.size())))
            out.printf("%s %-28s known=%d client=%d server=%d scalars=%d instr=%d%n",
                h.f.getEntryPoint(), h.f.getName(), h.known.size(), h.client, h.server, h.scalars, h.instructions);

        switches.sort((a, b) -> (int) b[2] - (int) a[2]);
        out.println("== largest switch tables");
        for (Object[] s : switches.subList(0, Math.min(20, switches.size())))
            out.printf("%s in %s at %s targets=%d%n", ((Function) s[0]).getEntryPoint(), ((Function) s[0]).getName(), s[1], (int) s[2]);

        out.println("== constant/call sequences of top functions");
        for (Hit h : hits.subList(0, Math.min(4, hits.size()))) {
            out.println("-- " + h.f.getEntryPoint() + " " + h.f.getName());
            Deque<Long> recent = new ArrayDeque<>();
            InstructionIterator it = currentProgram.getListing().getInstructions(h.f.getBody(), true);
            int printed = 0;
            while (it.hasNext() && printed < 400) {
                Instruction ins = it.next();
                for (int i = 0; i < ins.getNumOperands(); i++)
                    for (Object o : ins.getOpObjects(i))
                        if (o instanceof Scalar s && s.getUnsignedValue() > 0 && s.getUnsignedValue() < 0x2000) {
                            recent.addLast(s.getUnsignedValue());
                            if (recent.size() > 3) recent.removeFirst();
                        }
                if (ins.getFlowType().isCall()) {
                    Address[] targets = ins.getFlows();
                    String t = targets.length > 0 ? targets[0].toString() : "?";
                    StringBuilder sb = new StringBuilder();
                    for (long v : recent) sb.append(String.format("0x%04X(%s) ", v, names.getOrDefault(v, "-")));
                    out.println("  " + ins.getAddress() + " call " + t + " after " + sb);
                    recent.clear();
                    printed++;
                }
            }
        }
        out.close();
        println("OpcodeScan wrote " + args[1]);
    }
}

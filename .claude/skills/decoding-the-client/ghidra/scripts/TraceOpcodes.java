import ghidra.app.cmd.disassemble.DisassembleCommand;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.mem.Memory;

import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/** Dumps the in-game dispatcher case for each received opcode ("r:0x186") and the Lua binding function for each Lua name ("l:RepairItemVendor"), linearly up to a limit. */
public class TraceOpcodes extends GhidraScript {
    private PrintWriter out;
    private int limit;

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        limit = Integer.parseInt(args[1]);
        Memory mem = currentProgram.getMemory();
        try (PrintWriter w = new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
            out = w;
            for (int i = 2; i < args.length; i++) {
                String a = args[i];
                if (a.startsWith("r:")) {
                    int id = Integer.decode(a.substring(2));
                    int rva = mem.getInt(toAddr(0x1403F1344L + 4L * (id - 0x61)));
                    Address t = toAddr(0x140000000L + (rva & 0xffffffffL));
                    out.println("=== recv " + a.substring(2) + " case " + t);
                    dump(t);
                } else if (a.startsWith("l:")) {
                    byte[] name = (a.substring(2) + "\0").getBytes(StandardCharsets.US_ASCII);
                    Address s = mem.findBytes(currentProgram.getMinAddress(), name, null, true, monitor);
                    while (s != null) {
                        byte[] ptr = new byte[8];
                        long v = s.getOffset();
                        for (int k = 0; k < 8; k++) ptr[k] = (byte) (v >>> (8 * k));
                        Address p = mem.findBytes(currentProgram.getMinAddress(), ptr, null, true, monitor);
                        while (p != null) {
                            Address fn = toAddr(mem.getLong(p.add(8)));
                            out.println("=== lua " + a.substring(2) + " str " + s + " entry " + p + " fn " + fn);
                            dump(fn);
                            p = mem.findBytes(p.add(1), ptr, null, true, monitor);
                        }
                        s = mem.findBytes(s.add(1), name, null, true, monitor);
                    }
                } else if (a.startsWith("c:")) {
                    long target = Long.parseLong(a.substring(2), 16);
                    ghidra.program.model.mem.MemoryBlock text = mem.getBlock(".text");
                    long start = text.getStart().getOffset(), end = text.getEnd().getOffset();
                    byte[] buf = new byte[(int) (end - start + 1)];
                    mem.getBytes(text.getStart(), buf);
                    for (int k = 0; k + 5 <= buf.length; k++) {
                        if ((buf[k] & 0xff) != 0xE8) continue;
                        int rel = (buf[k + 1] & 0xff) | (buf[k + 2] & 0xff) << 8 | (buf[k + 3] & 0xff) << 16 | (buf[k + 4] & 0xff) << 24;
                        if (start + k + 5 + rel != target) continue;
                        int b = k;
                        while (b > 2 && !((buf[b - 1] & 0xff) == 0xCC && (buf[b - 2] & 0xff) == 0xCC) && k - b < 0x400) b--;
                        out.println("=== caller of " + a.substring(2) + " at " + Long.toHexString(start + k) + " fn " + Long.toHexString(start + b));
                    }
                } else if (a.startsWith("f:")) {
                    Address t = toAddr(a.substring(2));
                    out.println("=== fn " + t);
                    dump(t);
                }
            }
        }
    }

    private void dump(Address a) throws Exception {
        for (int n = 0; n < limit; n++) {
            Instruction ins = getInstructionAt(a);
            if (ins == null) {
                new DisassembleCommand(a, null, false).applyTo(currentProgram, monitor);
                ins = getInstructionAt(a);
            }
            if (ins == null) {
                out.println(a + "  ??");
                return;
            }
            out.println(ins.getAddress() + "  " + ins);
            String m = ins.getMnemonicString();
            if (m.equals("INT3")) return;
            a = ins.getMaxAddress().next();
        }
    }
}

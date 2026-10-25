import ghidra.app.script.GhidraScript;
import java.io.PrintWriter;
import java.nio.file.*;
public class ReadConst extends GhidraScript {
  protected void run() throws Exception {
    String[] a = getScriptArgs();
    try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(Path.of(a[0])))) {
      for (int i = 1; i < a.length; i++) {
        int d = currentProgram.getMemory().getInt(toAddr(a[i]));
        long q = currentProgram.getMemory().getLong(toAddr(a[i]));
        out.println(a[i] + " dword=0x" + Integer.toHexString(d) + " float=" + Float.intBitsToFloat(d) + " double=" + Double.longBitsToDouble(q) + " q=0x" + Long.toHexString(q));
      }
    }
  }
}

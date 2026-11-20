import java.lang.module.ModuleFinder;
import java.util.Properties;

public class HelloWorld {

    private static void probe(String key) {
        System.out.println("  " + key + " = " + System.getProperty(key));
    }

    private static void moduleState(String name) {
        boolean present = ModuleFinder.ofSystem().find(name).isPresent();
        System.out.println("  " + name + " : " + (present ? "vorhanden" : "FEHLT"));
    }

    public static void main(String[] args) {
        System.out.println("=== OpenJDK/mobile Probe ===");

        System.out.println("[VM]");
        probe("java.vm.name");
        probe("java.vm.info");
        probe("java.vm.version");
        probe("java.version");
        probe("java.home");

        System.out.println("[OS]");
        probe("os.name");
        probe("os.version");
        probe("os.arch");
        probe("user.dir");
        probe("user.timezone");
        System.out.println("  availableProcessors = " + Runtime.getRuntime().availableProcessors());

        System.out.println("[Module-Umfang]");
        moduleState("java.base");
        moduleState("java.logging");
        moduleState("java.xml");
        moduleState("java.net.http");
        moduleState("java.sql");
        moduleState("java.desktop");
        System.out.println("  Module gesamt = " + ModuleFinder.ofSystem().findAll().size());

        System.out.println("[Speicher]");
        Runtime r = Runtime.getRuntime();
        System.out.println("  maxMemory = " + (r.maxMemory() / (1024 * 1024)) + " MB");
        System.out.println("  totalMemory = " + (r.totalMemory() / (1024 * 1024)) + " MB");

        System.out.println("[Interpreter-Durchsatz]");
        long acc = 0;
        long t0 = System.nanoTime();
        for (int i = 0; i < 20_000_000; i++) {
            acc += Long.hashCode(acc ^ i);
        }
        long ms = (System.nanoTime() - t0) / 1_000_000;
        System.out.println("  20M Iterationen in " + ms + " ms (acc=" + acc + ")");

        Properties p = System.getProperties();
        System.out.println("[Umgebung]");
        System.out.println("  Anzahl System-Properties = " + p.size());
        System.out.println("=== Probe beendet ===");
    }
}

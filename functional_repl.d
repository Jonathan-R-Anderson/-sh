import std.stdio;
import std.string;
import shell_runtime;
import tui_language;
import language_builder;

void main() {
    writeln("=== LFE-SH Functional Language REPL ===");
    writeln("Type 'help' for commands, 'exit' to quit");
    writeln();

    auto interpreter = createFunctionalInterpreter();
    auto tui = new TUILanguage();

    while (true) {
        write("func> ");
        string line = readln();

        if (line is null || line == "exit\n") break;
        if (line.strip().length == 0) continue;

        line = line.strip();

        if (line == "help") {
            writeln("Available commands:");
            writeln("  help     - Show this help");
            writeln("  exit     - Exit the REPL");
            writeln("  demo     - Run demonstration");
            writeln("  tui      - Show TUI example");
            writeln("  lang     - Create a language");
            writeln("Any other input is evaluated as a functional expression");
            continue;
        }

        if (line == "demo") {
            writeln("Demo expressions:");
            string[] demos = [
                "(+ 1 2 3 4 5)",
                "(* 6 7)",
                "(/ 100 5)",
                "(layout \"demo\" \"panel\" 0 0 40 10 \"Demo Panel\")",
                "(render)"
            ];
            foreach(expr; demos) {
                write("  ", expr, " => ");
                try {
                    auto exprs = interpreter.parse(expr);
                    auto result = interpreter.eval(exprs);
                    writeln(result.toString());
                } catch (Exception e) {
                    writeln("Error: ", e.msg);
                }
            }
            continue;
        }

        if (line == "tui") {
            writeln("Creating TUI example...");
            string tuiExample = `
                (tui
                  (element window id:demo content:"REPL Demo"
                    (element panel id:header x:0 y:0 width:40 height:3
                      (element text id:title content:"Functional REPL" fg:cyan)
                    )
                    (element panel id:body x:0 y:3 width:40 height:8
                      (element text id:msg content:"Interactive functional programming")
                      (element button id:btnOk content:"OK" fg:green)
                    )
                  )
                )
            `;

            try {
                auto tuiRoot = tui.parse(tuiExample);
                writeln(tui.renderTerminal(tuiRoot));
            } catch (Exception e) {
                writeln("TUI Error: ", e.msg);
            }
            continue;
        }

        if (line == "lang") {
            writeln("Creating a mini-language 'QuickMath'...");
            auto quickMath = new LanguageBuilder()
                .meta("QuickMath", "Fast calculator DSL")
                .version_("1.0")
                .token("NUM", "\\d+", "42", "Numbers")
                .token("OP", "[+\\-*/]", "+", "Basic ops")
                .rule("calc -> NUM", "Number", "parseNum")
                .rule("calc -> calc OP calc", "Operation", "doOp")
                .builtin("clear", [], "Clear result", "reset()")
                .runtime(true, 5, 1);

            writeln("Generated QuickMath language:");
            writeln(quickMath.build());
            writeln("Saved to 'quickmath.lang'");
            quickMath.save("quickmath.lang");
            continue;
        }

        // Evaluate as functional expression
        try {
            auto exprs = interpreter.parse(line);
            auto result = interpreter.eval(exprs);
            writeln("=> ", result.toString());
        } catch (Exception e) {
            writeln("Error: ", e.msg);
        }
    }

    writeln("\nGoodbye!");
}
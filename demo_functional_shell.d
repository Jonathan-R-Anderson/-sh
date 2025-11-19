import std.stdio;
import std.string;
import shell_runtime;
import tui_language;
import language_builder;

void main() {
    writeln("=== Functional Language System Demonstration ===");
    writeln();

    // Part 1: Basic Functional Language Runtime
    writeln("1. Testing Functional Language Runtime:");
    writeln("=====================================");

    auto interpreter = createFunctionalInterpreter();

    string[] testExpressions = [
        "(+ 1 2 3)",
        "(* 10 5)",
        "(- 20 8)",
        "(/ 100 4)",
        "(layout \"main\" \"panel\" 0 0 80 20 \"Hello Functional World\")",
        "(widget \"btn1\" \"button\" \"content\" \"Click Me\" \"fg\" \"blue\")",
        "(render)"
    ];

    foreach(expr; testExpressions) {
        write("Expression: ", expr, " => ");
        try {
            auto exprs = interpreter.parse(expr);
            auto result = interpreter.eval(exprs);
            writeln(result.toString());
        } catch (Exception e) {
            writeln("Error: ", e.msg);
        }
    }

    writeln();

    // Part 2: TUI Description Language
    writeln("2. Testing TUI Description Language:");
    writeln("====================================");

    auto tui = new TUILanguage();

    string complexTUI = `
        (tui
          (element window id:main content:"Functional Application"
            (element panel id:header x:0 y:0 width:80 height:3
              (element text id:title content:"Functional Shell System" fg:cyan bold:true)
            )
            (element panel id:toolbar x:0 y:3 width:80 height:3
              (element button id:btnNew content:"New" fg:green)
              (element button id:btnOpen content:"Open" fg:blue)
              (element button id:btnSave content:"Save" fg:red)
              (element button id:btnExit content:"Exit" fg:white bg:gray)
            )
            (element panel id:main_content x:0 y:6 width:80 height:18
              (element text id:info content:"This interface is created using functional programming")
              (element list id:items x:2 y:2 width:76 height:10
                style:"listStyle"
              )
              (element input id:cmdline x:2 y:14 width:76 height:1
                placeholder:"Enter functional expression..."
              )
            )
            (element panel id:status x:0 y:24 width:80 height:1
              (element text id:status_msg content:"Ready" fg:green)
            )
          )
        )
    `;

    try {
        auto tuiRoot = tui.parse(complexTUI);
        writeln("Complex TUI Structure:");
        writeln("=======================");
        writeln(tui.renderTerminal(tuiRoot));
    } catch (Exception e) {
        writeln("TUI Error: ", e.msg);
    }

    writeln();

    // Part 3: Fluid Language Creation
    writeln("3. Testing Fluid Language Creation:");
    writeln("===================================");

    // Create a custom "CalcLang" - a calculator language
    auto calcLang = new LanguageBuilder()
        .meta("CalcLang", "A functional calculator language")
        .version_("1.0", "LFE-SH Team")
        .token("NUMBER", "\\d+", "42", "Numbers")
        .token("OP", "[+\\-*/%^]", "+", "Operators")
        .token("LPAREN", "\\(", "(", "Left parenthesis")
        .token("RPAREN", "\\)", ")", "Right parenthesis")
        .rule("expr -> term", "Single term", "evalTerm")
        .rule("expr -> expr OP term", "Binary operation", "binaryOp(evalExpr, OP, evalTerm)")
        .rule("term -> NUMBER", "Number literal", "parseNumber")
        .rule("term -> LPAREN expr RPAREN", "Parenthesized expression", "evalExpr")
        .rule("term -> function", "Function call", "callFunction")
        .rule("function -> func_name LPAREN args RPAREN", "Function", "callFunction")
        .builtin("sin", ["angle"], "Sine function", "math.sin(angle)")
        .builtin("cos", ["angle"], "Cosine function", "math.cos(angle)")
        .builtin("sqrt", ["value"], "Square root", "math.sqrt(value)")
        .runtime(true, 10, 5);

    writeln("Generated CalcLang Specification:");
    writeln("=================================");
    writeln(calcLang.build());

    // Save the language
    calcLang.save("calclang.lang");
    writeln("CalcLang saved to 'calclang.lang'");

    // Create a scripting language template
    writeln();
    writeln("4. Testing Language Templates:");
    writeln("==============================");

    auto templateRegistry = new TemplateRegistry();

    writeln("Available templates:");
    foreach(name; templateRegistry.listTemplates()) {
        writeln("  - ", name);
    }

    // Create a language from template
    auto scriptLang = templateRegistry.createFromTemplate("scripting", "MyScript");
    scriptLang.version_("2.0", "Custom User");

    writeln();
    writeln("Created scripting language specification:");
    writeln(scriptLang.build());

    writeln();
    writeln("=== Functional Language System Complete ===");
    writeln("Features demonstrated:");
    writeln("✓ Functional expression interpreter");
    writeln("✓ TUI description language");
    writeln("✓ Fluid language creation system");
    writeln("✓ Language templates");
    writeln("✓ Language serialization");
    writeln("✓ Runtime configuration");
}
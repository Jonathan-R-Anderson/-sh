import std.stdio;
import shell_runtime;
import tui_language;
import language_builder;

void main() {
    // Test functional TUI creation
    TUILanguage tui = new TUILanguage();

    // Create a simple functional TUI definition
    string tuiDefinition = `
        (tui
          (element window id:main content:"My Application"
            (element panel id:toolbar x:0 y:0 width:80 height:3
              (element button id:btnNew content:"New" fg:blue)
              (element button id:btnOpen content:"Open" fg:green)
            )
            (element panel id:content x:0 y:3 width:80 height:20
              (element text id:welcome content:"Welcome to Functional TUI!" fg:cyan)
            )
          )
        )
    `;

    writeln("=== Functional TUI Language Test ===");
    writeln();

    try {
        // Parse and render TUI
        TUIElement root = tui.parse(tuiDefinition);
        writeln("Parsed TUI Structure:");
        writeln("======================");
        writeln(tui.renderTerminal(root));
    } catch (Exception e) {
        writeln("Error parsing TUI: ", e.msg);
    }

    writeln();
    writeln("=== Testing Language Builder ===");

    // Test language builder
    auto builder = new LanguageBuilder()
        .meta("Test Language", "A simple functional language")
        .version_("1.0", "LFE-SH")
        .addCommonTokens()
        .addExpressionGrammar()
        .addCommonBuiltins()
        .runtime(true, 30, 10);

    string languageSpec = builder.build();
    writeln("Generated Language Specification:");
    writeln("=================================");
    writeln(languageSpec);
}
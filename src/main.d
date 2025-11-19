import std.stdio;
import std.string;
import core.stdc.stdlib;
import core.stdc.stdio;
import core.sys.posix.unistd : isatty, STDIN_FILENO;
import std.conv : to;
import frontend;
import lferepl;
import shell.executor : execute, initializeShell;
import shell.parser : parseShellCommand;
import shell.ast : Node;
import shell.config;
import shell.themes;
import shell.completion;
import shell.keybindings;
import shell.plugins;
import tui.core;
import tui.shell;
import tui.panes;
import tui.widgets;
import languages.framework;

// D bindings for GNU Readline
extern (C) {
    char* readline(const char* prompt);
    void add_history(const char* line);
    int read_history(const char* filename);
    int write_history(const char* filename);
}

// Global configuration and systems
__gshared ConfigManager configManager;
__gshared ThemeManager themeManager;
__gshared CompletionEngine completionEngine;
__gshared KeyBindingManager keyBindingManager;
__gshared PluginManager pluginManager;
__gshared ShellContext shellContext;
__gshared LanguageRegistry languageRegistry;
__gshared TUIManager tuiManager;
__gshared TUIShell tuiShell;

// Processes a single line of input (either shell or LFE)
void processLine(string line) {
    if (line.length == 0) {
        return;
    }

    string interpolatedLine = interpolateLfe(line);

    if (isLfeInput(interpolatedLine)) {
        try {
            auto result = evalString(interpolatedLine);
            writeln(valueToString(result));
        } catch (Exception e) {
            writeln("LFE Error: ", e.msg);
        }
    } else {
        Node ast = parseShellCommand(interpolatedLine);
        execute(ast);
    }
}

// The main interactive shell loop
void runInteractiveShell() {
    char* line_read;
    while ((line_read = readline(getPromptString().toStringz)) !is null) {
        if (line_read[0] != '\0') {
            add_history(line_read);
        }

        string line = fromStringz(line_read).strip.idup;
        free(line_read);

        if (line == "exit") {
            break;
        }

        // Handle special commands
        if (line.startsWith("tui ")) {
            handleTUICommand(line[4..$].strip());
            continue;
        }

        if (line == "themes") {
            themeManager.listThemes();
            continue;
        }

        if (line.startsWith("theme ")) {
            string themeName = line[6..$].strip;
            themeManager.setTheme(themeName);
            writeln("Theme switched to: " ~ themeName);
            continue;
        }

        if (line == "plugins") {
            pluginManager.printStatistics();
            continue;
        }

        if (line.startsWith("plugin ")) {
            handlePluginCommand(line[7..$].strip());
            continue;
        }

        // Notify plugins before command execution
        string[] args = line.split();
        if (args.length > 0) {
            pluginManager.onCommandExecuted(args[0], args[1..$]);
        }

        processLine(line);
    }

    // Notify plugins of shutdown
    pluginManager.onShellShutdown();
    writeln("\nexit");
}

// Handle TUI-specific commands
void handleTUICommand(string command) {
    if (command == "on" || command == "enable") {
        enterTUIMode();
    } else if (command == "off" || command == "disable") {
        writeln("Already in terminal mode");
    } else if (command == "status") {
        writeln("TUI mode: available - use 'tui on' to enter");
    } else {
        writeln("Unknown TUI command. Available: on, off, status");
    }
}

// Enter TUI mode
void enterTUIMode() {
    if (tuiShell is null) {
        tuiShell = new TUIShell(tuiManager, configManager, pluginManager, languageRegistry);
    }

    writeln("Entering TUI mode...");
    writeln("Press F1 for help, Ctrl+Q to exit");

    try {
        tuiShell.enterTUIMode();
    } catch (Exception e) {
        writeln("Error in TUI mode: ", e.msg);
    }

    writeln("Exited TUI mode");
}

// Handle plugin commands
void handlePluginCommand(string command) {
    string[] parts = command.split();
    if (parts.length == 0) return;

    string action = parts[0];
    string pluginName = parts.length > 1 ? parts[1] : "";

    if (action == "list") {
        string[] plugins = pluginManager.listLoadedPlugins();
        if (plugins.length == 0) {
            writeln("No plugins loaded");
        } else {
            writeln("Loaded plugins:");
            foreach(name; plugins) {
                auto metadata = pluginManager.getPluginMetadata(name);
                writeln("  " ~ name ~ " v" ~ metadata.version ~ " - " ~ metadata.description);
            }
        }
    } else if (action == "enable" && pluginName.length > 0) {
        if (pluginManager.enablePlugin(pluginName)) {
            writeln("Plugin '" ~ pluginName ~ "' enabled");
        } else {
            writeln("Failed to enable plugin '" ~ pluginName ~ "'");
        }
    } else if (action == "disable" && pluginName.length > 0) {
        if (pluginManager.disablePlugin(pluginName)) {
            writeln("Plugin '" ~ pluginName ~ "' disabled");
        } else {
            writeln("Failed to disable plugin '" ~ pluginName ~ "'");
        }
    } else if (action == "reload" && pluginName.length > 0) {
        if (pluginManager.reloadPlugin(pluginName)) {
            writeln("Plugin '" ~ pluginName ~ "' reloaded");
        } else {
            writeln("Failed to reload plugin '" ~ pluginName ~ "'");
        }
    } else {
        writeln("Unknown plugin command. Available: list, enable <name>, disable <name>, reload <name>");
    }
}

// Initialize enhanced shell systems
void initializeEnhancedShell() {
    // Initialize configuration system
    configManager = new ConfigManager();
    shellContext = configManager.getShellContext();

    // Initialize theme system
    themeManager = new ThemeManager(configManager);

    // Initialize completion engine
    completionEngine = new CompletionEngine(configManager);

    // Initialize key bindings
    keyBindingManager = new KeyBindingManager(configManager);

    // Initialize plugin system
    pluginManager = new PluginManager(configManager);

    // Initialize language framework
    languageRegistry = new LanguageRegistry(configManager);

    // Initialize TUI system
    tuiManager = new TUIManager(configManager);

    // Load plugins
    foreach(pluginPath; pluginManager.discoverPlugins()) {
        pluginManager.loadPlugin(pluginPath);
    }

    // Notify plugins of shell startup
    pluginManager.onShellStartup();

    // Display startup message if enabled
    if (configManager.getConfigBool("SHOW_STARTUP_MESSAGE", true)) {
        Theme currentTheme = themeManager.getCurrentTheme();
        string welcomeMessage = "Welcome to LFE-SH v1.0 with enhanced TUI support";
        writeln(currentTheme.formatText(welcomeMessage, "info", "bold"));

        int loadedPlugins = pluginManager.listLoadedPlugins().length;
        if (loadedPlugins > 0) {
            writeln(currentTheme.formatText(
                "Loaded " ~ to!string(loadedPlugins) ~ " plugins",
                "success",
                "normal"
            ));
        }
    }
}

// Get formatted prompt string
string getPromptString() {
    string promptTemplate = configManager.getConfig("PS1", "lfe-sh> ");
    Theme currentTheme = themeManager.getCurrentTheme();
    string promptColor = configManager.getConfig("PS_COLOR", "green");

    // Simple template substitution
    string prompt = promptTemplate;

    // Add theme formatting
    if (promptColor != "default") {
        prompt = currentTheme.formatText(prompt, promptColor, "prompt");
    }

    return prompt;
}

// Main entry point for the shell
void main(string[] args) {
    if (isatty(STDIN_FILENO)) {
        initializeShell();
        initializeEnhancedShell();
        runInteractiveShell();
    } else {
        // Non-interactive mode (e.g., from a pipe)
        string line;
        while((line = std.stdio.stdin.readln()) !is null) {
            processLine(line.strip);
        }
    }
}

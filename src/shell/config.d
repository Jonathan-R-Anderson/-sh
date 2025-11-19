module shell.config;

import std.stdio;
import std.string;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.conv : to;
import std.json;
import core.stdc.stdlib : getenv;
import std.process : environment;

/// Configuration variable with metadata
struct ConfigVar {
    string value;
    string description;
    string type; // "string", "int", "bool", "path"
    bool userSettable;
    string defaultValue;
}

/// Theme configuration
struct ThemeConfig {
    string name;
    string[string] colors; // fg, bg, cursor, selection, etc.
    string[string] styles; // prompt, command, output, error
}

/// Completion function signature
alias CompletionFunc = string[] function(string prefix, string context);

/// Shell context for plugins
class ShellContext {
    string[string] variables;
    string[string] aliases;
    ThemeConfig currentTheme;
    ConfigManager configManager;

    void setVariable(string name, string value) {
        variables[name] = value;
    }

    string getVariable(string name) {
        return variables.get(name, "");
    }

    void setAlias(string name, string command) {
        aliases[name] = command;
    }

    string getAlias(string name) {
        return aliases.get(name, "");
    }
}

/// Main configuration manager
class ConfigManager {
    private ConfigVar[string] configVars;
    private string[] configPaths;
    private ThemeConfig[string] themes;
    private ThemeConfig currentTheme;
    private ShellContext shellContext;
    private CompletionFunc[string] completionFuncs;
    private string[string] keyBindings;

    this() {
        shellContext = new ShellContext();
        shellContext.configManager = this;
        initializeConfigPaths();
        initializeDefaultConfig();
        loadConfigFiles();
        loadThemes();
    }

    /// Initialize configuration file search paths
    private void initializeConfigPaths() {
        configPaths = [
            "~/.shrc",
            "~/.sh_profile",
            "~/.sh_theme",
            "/etc/sh/config",
            "~/.config/lfe-sh/config.json"
        ];
    }

    /// Initialize default configuration variables
    private void initializeDefaultConfig() {
        // Shell behavior
        configVars["PS1"] = ConfigVar("lfe-sh> ", "Primary prompt string", "string", true, "lfe-sh> ");
        configVars["PS2"] = ConfigVar("> ", "Secondary prompt string", "string", true, "> ");
        configVars["PS_COLOR"] = ConfigVar("green", "Prompt color", "string", true, "green");
        configVars["HISTSIZE"] = ConfigVar("1000", "History size", "int", true, "1000");
        configVars["HISTFILE"] = ConfigVar("~/.sh_history", "History file location", "path", true, "~/.sh_history");

        // Editor and pager
        configVars["EDITOR"] = ConfigVar("nano", "Default text editor", "string", true, "nano");
        configVars["PAGER"] = ConfigVar("less", "Default pager", "string", true, "less");

        // TUI settings
        configVars["TUI_MODE"] = ConfigVar("auto", "TUI mode (auto/on/off)", "string", true, "auto");
        configVars["TUI_THEME"] = ConfigVar("default", "Default TUI theme", "string", true, "default");
        configVars["TUI_MOUSE"] = ConfigVar("true", "Enable mouse support in TUI", "bool", true, "true");

        // Language settings
        configVars["LFE_MODE"] = ConfigVar("auto", "LFE mode (auto/on/off)", "string", true, "auto");
        configVars["LFE_PROMPT"] = ConfigVar("lfe> ", "LFE prompt string", "string", true, "lfe> ");

        // Networking
        configVars["HTTP_TIMEOUT"] = ConfigVar("30", "HTTP request timeout in seconds", "int", true, "30");
        configVars["MAX_CONNECTIONS"] = ConfigVar("10", "Maximum concurrent connections", "int", true, "10");

        // Performance
        configVars["COMPLETION_DELAY"] = ConfigVar("300", "Completion popup delay in ms", "int", true, "300");
        configVars["TUI_REFRESH_RATE"] = ConfigVar("60", "TUI refresh rate in Hz", "int", true, "60");
    }

    /// Load configuration from all config files
    void loadConfigFiles() {
        foreach(configPath; configPaths) {
            string expandedPath = expandTilde(configPath);
            if (exists(expandedPath)) {
                loadConfigFile(expandedPath);
            }
        }
    }

    /// Load configuration from a single file
    private void loadConfigFile(string filepath) {
        try {
            if (filepath.endsWith(".json")) {
                loadJSONConfig(filepath);
            } else {
                loadShellConfig(filepath);
            }
        } catch (Exception e) {
            writeln("Warning: Failed to load config file ", filepath, ": ", e.msg);
        }
    }

    /// Load JSON configuration format
    private void loadJSONConfig(string filepath) {
        string content = readText(filepath);
        JSONValue json = parseJSON(content);

        if ("variables" in json.object) {
            foreach(string key, JSONValue value; json["variables"].object) {
                if (key in configVars) {
                    configVars[key].value = value.str;
                    configVars[key].userSettable = true;
                }
            }
        }

        if ("keyBindings" in json.object) {
            foreach(string key, JSONValue value; json["keyBindings"].object) {
                keyBindings[key] = value.str;
            }
        }

        if ("theme" in json.object) {
            string themeName = json["theme"].str;
            setTheme(themeName);
        }
    }

    /// Load shell-style configuration format
    private void loadShellConfig(string filepath) {
        string content = readText(filepath);
        foreach(line; content.splitLines()) {
            line = line.strip();
            if (line.length == 0 || line.startsWith("#")) continue;

            // Handle variable assignment: VAR=value
            auto eqPos = line.indexOf('=');
            if (eqPos > 0) {
                string varName = line[0..eqPos].strip();
                string varValue = line[eqPos+1..$].strip();

                // Remove quotes if present
                if (varValue.length >= 2 && (varValue[0] == '"' || varValue[0] == '\'')) {
                    varValue = varValue[1..$-1];
                }

                setConfig(varName, varValue);
            }
            // Handle alias: alias name='command'
            else if (line.startsWith("alias ")) {
                string aliasDef = line[6..$].strip();
                auto spacePos = aliasDef.indexOf('=');
                if (spacePos > 0) {
                    string aliasName = aliasDef[0..spacePos].strip();
                    string aliasValue = aliasDef[spacePos+1..$].strip();

                    // Remove quotes if present
                    if (aliasValue.length >= 2 && (aliasValue[0] == '"' || aliasValue[0] == '\'')) {
                        aliasValue = aliasValue[1..$-1];
                    }

                    shellContext.setAlias(aliasName, aliasValue);
                }
            }
        }
    }

    /// Load available themes
    private void loadThemes() {
        // Create default theme
        ThemeConfig defaultTheme;
        defaultTheme.name = "default";
        defaultTheme.colors = [
            "fg": "white",
            "bg": "black",
            "cursor": "white",
            "selection": "blue",
            "prompt": "green",
            "command": "white",
            "output": "gray",
            "error": "red",
            "warning": "yellow",
            "info": "cyan"
        ];
        defaultTheme.styles = [
            "prompt": "bold",
            "command": "normal",
            "output": "normal",
            "error": "bold",
            "warning": "bold",
            "info": "normal"
        ];
        themes["default"] = defaultTheme;

        // Create dark theme
        ThemeConfig darkTheme = defaultTheme;
        darkTheme.name = "dark";
        darkTheme.colors["bg"] = "#1a1a1a";
        darkTheme.colors["fg"] = "#e0e0e0";
        darkTheme.colors["prompt"] = "#4caf50";
        themes["dark"] = darkTheme;

        // Create light theme
        ThemeConfig lightTheme = defaultTheme;
        lightTheme.name = "light";
        lightTheme.colors["bg"] = "white";
        lightTheme.colors["fg"] = "black";
        lightTheme.colors["prompt"] = "blue";
        themes["light"] = lightTheme;

        // Set initial theme
        string themeName = getConfig("TUI_THEME", "default");
        setTheme(themeName);
    }

    /// Set a configuration variable
    void setConfig(string name, string value) {
        if (name in configVars) {
            configVars[name].value = value;
            configVars[name].userSettable = true;

            // Also set in shell context for immediate use
            shellContext.setVariable(name, value);
        }
    }

    /// Get a configuration variable
    string getConfig(string name, string defaultValue = "") {
        if (name in configVars) {
            return configVars[name].value;
        }
        return defaultValue;
    }

    /// Get integer configuration value
    int getConfigInt(string name, int defaultValue = 0) {
        string value = getConfig(name, to!string(defaultValue));
        try {
            return to!int(value);
        } catch (Exception) {
            return defaultValue;
        }
    }

    /// Get boolean configuration value
    bool getConfigBool(string name, bool defaultValue = false) {
        string value = getConfig(name, defaultValue ? "true" : "false");
        return value == "true" || value == "1" || value == "yes";
    }

    /// Set theme
    void setTheme(string themeName) {
        if (themeName in themes) {
            currentTheme = themes[themeName];
            shellContext.currentTheme = currentTheme;
            setConfig("TUI_THEME", themeName);
        }
    }

    /// Get current theme
    ThemeConfig getCurrentTheme() {
        return currentTheme;
    }

    /// Get all available themes
    string[] getAvailableThemes() {
        return themes.keys.array;
    }

    /// Set key binding
    void setKeyBinding(string key, string action) {
        keyBindings[key] = action;
    }

    /// Get key binding
    string getKeyBinding(string key) {
        return keyBindings.get(key, "");
    }

    /// Register completion function
    void registerCompletion(string command, CompletionFunc func) {
        completionFuncs[command] = func;
    }

    /// Get completion function
    CompletionFunc getCompletion(string command) {
        return completionFuncs.get(command, null);
    }

    /// Get shell context
    ShellContext getShellContext() {
        return shellContext;
    }

    /// Save current configuration to file
    void saveConfig(string filepath) {
        JSONValue json = JSONValue();

        // Save variables
        JSONValue vars = JSONValue();
        foreach(name, configVar; configVars) {
            if (configVar.userSettable) {
                vars[name] = JSONValue(configVar.value);
            }
        }
        json.object["variables"] = vars;

        // Save key bindings
        JSONValue bindings = JSONValue();
        foreach(key, action; keyBindings) {
            bindings[key] = JSONValue(action);
        }
        json.object["keyBindings"] = bindings;

        // Save theme
        json.object["theme"] = JSONValue(currentTheme.name);

        // Write to file
        string expandedPath = expandTilde(filepath);
        ensurePathExists(dirName(expandedPath));
        std.file.write(expandedPath, json.toPrettyString());
    }

    /// Get all configuration variables with descriptions
    ConfigVar[string] getAllConfigVars() {
        return configVars;
    }

    /// Expand tilde to home directory
    private string expandTilde(string path) {
        if (path.startsWith("~/")) {
            string homeDir = environment.get("HOME", "");
            return homeDir ~ path[1..$];
        }
        return path;
    }
}
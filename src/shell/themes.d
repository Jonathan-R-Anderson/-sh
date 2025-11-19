module shell.themes;

import std.stdio;
import std.string;
import std.file;
import std.json;
import std.path;
import std.array;
import std.algorithm;
import shell.config;

/// Color definition for terminal colors
struct Color {
    string name;
    string rgb; // "#RRGGBB" format
    string ansi; // ANSI escape code
    bool bright;

    this(string name, string rgb, string ansi, bool bright = false) {
        this.name = name;
        this.rgb = rgb;
        this.ansi = ansi;
        this.bright = bright;
    }
}

/// Text style definition
struct Style {
    string name;
    bool bold;
    bool dim;
    bool italic;
    bool underline;
    bool blink;
    bool reverse;

    string toAnsi() const {
        string[] codes;
        if (bold) codes ~= "1";
        if (dim) codes ~= "2";
        if (italic) codes ~= "3";
        if (underline) codes ~= "4";
        if (blink) codes ~= "5";
        if (reverse) codes ~= "7";

        if (codes.length == 0) return "";
        return "\033[" ~ codes.join(";") ~ "m";
    }
}

/// Complete theme definition
class Theme {
    string name;
    string description;
    Color[string] colors;
    Style[string] styles;
    string background;
    string foreground;

    this(string name, string description = "") {
        this.name = name;
        this.description = description;
        initializeDefaultColors();
        initializeDefaultStyles();
    }

    /// Initialize default color palette
    private void initializeDefaultColors() {
        // Basic 16-color palette
        colors["black"] = Color("black", "#000000", "\033[30m");
        colors["red"] = Color("red", "#ff0000", "\033[31m");
        colors["green"] = Color("green", "#00ff00", "\033[32m");
        colors["yellow"] = Color("yellow", "#ffff00", "\033[33m");
        colors["blue"] = Color("blue", "#0000ff", "\033[34m");
        colors["magenta"] = Color("magenta", "#ff00ff", "\033[35m");
        colors["cyan"] = Color("cyan", "#00ffff", "\033[36m");
        colors["white"] = Color("white", "#ffffff", "\033[37m");
        colors["gray"] = Color("gray", "#808080", "\033[90m");

        // Bright variants
        colors["bright-black"] = Color("bright-black", "#808080", "\033[90m", true);
        colors["bright-red"] = Color("bright-red", "#ff8080", "\033[91m", true);
        colors["bright-green"] = Color("bright-green", "#80ff80", "\033[92m", true);
        colors["bright-yellow"] = Color("bright-yellow", "#ffff80", "\033[93m", true);
        colors["bright-blue"] = Color("bright-blue", "#8080ff", "\033[94m", true);
        colors["bright-magenta"] = Color("bright-magenta", "#ff80ff", "\033[95m", true);
        colors["bright-cyan"] = Color("bright-cyan", "#80ffff", "\033[96m", true);
        colors["bright-white"] = Color("bright-white", "#ffffff", "\033[97m", true);

        // Semantic colors (can be overridden)
        colors["background"] = Color("background", "#000000", "\033[40m");
        colors["foreground"] = Color("foreground", "#ffffff", "\033[97m");
        colors["cursor"] = Color("cursor", "#ffffff", "\033[97m");
        colors["selection"] = Color("selection", "#000080", "\033[44m");
        colors["prompt"] = Color("prompt", "#00ff00", "\033[32m");
        colors["command"] = Color("command", "#ffffff", "\033[97m");
        colors["output"] = Color("output", "#cccccc", "\033[37m");
        colors["error"] = Color("error", "#ff0000", "\033[31m");
        colors["warning"] = Color("warning", "#ffff00", "\033[33m");
        colors["info"] = Color("info", "#00ffff", "\033[36m");
        colors["success"] = Color("success", "#00ff00", "\033[32m");
        colors["highlight"] = Color("highlight", "#ffff00", "\033[43m");
    }

    /// Initialize default styles
    private void initializeDefaultStyles() {
        styles["normal"] = Style("normal");
        styles["bold"] = Style("bold", true);
        styles["dim"] = Style("dim", false, true);
        styles["italic"] = Style("italic", false, false, true);
        styles["underline"] = Style("underline", false, false, false, false, false, false, true);
        styles["blink"] = Style("blink", false, false, false, false, true);
        styles["reverse"] = Style("reverse", false, false, false, false, false, false, false, true);
        styles["prompt"] = Style("prompt", true);
        styles["error"] = Style("error", true);
        styles["warning"] = Style("warning", true);
        styles["success"] = Style("success", true);
        styles["info"] = Style("info");
        styles["header"] = Style("header", true, false, false, true);
        styles["keyword"] = Style("keyword", true);
        styles["comment"] = Style("comment", false, true);
        styles["string"] = Style("string", false, false, false, false, false, false, false, true);
    }

    /// Set a custom color
    void setColor(string name, string rgb) {
        colors[name] = Color(name, rgb, convertRgbToAnsi(rgb));
    }

    /// Set a custom style
    void setStyle(string name, bool bold = false, bool dim = false, bool italic = false,
                  bool underline = false, bool blink = false, bool reverse = false) {
        styles[name] = Style(name, bold, dim, italic, underline, blink, reverse);
    }

    /// Get color by name
    Color getColor(string name) {
        if (name in colors) {
            return colors[name];
        }
        return colors["white"]; // fallback
    }

    /// Get style by name
    Style getStyle(string name) {
        if (name in styles) {
            return styles[name];
        }
        return styles["normal"]; // fallback
    }

    /// Format text with color and style
    string formatText(string text, string colorName, string styleName = "normal") {
        Color color = getColor(colorName);
        Style style = getStyle(styleName);
        string resetCode = "\033[0m";

        return color.ansi ~ style.toAnsi() ~ text ~ resetCode;
    }

    /// Format text with RGB color
    string formatTextRGB(string text, string rgb, string styleName = "normal") {
        string ansiCode = "\033[38;2;" ~ convertRgbToAnsiParams(rgb) ~ "m";
        Style style = getStyle(styleName);
        string resetCode = "\033[0m";

        return ansiCode ~ style.toAnsi() ~ text ~ resetCode;
    }

    /// Convert RGB hex to ANSI parameters
    private string convertRgbToAnsiParams(string rgb) {
        if (rgb.length != 7 || rgb[0] != '#') return "255;255;255";

        try {
            int r = parse!int(rgb[1..3], 16);
            int g = parse!int(rgb[3..5], 16);
            int b = parse!int(rgb[5..7], 16);
            return to!string(r) ~ ";" ~ to!string(g) ~ ";" ~ to!string(b);
        } catch (Exception) {
            return "255;255;255";
        }
    }

    /// Convert RGB hex to basic ANSI color code
    private string convertRgbToAnsi(string rgb) {
        // Simplified conversion - map to nearest 16-color
        if (rgb == "#000000") return "\033[30m";      // black
        if (rgb == "#ff0000") return "\033[31m";      // red
        if (rgb == "#00ff00") return "\033[32m";      // green
        if (rgb == "#ffff00") return "\033[33m";      // yellow
        if (rgb == "#0000ff") return "\033[34m";      // blue
        if (rgb == "#ff00ff") return "\033[35m";      // magenta
        if (rgb == "#00ffff") return "\033[36m";      // cyan
        if (rgb == "#ffffff") return "\033[37m";      // white

        return "\033[37m"; // default to white
    }

    /// Save theme to JSON file
    void save(string filepath) {
        JSONValue json = JSONValue();
        json.object["name"] = JSONValue(name);
        json.object["description"] = JSONValue(description);

        // Save colors
        JSONValue colorsJson = JSONValue();
        foreach(name, color; colors) {
            JSONValue colorJson = JSONValue();
            colorJson.object["rgb"] = JSONValue(color.rgb);
            colorJson.object["bright"] = JSONValue(color.bright);
            colorsJson[name] = colorJson;
        }
        json.object["colors"] = colorsJson;

        // Save styles
        JSONValue stylesJson = JSONValue();
        foreach(name, style; styles) {
            JSONValue styleJson = JSONValue();
            styleJson.object["bold"] = JSONValue(style.bold);
            styleJson.object["dim"] = JSONValue(style.dim);
            styleJson.object["italic"] = JSONValue(style.italic);
            styleJson.object["underline"] = JSONValue(style.underline);
            styleJson.object["blink"] = JSONValue(style.blink);
            styleJson.object["reverse"] = JSONValue(style.reverse);
            stylesJson[name] = styleJson;
        }
        json.object["styles"] = stylesJson;

        // Write file
        string expandedPath = expandTilde(filepath);
        ensurePathExists(dirName(expandedPath));
        std.file.write(expandedPath, json.toPrettyString());
    }

    /// Load theme from JSON file
    static Theme load(string filepath) {
        string expandedPath = expandTilde(filepath);
        if (!exists(expandedPath)) {
            throw new Exception("Theme file not found: " ~ filepath);
        }

        string content = readText(expandedPath);
        JSONValue json = parseJSON(content);

        Theme theme = new Theme(
            json["name"].str,
            json.object.get("description", JSONValue("")).str
        );

        // Load colors
        if ("colors" in json.object) {
            foreach(name, colorValue; json["colors"].object) {
                string rgb = colorValue.object["rgb"].str;
                theme.setColor(name, rgb);
            }
        }

        // Load styles
        if ("styles" in json.object) {
            foreach(name, styleValue; json["styles"].object) {
                bool bold = styleValue.object.get("bold", JSONValue(false)).bool_;
                bool dim = styleValue.object.get("dim", JSONValue(false)).bool_;
                bool italic = styleValue.object.get("italic", JSONValue(false)).bool_;
                bool underline = styleValue.object.get("underline", JSONValue(false)).bool_;
                bool blink = styleValue.object.get("blink", JSONValue(false)).bool_;
                bool reverse = styleValue.object.get("reverse", JSONValue(false)).bool_;

                theme.setStyle(name, bold, dim, italic, underline, blink, reverse);
            }
        }

        return theme;
    }

    /// Generate CSS-like theme preview
    string generatePreview() {
        string preview = "Theme: " ~ name ~ "\n";
        preview ~= "Description: " ~ description ~ "\n\n";

        preview ~= "Colors:\n";
        foreach(name, color; colors) {
            if (!name.startsWith("bright-")) {
                preview ~= "  " ~ name ~ ": ";
                preview ~= color.ansi ~ "████" ~ "\033[0m (" ~ color.rgb ~ ")\n";
            }
        }

        preview ~= "\nStyles:\n";
        foreach(name, style; styles) {
            preview ~= "  " ~ name ~ ": ";
            string sample = formatText("Sample text", "foreground", name);
            preview ~= sample ~ "\n";
        }

        return preview;
    }
}

/// Theme manager
class ThemeManager {
    private Theme[string] themes;
    private Theme currentTheme;
    private ConfigManager configManager;

    this(ConfigManager configManager) {
        this.configManager = configManager;
        loadBuiltinThemes();
        loadUserThemes();
    }

    /// Load built-in themes
    private void loadBuiltinThemes() {
        // Default theme
        Theme defaultTheme = new Theme("default", "Default light theme");
        defaultTheme.setColor("background", "#ffffff");
        defaultTheme.setColor("foreground", "#000000");
        defaultTheme.setColor("prompt", "#0000ff");
        themes["default"] = defaultTheme;

        // Dark theme
        Theme darkTheme = new Theme("dark", "Dark theme for low-light environments");
        darkTheme.setColor("background", "#1a1a1a");
        darkTheme.setColor("foreground", "#e0e0e0");
        darkTheme.setColor("prompt", "#4caf50");
        darkTheme.setColor("command", "#ffffff");
        darkTheme.setColor("output", "#cccccc");
        darkTheme.setColor("error", "#ff5252");
        darkTheme.setColor("warning", "#ffeb3b");
        darkTheme.setColor("info", "#03a9f4");
        themes["dark"] = darkTheme;

        // Solarized theme
        Theme solarizedTheme = new Theme("solarized", "Solarized color palette");
        solarizedTheme.setColor("background", "#002b36");
        solarizedTheme.setColor("foreground", "#839496");
        solarizedTheme.setColor("prompt", "#268bd2");
        solarizedTheme.setColor("command", "#93a1a1");
        solarizedTheme.setColor("error", "#dc322f");
        solarizedTheme.setColor("warning", "#b58900");
        solarizedTheme.setColor("info", "#2aa198");
        solarizedTheme.setColor("success", "#859900");
        themes["solarized"] = solarizedTheme;

        // Set initial theme
        string themeName = configManager.getConfig("TUI_THEME", "default");
        setTheme(themeName);
    }

    /// Load user themes from config directory
    private void loadUserThemes() {
        string[] themeDirs = [
            "~/.config/lfe-sh/themes/",
            "/etc/lfe-sh/themes/",
            "./themes/"
        ];

        foreach(themeDir; themeDirs) {
            string expandedDir = expandTilde(themeDir);
            if (exists(expandedDir)) {
                foreach(string file; dirEntries(expandedDir, "*.json", SpanMode.depth)) {
                    try {
                        Theme theme = Theme.load(file);
                        themes[theme.name] = theme;
                    } catch (Exception e) {
                        writeln("Warning: Failed to load theme ", file, ": ", e.msg);
                    }
                }
            }
        }
    }

    /// Set current theme
    void setTheme(string name) {
        if (name in themes) {
            currentTheme = themes[name];
            configManager.setTheme(name);
        } else {
            writeln("Warning: Theme '", name, "' not found, using default");
            if ("default" in themes) {
                currentTheme = themes["default"];
            }
        }
    }

    /// Get current theme
    Theme getCurrentTheme() {
        return currentTheme;
    }

    /// Get all available theme names
    string[] getAvailableThemes() {
        return themes.keys.array;
    }

    /// Get theme by name
    Theme getTheme(string name) {
        return themes.get(name, null);
    }

    /// Register a new theme
    void registerTheme(Theme theme) {
        themes[theme.name] = theme;
    }

    /// Create and register a new theme
    Theme createTheme(string name, string description, string baseTheme = "default") {
        Theme newTheme = new Theme(name, description);

        // Copy colors from base theme
        if (baseTheme in themes) {
            Theme base = themes[baseTheme];
            foreach(colorName, color; base.colors) {
                newTheme.colors[colorName] = color;
            }
            foreach(styleName, style; base.styles) {
                newTheme.styles[styleName] style;
            }
        }

        themes[name] = newTheme;
        return newTheme;
    }

    /// List all themes with descriptions
    void listThemes() {
        writeln("Available themes:");
        foreach(name, theme; themes) {
            string marker = (currentTheme.name == name) ? " [current]" : "";
            writeln("  " ~ name ~ marker ~ " - " ~ theme.description);
        }
    }

    /// Show theme preview
    void previewTheme(string name) {
        if (name in themes) {
            writeln(themes[name].generatePreview());
        } else {
            writeln("Theme '" ~ name ~ "' not found");
        }
    }
}
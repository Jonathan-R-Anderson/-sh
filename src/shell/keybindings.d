module shell.keybindings;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.json;
import shell.config;

/// Key event definition
struct KeyEvent {
    string key; // Key name (e.g., "ctrl-c", "f1", "up", "enter")
    bool ctrl;
    bool alt;
    bool shift;
    string char_; // Single character if applicable
}

/// Key action definition
struct KeyAction {
    string name;
    string description;
    string command;
    bool builtin;
    bool contextSensitive; // Only works in specific contexts
}

/// Key binding context
enum KeyContext {
    GLOBAL,    // Works everywhere
    COMMAND,   // Works during command entry
    TUI,       // Works in TUI mode
    EDITOR,    // Works in text editor
    BROWSER    // Works in file browser
}

/// Key binding
struct KeyBinding {
    KeyEvent keyEvent;
    KeyAction action;
    KeyContext context;
    int priority;
}

/// Key binding manager
class KeyBindingManager {
    private KeyBinding[] bindings;
    private string[string] keyDescriptions;
    private ConfigManager configManager;

    this(ConfigManager configManager) {
        this.configManager = configManager;
        initializeDefaultBindings();
        initializeKeyDescriptions();
        loadCustomBindings();
    }

    /// Initialize default key bindings
    private void initializeDefaultBindings() {
        // Emacs-style bindings (default)
        addBinding(KeyEvent("ctrl-a", true, false, false), KeyAction("beginning-of-line", "Move to beginning of line", "", true), KeyContext.GLOBAL);
        addBinding(KeyEvent("ctrl-e", true, false, false), KeyAction("end-of-line", "Move to end of line", "", true), KeyContext.GLOBAL);
        addBinding(KeyEvent("ctrl-f", true, false, false), KeyAction("forward-char", "Move forward one character", "", true), KeyContext.GLOBAL);
        addBinding(KeyEvent("ctrl-b", true, false, false), KeyAction("backward-char", "Move backward one character", "", true), KeyContext.GLOBAL);
        addBinding(KeyEvent("ctrl-p", true, false, false), KeyAction("previous-history", "Previous command in history", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-n", true, false, false), KeyAction("next-history", "Next command in history", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-r", true, false, false), KeyAction("reverse-search-history", "Search history backward", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-s", true, false, false), KeyAction("forward-search-history", "Search history forward", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-u", true, false, false), KeyAction("unix-line-discard", "Delete from cursor to beginning", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-k", true, false, false), KeyAction("kill-line", "Delete from cursor to end", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-w", true, false, false), KeyAction("unix-word-rubout", "Delete previous word", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-d", true, false, false), KeyAction("delete-char", "Delete character at cursor", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-h", true, false, false), KeyAction("backward-delete-char", "Delete previous character", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-l", true, false, false), KeyAction("clear-screen", "Clear screen", "", true), KeyContext.GLOBAL);
        addBinding(KeyEvent("ctrl-c", true, false, false), KeyAction("interrupt", "Send interrupt signal", "", true), KeyContext.GLOBAL);
        addBinding(KeyEvent("ctrl-z", true, false, false), KeyAction("suspend", "Suspend current process", "", true), KeyContext.GLOBAL);
        addBinding(KeyEvent("ctrl-t", true, false, false), KeyAction("transpose-chars", "Transpose characters", "", true), KeyContext.COMMAND);

        // Arrow keys
        addBinding(KeyEvent("up", false, false, false), KeyAction("previous-history", "Previous command in history", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("down", false, false, false), KeyAction("next-history", "Next command in history", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("left", false, false, false), KeyAction("backward-char", "Move backward one character", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("right", false, false, false), KeyAction("forward-char", "Move forward one character", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("home", false, false, false), KeyAction("beginning-of-line", "Move to beginning of line", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("end", false, false, false), KeyAction("end-of-line", "Move to end of line", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("delete", false, false, false), KeyAction("delete-char", "Delete character at cursor", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("backspace", false, false, false), KeyAction("backward-delete-char", "Delete previous character", "", true), KeyContext.COMMAND);

        // Function keys
        addBinding(KeyEvent("f1", false, false, false), KeyAction("help", "Show help", "help", false), KeyContext.GLOBAL);
        addBinding(KeyEvent("f2", false, false, false), KeyAction("tui-toggle", "Toggle TUI mode", "tui", false), KeyContext.GLOBAL);
        addBinding(KeyEvent("f3", false, false, false), KeyAction("file-explorer", "Toggle file explorer", "", true), KeyContext.TUI);
        addBinding(KeyEvent("f4", false, false, false), KeyAction("process-manager", "Toggle process manager", "", true), KeyContext.TUI);
        addBinding(KeyEvent("f5", false, false, false), KeyAction("refresh", "Refresh current view", "", true), KeyContext.TUI);
        addBinding(KeyEvent("f7", false, false, false), KeyAction("history", "Show command history", "history", false), KeyContext.GLOBAL);
        addBinding(KeyEvent("f10", false, false, false), KeyAction("menu", "Open menu", "", true), KeyContext.TUI);
        addBinding(KeyEvent("f12", false, false, false), KeyAction("settings", "Open settings", "", true), KeyContext.TUI);

        // Tab completion
        addBinding(KeyEvent("tab", false, false, false), KeyAction("complete", "Complete command/file", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("shift-tab", false, false, true), KeyAction("complete-backward", "Complete backward", "", true), KeyContext.COMMAND);

        // Escape sequences
        addBinding(KeyEvent("escape", false, false, false), KeyAction("cancel", "Cancel current operation", "", true), KeyContext.GLOBAL);
        addBinding(KeyEvent("ctrl-[", true, false, false), KeyAction("cancel", "Cancel current operation", "", true), KeyContext.GLOBAL);

        // Enter key
        addBinding(KeyEvent("enter", false, false, false), KeyAction("accept-line", "Execute command", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-m", true, false, false), KeyAction("accept-line", "Execute command", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("ctrl-j", true, false, false), KeyAction("accept-line", "Execute command", "", true), KeyContext.COMMAND);

        // TUI-specific bindings
        addBinding(KeyEvent("ctrl-q", true, false, false), KeyAction("tui-exit", "Exit TUI mode", "", true), KeyContext.TUI);
        addBinding(KeyEvent("ctrl-x", true, false, false), KeyAction("tui-exit", "Exit TUI mode", "", true), KeyContext.TUI);
        addBinding(KeyEvent("ctrl-o", true, false, false), KeyAction("tui-split", "Split window", "", true), KeyContext.TUI);
        addBinding(KeyEvent("ctrl-g", true, false, false), KeyAction("tui-goto-line", "Go to line", "", true), KeyContext.TUI);
        addBinding(KeyEvent("ctrl-s", true, false, false), KeyAction("tui-search", "Search in current buffer", "", true), KeyContext.TUI);

        // Vi-style bindings (optional)
        addBinding(KeyEvent("escape", false, false, false), KeyAction("vi-mode", "Enter vi mode", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("h", false, false, false), KeyAction("vi-left", "Vi left movement", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("j", false, false, false), KeyAction("vi-down", "Vi down movement", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("k", false, false, false), KeyAction("vi-up", "Vi up movement", "", true), KeyContext.COMMAND);
        addBinding(KeyEvent("l", false, false, false), KeyAction("vi-right", "Vi right movement", "", true), KeyContext.COMMAND);
    }

    /// Initialize key descriptions
    private void initializeKeyDescriptions() {
        keyDescriptions = [
            "ctrl-a": "Ctrl + A",
            "ctrl-b": "Ctrl + B",
            "ctrl-c": "Ctrl + C",
            "ctrl-d": "Ctrl + D",
            "ctrl-e": "Ctrl + E",
            "ctrl-f": "Ctrl + F",
            "ctrl-g": "Ctrl + G",
            "ctrl-h": "Ctrl + H",
            "ctrl-j": "Ctrl + J",
            "ctrl-k": "Ctrl + K",
            "ctrl-l": "Ctrl + L",
            "ctrl-m": "Ctrl + M",
            "ctrl-n": "Ctrl + N",
            "ctrl-o": "Ctrl + O",
            "ctrl-p": "Ctrl + P",
            "ctrl-q": "Ctrl + Q",
            "ctrl-r": "Ctrl + R",
            "ctrl-s": "Ctrl + S",
            "ctrl-t": "Ctrl + T",
            "ctrl-u": "Ctrl + U",
            "ctrl-w": "Ctrl + W",
            "ctrl-x": "Ctrl + X",
            "ctrl-z": "Ctrl + Z",
            "tab": "Tab",
            "shift-tab": "Shift + Tab",
            "enter": "Enter",
            "escape": "Escape",
            "space": "Space",
            "backspace": "Backspace",
            "delete": "Delete",
            "home": "Home",
            "end": "End",
            "pageup": "Page Up",
            "pagedown": "Page Down",
            "up": "Up Arrow",
            "down": "Down Arrow",
            "left": "Left Arrow",
            "right": "Right Arrow"
        ];
    }

    /// Load custom key bindings from configuration
    private void loadCustomBindings() {
        // Load from config file
        string configKeyBindings = configManager.getConfig("KEY_BINDINGS", "");
        if (configKeyBindings.length > 0) {
            try {
                JSONValue json = parseJSON(configKeyBindings);
                foreach(string key, string action; json.object) {
                    KeyEvent event = parseKeyEvent(key);
                    KeyAction keyAction = KeyAction("custom", action, action, false);
                    addBinding(event, keyAction, KeyContext.GLOBAL);
                }
            } catch (Exception e) {
                writeln("Warning: Failed to parse key bindings from config: ", e.msg);
            }
        }
    }

    /// Add a key binding
    void addBinding(KeyEvent keyEvent, KeyAction action, KeyContext context, int priority = 100) {
        KeyBinding binding;
        binding.keyEvent = keyEvent;
        binding.action = action;
        binding.context = context;
        binding.priority = priority;

        // Remove existing binding for same key in same context
        bindings = bindings.filter!(b =>
            !(b.keyEvent.key == keyEvent.key &&
              b.keyEvent.ctrl == keyEvent.ctrl &&
              b.keyEvent.alt == keyEvent.alt &&
              b.keyEvent.shift == keyEvent.shift &&
              b.context == context)
        ).array;

        bindings ~= binding;

        // Sort by priority
        bindings = bindings.sort!((a, b) => a.priority > b.priority);
    }

    /// Find binding for key event in given context
    KeyBinding* findBinding(KeyEvent keyEvent, KeyContext context) {
        // First try exact context match
        foreach(ref binding; bindings) {
            if (binding.context == context &&
                binding.keyEvent.key == keyEvent.key &&
                binding.keyEvent.ctrl == keyEvent.ctrl &&
                binding.keyEvent.alt == keyEvent.alt &&
                binding.keyEvent.shift == keyEvent.shift) {
                return &binding;
            }
        }

        // Then try global context
        if (context != KeyContext.GLOBAL) {
            foreach(ref binding; bindings) {
                if (binding.context == KeyContext.GLOBAL &&
                    binding.keyEvent.key == keyEvent.key &&
                    binding.keyEvent.ctrl == keyEvent.ctrl &&
                    binding.keyEvent.alt == keyEvent.alt &&
                    binding.keyEvent.shift == keyEvent.shift) {
                    return &binding;
                }
            }
        }

        return null;
    }

    /// Parse key event from string
    KeyEvent parseKeyEvent(string keyString) {
        KeyEvent event;
        string lowerKey = keyString.toLower();

        // Extract modifiers
        event.ctrl = lowerKey.startsWith("ctrl-");
        if (event.ctrl) lowerKey = lowerKey[5..$];

        event.alt = lowerKey.startsWith("alt-");
        if (event.alt) lowerKey = lowerKey[4..$];

        event.shift = lowerKey.startsWith("shift-");
        if (event.shift) lowerKey = lowerKey[6..$];

        // Extract key
        if (lowerKey.length == 1) {
            event.key = lowerKey;
            event.char_ = lowerKey;
        } else {
            event.key = lowerKey;
            event.char_ = "";
        }

        return event;
    }

    /// Convert key event to string
    string keyEventToString(KeyEvent event) {
        string result;
        if (event.ctrl) result ~= "ctrl-";
        if (event.alt) result ~= "alt-";
        if (event.shift) result ~= "shift-";
        result ~= event.key;
        return result;
    }

    /// Get human-readable key description
    string getKeyEventDescription(KeyEvent event) {
        string description = keyDescriptions.get(event.key, event.key);
        if (event.ctrl) description = "Ctrl + " ~ description;
        if (event.alt) description = "Alt + " ~ description;
        if (event.shift) description = "Shift + " ~ description;
        return description;
    }

    /// List all key bindings
    void listKeyBindings(KeyContext context = KeyContext.GLOBAL) {
        writeln("Key Bindings for context: ", context);
        writeln("=".repeat(50));

        KeyBinding[] contextBindings = bindings.filter!(b => b.context == context).array;

        foreach(binding; contextBindings) {
            string keyDesc = getKeyEventDescription(binding.keyEvent);
            writefln("%-20s | %-25s | %s",
                keyDesc,
                binding.action.name,
                binding.action.description
            );
        }
    }

    /// Export key bindings to JSON
    string exportKeyBindings() {
        JSONValue json = JSONValue();

        foreach(binding; bindings) {
            string key = keyEventToString(binding.keyEvent);
            json.object[key] = JSONValue(binding.action.command.length > 0 ?
                binding.action.command : binding.action.name);
        }

        return json.toPrettyString();
    }

    /// Import key bindings from JSON
    void importKeyBindings(string jsonStr) {
        try {
            JSONValue json = parseJSON(jsonStr);
            foreach(string key, JSONValue value; json.object) {
                KeyEvent event = parseKeyEvent(key);
                KeyAction action = KeyAction("imported", value.str, value.str, false);
                addBinding(event, action, KeyContext.GLOBAL);
            }
        } catch (Exception e) {
            writeln("Error importing key bindings: ", e.msg);
        }
    }

    /// Create Emacs-style key bindings
    void createEmacsBindings() {
        // Clear existing bindings
        bindings.length = 0;

        // Add Emacs bindings
        initializeDefaultBindings();

        // Additional Emacs-specific bindings
        addBinding(KeyEvent("x", false, true, false), KeyAction("kill-region", "Cut region", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("c", false, true, false), KeyAction("copy-region", "Copy region", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("v", false, true, false), KeyAction("yank", "Paste", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("y", false, true, false), KeyAction("yank-pop", "Paste from kill ring", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent(" ", false, true, false), KeyAction("set-mark-command", "Set mark", "", true), KeyContext.EDITOR);
    }

    /// Create Vi-style key bindings
    void createViBindings() {
        // Clear existing bindings
        bindings.length = 0;

        // Add Vi command mode bindings
        addBinding(KeyEvent("h", false, false, false), KeyAction("vi-left", "Move left", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("j", false, false, false), KeyAction("vi-down", "Move down", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("k", false, false, false), KeyAction("vi-up", "Move up", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("l", false, false, false), KeyAction("vi-right", "Move right", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("w", false, false, false), KeyAction("vi-word", "Next word", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("b", false, false, false), KeyAction("vi-backward-word", "Previous word", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("0", false, false, false), KeyAction("vi-beginning-line", "Beginning of line", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("$", false, false, false), KeyAction("vi-end-line", "End of line", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("i", false, false, false), KeyAction("vi-insert-mode", "Enter insert mode", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("a", false, false, false), KeyAction("vi-append-mode", "Append mode", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("d", false, false, false), KeyAction("vi-delete", "Delete", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("y", false, false, false), KeyAction("vi-yank", "Yank/copy", "", true), KeyContext.EDITOR);
        addBinding(KeyEvent("p", false, false, false), KeyAction("vi-put", "Put/paste", "", true), KeyContext.EDITOR);
    }

    /// Get available key binding schemes
    string[] getAvailableSchemes() {
        return ["emacs", "vi", "default"];
    }

    /// Switch to key binding scheme
    void switchScheme(string schemeName) {
        switch (schemeName.toLower()) {
            case "emacs":
                createEmacsBindings();
                break;
            case "vi":
                createViBindings();
                break;
            case "default":
            default:
                bindings.length = 0;
                initializeDefaultBindings();
                break;
        }
    }
}
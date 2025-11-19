module shell.completion;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.path;
import std.file;
import std.regex;
import core.stdc.stdlib;
import shell.config;
import shell.executor;

/// Completion result with metadata
struct CompletionResult {
    string text;
    string description;
    string type; // "command", "file", "directory", "variable", "alias"
    int priority; // Higher priority = earlier in list
}

/// Completion context
struct CompletionContext {
    string input;
    string prefix;
    int cursorPosition;
    string[] commandLine;
    string currentCommand;
    bool inQuotes;
    char quoteChar;
}

/// Completion engine
class CompletionEngine {
    private ConfigManager configManager;
    private string[string] commandDescriptions;
    private string[string][string] customCompletions;

    this(ConfigManager configManager) {
        this.configManager = configManager;
        initializeBuiltinCommands();
        loadCustomCompletions();
    }

    /// Initialize built-in command descriptions
    private void initializeBuiltinCommands() {
        commandDescriptions = [
            "cd": "Change directory",
            "ls": "List directory contents",
            "pwd": "Print working directory",
            "echo": "Display message",
            "cat": "Display file contents",
            "grep": "Search text patterns",
            "find": "Search for files",
            "ps": "Process status",
            "kill": "Terminate processes",
            "mkdir": "Create directory",
            "rm": "Remove files/directories",
            "cp": "Copy files",
            "mv": "Move/rename files",
            "chmod": "Change file permissions",
            "chown": "Change file owner",
            "tar": "Archive utility",
            "gzip": "Compress files",
            "alias": "Create command alias",
            "unalias": "Remove command alias",
            "export": "Set environment variable",
            "history": "Command history",
            "jobs": "List background jobs",
            "bg": "Background job",
            "fg": "Foreground job",
            "tui": "Enter TUI mode",
            "help": "Show help",
            "exit": "Exit shell"
        ];
    }

    /// Load custom completions from configuration
    private void loadCustomCompletions() {
        // This could be loaded from config files
        // For now, add some examples
        customCompletions["git"] = [
            "status", "add", "commit", "push", "pull", "branch", "checkout",
            "merge", "rebase", "log", "diff", "show", "stash", "clone"
        ];
        customCompletions["docker"] = [
            "run", "build", "ps", "images", "rm", "rmi", "exec", "logs",
            "stop", "start", "restart", "pull", "push", "compose"
        ];
        customCompletions["npm"] = [
            "install", "run", "start", "test", "build", "publish", "update"
        ];
        customCompletions["python"] = [
            "-m", "-c", "--version", "--help", "-v", "-h"
        ];
    }

    /// Generate completions for given input
    CompletionResult[] generateCompletions(string input, int cursorPos = -1) {
        if (cursorPos == -1) cursorPos = cast(int)input.length;

        CompletionContext context = parseCompletionContext(input, cursorPos);

        CompletionResult[] results;

        // Command completion (first word)
        if (context.commandLine.length <= 1) {
            results ~= completeCommands(context.prefix);
            results ~= completeAliases(context.prefix);
            results ~= completeFunctions(context.prefix);
        }
        // Argument completion
        else {
            results ~= completeArguments(context);
        }

        // Sort by priority and text
        results = results.sort!((a, b) => a.priority != b.priority ? a.priority > b.priority : a.text < b.text);

        // Limit results
        int maxResults = configManager.getConfigInt("MAX_COMPLETION_RESULTS", 100);
        if (results.length > maxResults) {
            results = results[0..maxResults];
        }

        return results;
    }

    /// Parse completion context from input
    private CompletionContext parseCompletionContext(string input, int cursorPos) {
        CompletionContext context;
        context.input = input;
        context.cursorPosition = cursorPos;

        // Extract text before cursor
        string beforeCursor = input[0..cursorPos];

        // Parse command line
        context.commandLine = parseCommandLine(beforeCursor);
        context.currentCommand = context.commandLine.length > 0 ? context.commandLine[0] : "";

        // Find current prefix to complete
        context.prefix = extractCurrentPrefix(beforeCursor);

        // Check if in quotes
        context.inQuotes = false;
        context.quoteChar = '\0';
        foreach_reverse(i, char c; beforeCursor) {
            if (c == '"' || c == '\'') {
                context.inQuotes = !context.inQuotes;
                context.quoteChar = c;
            }
        }

        return context;
    }

    /// Parse command line into words
    private string[] parseCommandLine(string line) {
        string[] words;
        string current;
        bool inQuotes = false;
        char quoteChar;

        for (size_t i = 0; i < line.length; i++) {
            char c = line[i];

            if (c == '"' || c == '\'') {
                if (!inQuotes) {
                    inQuotes = true;
                    quoteChar = c;
                } else if (c == quoteChar) {
                    inQuotes = false;
                } else {
                    current ~= c;
                }
            } else if (!inQuotes && (c == ' ' || c == '\t')) {
                if (current.length > 0) {
                    words ~= current;
                    current = "";
                }
            } else {
                current ~= c;
            }
        }

        if (current.length > 0) {
            words ~= current;
        }

        return words;
    }

    /// Extract current word prefix to complete
    private string extractCurrentPrefix(string line) {
        string prefix;
        bool inQuotes = false;
        char quoteChar;

        foreach_reverse(i, char c; line) {
            if (c == '"' || c == '\'') {
                if (!inQuotes) {
                    inQuotes = true;
                    quoteChar = c;
                } else if (c == quoteChar) {
                    inQuotes = false;
                }
            } else if (!inQuotes && (c == ' ' || c == '\t' || c == '|' || c == '>' || c == '<')) {
                break;
            } else {
                prefix = c ~ prefix;
            }
        }

        return prefix;
    }

    /// Complete commands
    private CompletionResult[] completeCommands(string prefix) {
        CompletionResult[] results;

        // Built-in commands
        foreach(command; commandDescriptions.keys) {
            if (command.startsWith(prefix)) {
                results ~= CompletionResult(
                    command,
                    commandDescriptions[command],
                    "command",
                    100
                );
            }
        }

        // Commands in PATH
        string[] pathDirs = getEnvironmentVariable("PATH").split(":");
        foreach(pathDir; pathDirs) {
            if (exists(pathDir) && isDir(pathDir)) {
                try {
                    foreach(string file; dirEntries(pathDir, SpanMode.shallow)) {
                        if (isFile(file) && hasExecute(file)) {
                            string command = baseName(file);
                            if (command.startsWith(prefix) && !(command in commandDescriptions)) {
                                results ~= CompletionResult(
                                    command,
                                    "External command",
                                    "command",
                                    80
                                );
                            }
                        }
                    }
                } catch (Exception e) {
                    // Skip directories we can't read
                }
            }
        }

        return results;
    }

    /// Complete aliases
    private CompletionResult[] completeAliases(string prefix) {
        CompletionResult[] results;
        ShellContext shellContext = configManager.getShellContext();

        foreach(aliasName, aliasCommand; shellContext.aliases) {
            if (aliasName.startsWith(prefix)) {
                results ~= CompletionResult(
                    aliasName,
                    "Alias: " ~ aliasCommand,
                    "alias",
                    90
                );
            }
        }

        return results;
    }

    /// Complete functions
    private CompletionResult[] completeFunctions(string prefix) {
        CompletionResult[] results;

        // For now, just add some common shell functions
        string[] functions = ["cdls", "mkcd", "up", "extract", "backup"];
        foreach(func; functions) {
            if (func.startsWith(prefix)) {
                results ~= CompletionResult(
                    func,
                    "Shell function",
                    "function",
                    70
                );
            }
        }

        return results;
    }

    /// Complete arguments
    private CompletionResult[] completeArguments(CompletionContext context) {
        CompletionResult[] results;
        string command = context.currentCommand;

        // File/directory completion
        if (shouldCompleteFiles(command, context)) {
            results ~= completeFiles(context.prefix);
        }

        // Custom command completions
        if (command in customCompletions) {
            results ~= completeCustomCommand(command, context.prefix);
        }

        // Environment variable completion
        if (context.prefix.startsWith("$")) {
            results ~= completeVariables(context.prefix);
        }

        // Username completion (for cd ~username)
        if (context.prefix.startsWith("~")) {
            results ~= completeUsernames(context.prefix);
        }

        return results;
    }

    /// Check if should complete files for this command
    private bool shouldCompleteFiles(string command, CompletionContext context) {
        // Commands that typically take file arguments
        string[] fileCommands = [
            "cd", "ls", "cat", "less", "more", "head", "tail", "grep", "find",
            "cp", "mv", "rm", "chmod", "chown", "touch", "mkdir", "rmdir",
            "tar", "gzip", "gunzip", "diff", "wc", "sort", "uniq"
        ];

        return fileCommands.canFind(command) || command.length == 0;
    }

    /// Complete files and directories
    private CompletionResult[] completeFiles(string prefix) {
        CompletionResult[] results;

        string dir = ".";
        string filePrefix = prefix;

        // Extract directory from prefix
        auto slashPos = prefix.lastIndexOf('/');
        if (slashPos >= 0) {
            dir = prefix[0..slashPos];
            filePrefix = prefix[slashPos+1..$];
            if (dir.length == 0) dir = "/";
        }

        // Handle ~ expansion
        if (dir.startsWith("~")) {
            dir = expandUser(dir);
        }

        try {
            if (exists(dir) && isDir(dir)) {
                foreach(string file; dirEntries(dir, SpanMode.shallow)) {
                    string fileName = baseName(file);
                    if (fileName.startsWith(filePrefix)) {
                        string type = isDir(file) ? "directory" : "file";
                        int priority = isDir(file) ? 100 : 50;

                        // Add trailing slash for directories
                        string displayText = fileName;
                        if (isDir(file) && !fileName.endsWith("/")) {
                            displayText ~= "/";
                        }

                        string description = type;
                        if (type == "file") {
                            description ~= " (" ~ getFileDescription(file) ~ ")";
                        }

                        results ~= CompletionResult(displayText, description, type, priority);
                    }
                }
            }
        } catch (Exception e) {
            // Can't read directory
        }

        return results;
    }

    /// Complete custom command arguments
    private CompletionResult[] completeCustomCommand(string command, string prefix) {
        CompletionResult[] results;

        if (command in customCompletions) {
            foreach(arg; customCompletions[command]) {
                if (arg.startsWith(prefix)) {
                    results ~= CompletionResult(
                        arg,
                        command ~ " " ~ arg,
                        "argument",
                        80
                    );
                }
            }
        }

        return results;
    }

    /// Complete environment variables
    private CompletionResult[] completeVariables(string prefix) {
        CompletionResult[] results;

        string varPrefix = prefix[1..$]; // Remove '$'

        // Environment variables
        foreach(string key; environment.keys) {
            if (key.startsWith(varPrefix)) {
                results ~= CompletionResult(
                    "$" ~ key,
                    environment[key],
                    "variable",
                    90
                );
            }
        }

        // Shell variables
        ShellContext shellContext = configManager.getShellContext();
        foreach(key, value; shellContext.variables) {
            if (key.startsWith(varPrefix)) {
                results ~= CompletionResult(
                    "$" ~ key,
                    value,
                    "variable",
                    90
                );
            }
        }

        return results;
    }

    /// Complete usernames
    private CompletionResult[] completeUsernames(string prefix) {
        CompletionResult[] results;

        string userPrefix = prefix[1..$]; // Remove '~'

        try {
            string[] users;
            if (exists("/etc/passwd")) {
                string content = readText("/etc/passwd");
                foreach(line; content.splitLines()) {
                    auto parts = line.split(":");
                    if (parts.length >= 1) {
                        string username = parts[0];
                        if (username.startsWith(userPrefix)) {
                            results ~= CompletionResult(
                                "~" ~ username,
                                "User: " ~ username,
                                "user",
                                60
                            );
                        }
                    }
                }
            }
        } catch (Exception e) {
            // Can't read passwd file
        }

        return results;
    }

    /// Get file description for display
    private string getFileDescription(string file) {
        try {
            string extension = file.endsWithExtension() ? file.extension : "";
            switch (extension.toLower()) {
                case ".d": return "D source";
                case ".c": return "C source";
                case ".cpp": case ".cxx": case ".cc": return "C++ source";
                case ".py": return "Python script";
                case ".js": return "JavaScript";
                case ".json": return "JSON data";
                case ".xml": return "XML data";
                case ".txt": return "Text file";
                case ".md": return "Markdown";
                case ".pdf": return "PDF document";
                case ".zip": return "ZIP archive";
                case ".tar": return "TAR archive";
                case ".gz": return "GZip archive";
                case ".jpg": case ".jpeg": case ".png": case ".gif": return "Image";
                default: return extension.length > 0 ? extension[1..$] ~ " file" : "File";
            }
        } catch (Exception) {
            return "File";
        }
    }

    /// Register custom completion for a command
    void registerCustomCompletion(string command, string[] arguments) {
        customCompletions[command] = arguments;
    }

    /// Register command description
    void registerCommandDescription(string command, string description) {
        commandDescriptions[command] = description;
    }

    /// Get command description
    string getCommandDescription(string command) {
        return commandDescriptions.get(command, "");
    }

    /// Format completion results for display
    string formatCompletions(CompletionResult[] results, int maxWidth = 80) {
        if (results.length == 0) return "";

        // Group by type
        CompletionResult[][] groups;
        string[] typeOrder = ["command", "alias", "function", "directory", "file", "variable", "user"];

        foreach(string type; typeOrder) {
            CompletionResult[] typeGroup = results.filter!(r => r.type == type).array;
            if (typeGroup.length > 0) {
                groups ~= typeGroup;
            }
        }

        string output;
        foreach(group; groups) {
            if (group.length == 0) continue;

            // Calculate column layout
            int maxTextLength = 0;
            foreach(result; group) {
                if (result.text.length > maxTextLength) {
                    maxTextLength = result.text.length;
                }
            }

            int columns = (maxWidth + 2) / (maxTextLength + 2);
            if (columns < 1) columns = 1;

            // Display group
            if (output.length > 0) output ~= "\n";
            output ~= group[0].type ~ ":\n";

            for (size_t i = 0; i < group.length; i++) {
                CompletionResult result = group[i];
                output ~= "  " ~ result.text;

                // Pad for alignment
                int padding = maxTextLength - result.text.length + 2;
                for (int j = 0; j < padding; j++) {
                    output ~= " ";
                }

                // Add description if it fits
                if (i % columns == 0) {
                    output ~= " # " ~ result.description;
                }

                if ((i + 1) % columns == 0 || i == group.length - 1) {
                    output ~= "\n";
                }
            }
        }

        return output;
    }
}
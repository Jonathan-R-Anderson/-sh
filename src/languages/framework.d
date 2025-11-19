module languages.framework;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.path;
import std.file;
import std.json;
import dlexer;
import dparser;
import shell.config;

/// Language value types
enum ValueType {
    Null,
    Boolean,
    Number,
    String,
    List,
    Map,
    Function,
    Object,
    Error
}

/// Language value representation
struct Value {
    ValueType type;
    union {
        bool boolean;
        double number;
        string string_;
        Value[] list;
        Value[string] map;
        struct {
            Value function(Value[]) func;
            string[] paramNames;
        } function_;
        struct {
            string[string] properties;
            string type_;
        } object;
        string error;
    }

    static Value Null() {
        Value v;
        v.type = ValueType.Null;
        return v;
    }

    static Value Boolean(bool b) {
        Value v;
        v.type = ValueType.Boolean;
        v.boolean = b;
        return v;
    }

    static Value Number(double n) {
        Value v;
        v.type = ValueType.Number;
        v.number = n;
        return v;
    }

    static Value String(string s) {
        Value v;
        v.type = ValueType.String;
        v.string_ = s;
        return v;
    }

    static Value List(Value[] l) {
        Value v;
        v.type = ValueType.List;
        v.list = l;
        return v;
    }

    static Value Map(Value[string] m) {
        Value v;
        v.type = ValueType.Map;
        v.map = m;
        return v;
    }

    static Value Error(string e) {
        Value v;
        v.type = ValueType.Error;
        v.error = e;
        return v;
    }

    string toString() {
        switch (type) {
            case ValueType.Null: return "null";
            case ValueType.Boolean: return boolean ? "true" : "false";
            case ValueType.Number: return to!string(number);
            case ValueType.String: return "\"" ~ string_ ~ "\"";
            case ValueType.List:
                string[] parts;
                foreach(item; list) {
                    parts ~= item.toString();
                }
                return "[" ~ parts.join(", ") ~ "]";
            case ValueType.Map:
                string[] parts;
                foreach(key, value; map) {
                    parts ~= key ~ ": " ~ value.toString();
                }
                return "{" ~ parts.join(", ") ~ "}";
            case ValueType.Error: return "Error(" ~ error ~ ")";
            default: return "<?>";
        }
    }
}

/// Execution context
class ExecutionContext {
    private Value[string] variables;
    private Value[string] functions;
    private ExecutionContext parentContext;
    private ConfigManager configManager;

    this(ConfigManager configManager = null, ExecutionContext parent = null) {
        this.configManager = configManager;
        this.parentContext = parent;
    }

    void setVariable(string name, Value value) {
        variables[name] = value;
    }

    Value getVariable(string name) {
        if (name in variables) {
            return variables[name];
        }
        if (parentContext !is null) {
            return parentContext.getVariable(name);
        }
        return Value.Null();
    }

    void setFunction(string name, Value value) {
        functions[name] = value;
    }

    Value getFunction(string name) {
        if (name in functions) {
            return functions[name];
        }
        if (parentContext !is null) {
            return parentContext.getFunction(name);
        }
        return Value.Null();
    }

    bool hasVariable(string name) {
        return (name in variables) || (parentContext !is null && parentContext.hasVariable(name));
    }

    bool hasFunction(string name) {
        return (name in functions) || (parentContext !is null && parentContext.hasFunction(name));
    }

    ExecutionContext createChild() {
        return new ExecutionContext(configManager, this);
    }
}

/// Completion result
struct CompletionResult {
    string text;
    string description;
    string type;
    int priority;
}

/// Language interface
interface Language {
    string name();
    string[] extensions();
    string[] fileNames();
    bool canHandle(string input);
    Value execute(string code, ExecutionContext context);
    CompletionResult[] getCompletion(string prefix, string context);
    string getSyntaxHighlighting(string code);
    string getDescription();
    bool supportsInteractive();
    bool supportsCompilation();
    Value compile(string code);
}

/// Built-in function signature
alias BuiltinFunction = Value function(Value[] args, ExecutionContext context);

/// Language registration information
struct LanguageRegistration {
    Language language;
    string[] extensions;
    string[] patterns;
    int priority;
    bool enabled;
}

/// Language registry
class LanguageRegistry {
    private LanguageRegistration[string] languages;
    private ConfigManager configManager;

    this(ConfigManager configManager) {
        this.configManager = configManager;
        registerBuiltinLanguages();
        loadUserLanguages();
    }

    /// Register built-in languages
    private void registerBuiltinLanguages() {
        // Register LFE (already exists)
        registerLanguage(new LFELanguage(), ["lfe", ".lfe"], ["^\\s*\\("], 100);

        // Register JavaScript support
        registerLanguage(new JavaScriptLanguage(), ["js", "javascript", ".js"], [], 80);

        // Register Python support
        registerLanguage(new PythonLanguage(), ["py", "python", ".py"], [], 80);

        // Register Shell script support
        registerLanguage(new ShellLanguage(), ["sh", "bash", ".sh", ".bash"], [], 60);

        // Register JSON support
        registerLanguage(new JSONLanguage(), ["json", ".json"], [], 40);
    }

    /// Load user-defined languages
    private void loadUserLanguages() {
        // TODO: Load from configuration
    }

    /// Register a language
    void registerLanguage(Language language, string[] extensions, string[] patterns, int priority = 50) {
        LanguageRegistration registration;
        registration.language = language;
        registration.extensions = extensions;
        registration.patterns = patterns;
        registration.priority = priority;
        registration.enabled = true;

        languages[language.name()] = registration;
    }

    /// Unregister a language
    void unregisterLanguage(string name) {
        languages.remove(name);
    }

    /// Detect language for input
    Language detectLanguage(string input) {
        LanguageRegistration[] candidates;

        // Check patterns first (highest priority)
        foreach(name, registration; languages) {
            if (!registration.enabled) continue;

            foreach(pattern; registration.patterns) {
                import std.regex;
                try {
                    auto regex = Regex(pattern);
                    if (matchFirst(input, regex)) {
                        candidates ~= registration;
                        break;
                    }
                } catch (Exception e) {
                    // Skip invalid regex
                }
            }
        }

        // Sort by priority
        candidates = candidates.sort!((a, b) => a.priority > b.priority);

        if (candidates.length > 0) {
            return candidates[0].language;
        }

        // Check for LFE by default (starts with '(' or prefixed with ':lfe')
        if (input.strip().startsWith("(") || input.strip().startsWith(":lfe")) {
            return languages["lfe"].language;
        }

        return null;
    }

    /// Get language by name
    Language getLanguage(string name) {
        if (name in languages) {
            return languages[name].language;
        }
        return null;
    }

    /// Execute code with auto-detected language
    Value executeCode(string input, ExecutionContext context) {
        Language language = detectLanguage(input);
        if (language is null) {
            // Default to shell execution
            return shell.config.Value.Error("No language detected for input");
        }

        return language.execute(input, context);
    }

    /// Get completion for context
    CompletionResult[] getCompletion(string prefix, string context) {
        CompletionResult[] results;

        foreach(registration; languages.values) {
            if (!registration.enabled) continue;

            try {
                auto completions = registration.language.getCompletion(prefix, context);
                results ~= completions;
            } catch (Exception e) {
                // Skip failing completions
            }
        }

        // Sort by priority and remove duplicates
        results = results.sort!((a, b) => a.priority > b.priority);
        // TODO: Remove duplicates

        return results;
    }

    /// List all registered languages
    string[] listLanguages() {
        string[] names;
        foreach(name, registration; languages) {
            if (registration.enabled) {
                names ~= name ~ " (" ~ registration.language.getDescription() ~ ")";
            }
        }
        return names;
    }

    /// Enable/disable language
    void setLanguageEnabled(string name, bool enabled) {
        if (name in languages) {
            languages[name].enabled = enabled;
        }
    }

    /// Get language info
    string getLanguageInfo(string name) {
        if (name in languages) {
            auto registration = languages[name];
            return "Language: " ~ name ~ "\n" ~
                   "Description: " ~ registration.language.getDescription() ~ "\n" ~
                   "Extensions: " ~ registration.extensions.join(", ") ~ "\n" ~
                   "Priority: " ~ to!string(registration.priority) ~ "\n" ~
                   "Enabled: " ~ (registration.enabled ? "Yes" : "No");
        }
        return "Language not found: " ~ name;
    }
}

/// Simple JavaScript-like language implementation
class JavaScriptLanguage : Language {
    string name() { return "javascript"; }

    string[] extensions() { return ["js", ".js"]; }

    string[] fileNames() { return ["package.json", "*.js"]; }

    bool canHandle(string input) {
        // Simple heuristic for JavaScript
        return input.canFind("function") || input.canFind("var ") ||
               input.canFind("let ") || input.canFind("const ") ||
               input.canFind("//") || input.canFind("/*");
    }

    Value execute(string code, ExecutionContext context) {
        // Very simple JavaScript-like execution
        if (code.strip().startsWith("console.log")) {
            string content = code[code.indexOf("(")+1..code.lastIndexOf(")")];
            writeln("JS Output: ", content);
            return Value.String(content);
        }
        return Value.Error("JavaScript execution not fully implemented");
    }

    CompletionResult[] getCompletion(string prefix, string context) {
        CompletionResult[] results;
        string[] keywords = ["function", "var", "let", "const", "if", "else", "for", "while", "return"];

        foreach(keyword; keywords) {
            if (keyword.startsWith(prefix)) {
                results ~= CompletionResult(keyword, "JavaScript keyword", "keyword", 90);
            }
        }
        return results;
    }

    string getSyntaxHighlighting(string code) {
        // TODO: Implement syntax highlighting
        return code;
    }

    string getDescription() { return "JavaScript-like language support"; }

    bool supportsInteractive() { return true; }

    bool supportsCompilation() { return false; }

    Value compile(string code) {
        return Value.Error("JavaScript compilation not supported");
    }
}

/// Simple Python-like language implementation
class PythonLanguage : Language {
    string name() { return "python"; }

    string[] extensions() { return ["py", ".py"]; }

    string[] fileNames() { return ["*.py", "requirements.txt"]; }

    bool canHandle(string input) {
        return input.canFind("def ") || input.canFind("import ") ||
               input.canFind("class ") || input.startsWith("#") ||
               input.canFind("print(");
    }

    Value execute(string code, ExecutionContext context) {
        if (code.strip().startsWith("print")) {
            string content = code[code.indexOf("(")+1..code.lastIndexOf(")")];
            writeln("Python Output: ", content);
            return Value.String(content);
        }
        return Value.Error("Python execution not fully implemented");
    }

    CompletionResult[] getCompletion(string prefix, string context) {
        CompletionResult[] results;
        string[] keywords = ["def", "class", "import", "if", "else", "for", "while", "return", "print"];

        foreach(keyword; keywords) {
            if (keyword.startsWith(prefix)) {
                results ~= CompletionResult(keyword, "Python keyword", "keyword", 90);
            }
        }
        return results;
    }

    string getSyntaxHighlighting(string code) {
        // TODO: Implement syntax highlighting
        return code;
    }

    string getDescription() { return "Python-like language support"; }

    bool supportsInteractive() { return true; }

    bool supportsCompilation() { return false; }

    Value compile(string code) {
        return Value.Error("Python compilation not supported");
    }
}

/// Shell script language implementation
class ShellLanguage : Language {
    string name() { return "shell"; }

    string[] extensions() { return ["sh", "bash", ".sh", ".bash"]; }

    string[] fileNames() { return ["*.sh", ".bashrc", ".profile"]; }

    bool canHandle(string input) {
        return input.startsWith("#!/") || input.canFind("$") ||
               input.canFind("for ") || input.canFind("if ") ||
               input.canFind("echo ") || input.canFind("cd ");
    }

    Value execute(string code, ExecutionContext context) {
        // This would delegate to the main shell executor
        return Value.Error("Shell execution through language framework not implemented");
    }

    CompletionResult[] getCompletion(string prefix, string context) {
        CompletionResult[] results;
        string[] keywords = ["if", "then", "else", "fi", "for", "while", "case", "esac", "function"];

        foreach(keyword; keywords) {
            if (keyword.startsWith(prefix)) {
                results ~= CompletionResult(keyword, "Shell keyword", "keyword", 90);
            }
        }
        return results;
    }

    string getSyntaxHighlighting(string code) {
        // TODO: Implement syntax highlighting
        return code;
    }

    string getDescription() { return "Shell script language support"; }

    bool supportsInteractive() { return false; }

    bool supportsCompilation() { return false; }

    Value compile(string code) {
        return Value.Error("Shell compilation not supported");
    }
}

/// JSON language implementation
class JSONLanguage : Language {
    string name() { return "json"; }

    string[] extensions() { return ["json", ".json"]; }

    string[] fileNames() { return ["*.json", "package.json"]; }

    bool canHandle(string input) {
        string trimmed = input.strip();
        return (trimmed.startsWith("{") && trimmed.endsWith("}")) ||
               (trimmed.startsWith("[") && trimmed.endsWith("]"));
    }

    Value execute(string code, ExecutionContext context) {
        try {
            JSONValue json = parseJSON(code);
            // Convert JSON to Value
            return convertJSONToValue(json);
        } catch (Exception e) {
            return Value.Error("Invalid JSON: " ~ e.msg);
        }
    }

    private Value convertJSONToValue(JSONValue json) {
        final switch (json.type) {
            case JSON_TYPE.NULL:
                return Value.Null();
            case JSON_TYPE.TRUE:
                return Value.Boolean(true);
            case JSON_TYPE.FALSE:
                return Value.Boolean(false);
            case JSON_TYPE.INTEGER:
                return Value.Number(cast(double) json.integer);
            case JSON_TYPE.FLOAT:
                return Value.Number(json.floating);
            case JSON_TYPE.STRING:
                return Value.String(json.str);
            case JSON_TYPE.ARRAY:
                Value[] array;
                foreach(item; json.array) {
                    array ~= convertJSONToValue(item);
                }
                return Value.List(array);
            case JSON_TYPE.OBJECT:
                Value[string] map;
                foreach(key, value; json.object) {
                    map[key] = convertJSONToValue(value);
                }
                return Value.Map(map);
        }
    }

    CompletionResult[] getCompletion(string prefix, string context) {
        // JSON doesn't have much completion
        return [];
    }

    string getSyntaxHighlighting(string code) {
        // TODO: Implement JSON syntax highlighting
        return code;
    }

    string getDescription() { return "JSON data format support"; }

    bool supportsInteractive() { return false; }

    bool supportsCompilation() { return false; }

    Value compile(string code) {
        return execute(code, null);
    }
}

/// LFE language wrapper
class LFELanguage : Language {
    string name() { return "lfe"; }

    string[] extensions() { return ["lfe", ".lfe"]; }

    string[] fileNames() { return ["*.lfe"]; }

    bool canHandle(string input) {
        string trimmed = input.strip();
        return trimmed.startsWith("(") || trimmed.startsWith(":lfe");
    }

    Value execute(string code, ExecutionContext context) {
        // This would delegate to the existing LFE interpreter
        try {
            // TODO: Call existing LFE evaluation
            return Value.String("LFE execution not yet integrated");
        } catch (Exception e) {
            return Value.Error("LFE Error: " ~ e.msg);
        }
    }

    CompletionResult[] getCompletion(string prefix, string context) {
        CompletionResult[] results;
        string[] lfeFunctions = ["defun", "defmacro", "defmodule", "let", "case", "cond", "if", "lambda"];

        foreach(func; lfeFunctions) {
            if (func.startsWith(prefix)) {
                results ~= CompletionResult(func, "LFE function", "function", 90);
            }
        }
        return results;
    }

    string getSyntaxHighlighting(string code) {
        // TODO: Implement LFE syntax highlighting
        return code;
    }

    string getDescription() { return "Lisp Flavored Erlang"; }

    bool supportsInteractive() { return true; }

    bool supportsCompilation() { return true; }

    Value compile(string code) {
        // TODO: LFE compilation to Erlang
        return Value.Error("LFE compilation not yet implemented");
    }
}
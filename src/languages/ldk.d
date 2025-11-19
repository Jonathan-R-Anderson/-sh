module languages.ldk;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.json;
import std.path;
import std.file;
import std.regex;
import dlexer;
import dparser;
import shell.config;
import shell.themes;
import languages.framework;

/// Language specification
struct LanguageSpec {
    string name;
    string version;
    string description;
    string author;

    // Lexer specification
    TokenSpec[] tokenSpecs;
    string[] skipTokens;
    string[] keywords;

    // Grammar rules
    GrammarRule[] grammarRules;
    string startSymbol;

    // Runtime configuration
    RuntimeConfig runtimeConfig;

    // Built-in functions
    BuiltinFunctionSpec[] builtinFunctions;
}

/// Token specification for lexer
struct TokenSpec {
    string name;
    string pattern; // Regex pattern
    int priority; // Higher priority = checked first
    bool isKeyword;
}

/// Grammar rule
struct GrammarRule {
    string lhs;    // Left-hand side (non-terminal)
    string[] rhs;  // Right-hand side (symbols)
    string action; // Code to execute when rule matches
}

/// Runtime configuration
struct RuntimeConfig {
    bool sandboxEnabled = true;
    int maxMemoryBytes = 100 * 1024 * 1024; // 100MB
    Duration maxExecutionTime = dur!"seconds"(30);
    bool allowFileAccess = false;
    bool allowNetworkAccess = false;
    string[] allowedFilePaths;
    string[] allowedNetworkHosts;
}

/// Built-in function specification
struct BuiltinFunctionSpec {
    string name;
    string[] paramNames;
    string returnType;
    string code; // D code implementation
    string description;
}

/// Language builder
class LanguageBuilder {
    private LanguageSpec spec;
    private Rule[] lexerRules;
    private Rule[] parserRules;

    this() {
        spec.name = "";
        spec.version = "1.0.0";
        spec.description = "";
        spec.author = "";
        spec.startSymbol = "program";
        spec.runtimeConfig = RuntimeConfig();
    }

    LanguageBuilder setName(string name) {
        spec.name = name;
        return this;
    }

    LanguageBuilder setVersion(string version) {
        spec.version = version;
        return this;
    }

    LanguageBuilder setDescription(string description) {
        spec.description = description;
        return this;
    }

    LanguageBuilder setAuthor(string author) {
        spec.author = author;
        return this;
    }

    // Token specification methods
    LanguageBuilder addToken(string name, string pattern, int priority = 0, bool isKeyword = false) {
        TokenSpec tokenSpec;
        tokenSpec.name = name;
        tokenSpec.pattern = pattern;
        tokenSpec.priority = priority;
        tokenSpec.isKeyword = isKeyword;
        spec.tokenSpecs ~= tokenSpec;
        return this;
    }

    LanguageBuilder addSkipToken(string pattern) {
        spec.skipTokens ~= pattern;
        return this;
    }

    LanguageBuilder addKeyword(string keyword) {
        spec.keywords ~= keyword;
        return this;
    }

    // Grammar rule methods
    LanguageBuilder addRule(string lhs, string[] rhs, string action = "") {
        GrammarRule rule;
        rule.lhs = lhs;
        rule.rhs = rhs;
        rule.action = action;
        spec.grammarRules ~= rule;
        return this;
    }

    LanguageBuilder setStartSymbol(string startSymbol) {
        spec.startSymbol = startSymbol;
        return this;
    }

    // Runtime configuration methods
    LanguageBuilder setSandboxEnabled(bool enabled) {
        spec.runtimeConfig.sandboxEnabled = enabled;
        return this;
    }

    LanguageBuilder setMaxMemory(int maxMemoryBytes) {
        spec.runtimeConfig.maxMemoryBytes = maxMemoryBytes;
        return this;
    }

    LanguageBuilder setMaxExecutionTime(Duration maxTime) {
        spec.runtimeConfig.maxExecutionTime = maxTime;
        return this;
    }

    LanguageBuilder allowFileAccess(bool allowed) {
        spec.runtimeConfig.allowFileAccess = allowed;
        return this;
    }

    LanguageBuilder allowNetworkAccess(bool allowed) {
        spec.runtimeConfig.allowNetworkAccess = allowed;
        return this;
    }

    // Built-in function methods
    LanguageBuilder addBuiltinFunction(string name, string[] paramNames, string returnType, string code, string description = "") {
        BuiltinFunctionSpec funcSpec;
        funcSpec.name = name;
        funcSpec.paramNames = paramNames;
        funcSpec.returnType = returnType;
        funcSpec.code = code;
        funcSpec.description = description;
        spec.builtinFunctions ~= funcSpec;
        return this;
    }

    // Build the language
    CustomLanguage build() {
        if (spec.name.length == 0) {
            throw new Exception("Language name cannot be empty");
        }

        // Create lexer rules from token specs
        lexerRules = createLexerRules();

        // Create parser from grammar rules
        // This would be more complex in a real implementation
        // For now, create a simple placeholder

        return new CustomLanguage(spec);
    }

    private Rule[] createLexerRules() {
        Rule[] rules;

        // Sort token specs by priority (higher first)
        TokenSpec[] sortedSpecs = spec.tokenSpecs.dup;
        sortedSpecs.sort!((a, b) => b.priority > a.priority);

        foreach(tokenSpec; sortedSpecs) {
            Rule rule;
            rule.name = tokenSpec.name;
            try {
                rule.pattern = Regex(tokenSpec.pattern);
                rules ~= rule;
            } catch (Exception e) {
                writeln("Warning: Invalid regex pattern for token '" ~ tokenSpec.name ~ "': " ~ e.msg);
            }
        }

        // Add skip tokens
        foreach(skipPattern; spec.skipTokens) {
            Rule rule;
            rule.name = "SKIP";
            try {
                rule.pattern = Regex(skipPattern);
                rules ~= rule;
            } catch (Exception e) {
                writeln("Warning: Invalid skip regex pattern: " ~ e.msg);
            }
        }

        return rules;
    }
}

/// Custom language implementation
class CustomLanguage : Language {
    private LanguageSpec spec;
    private LanguageRegistry registry;
    private LanguageSandbox sandbox;

    this(LanguageSpec spec, LanguageRegistry registry = null) {
        this.spec = spec;
        this.registry = registry;
        this.sandbox = new LanguageSandbox(spec.runtimeConfig);
    }

    string name() {
        return spec.name;
    }

    string[] extensions() {
        string[] extensions;
        foreach(ext; spec.extensions) {
            extensions ~= ext;
        }
        return extensions;
    }

    string[] fileNames() {
        return spec.fileNames;
    }

    bool canHandle(string input) {
        // Check if input starts with language marker
        string marker = "#" ~ spec.name;
        if (input.strip().startsWith(marker)) {
            return true;
        }

        // Check file patterns
        foreach(pattern; spec.filePatterns) {
            try {
                auto regex = Regex(pattern);
                if (matchFirst(input, regex)) {
                    return true;
                }
            } catch (Exception) {
                // Skip invalid patterns
            }
        }

        return false;
    }

    Value execute(string code, ExecutionContext context) {
        // Remove language marker if present
        string marker = "#" ~ spec.name;
        if (code.strip().startsWith(marker)) {
            code = code.strip()[marker.length..$].strip();
        }

        // Execute in sandbox
        return sandbox.execute(this, code, context);
    }

    CompletionResult[] getCompletion(string prefix, string context) {
        CompletionResult[] results;

        // Complete keywords
        foreach(keyword; spec.keywords) {
            if (keyword.startsWith(prefix)) {
                results ~= CompletionResult(keyword, "Keyword", "keyword", 100);
            }
        }

        // Complete built-in functions
        foreach(func; spec.builtinFunctions) {
            if (func.name.startsWith(prefix)) {
                results ~= CompletionResult(func.name, func.description, "function", 90);
            }
        }

        return results;
    }

    string getSyntaxHighlighting(string code) {
        // This would implement syntax highlighting
        // For now, return the original code
        return code;
    }

    string getDescription() {
        return spec.description;
    }

    bool supportsInteractive() {
        return spec.runtimeConfig.interactiveMode;
    }

    bool supportsCompilation() {
        return spec.runtimeConfig.compilationEnabled;
    }

    Value compile(string code) {
        if (!supportsCompilation()) {
            return Value.Error("Compilation not supported for this language");
        }

        // This would implement compilation to intermediate code
        return Value.Error("Compilation not yet implemented");
    }

    LanguageSpec getSpec() {
        return spec;
    }
}

/// Language sandbox
class LanguageSandbox {
    private RuntimeConfig config;
    private long memoryUsage = 0;
    private Clock.TimePoint startTime;

    this(RuntimeConfig config) {
        this.config = config;
    }

    Value execute(CustomLanguage language, string code, ExecutionContext context) {
        if (!config.sandboxEnabled) {
            return executeUnsandboxed(language, code, context);
        }

        startTime = Clock.currTime();
        memoryUsage = 0;

        // Check execution time
        if (config.maxExecutionTime != Duration.zero) {
            // This would be implemented with actual timeout handling
        }

        // Check memory usage
        if (config.maxMemoryBytes > 0) {
            // This would be implemented with actual memory tracking
        }

        // Execute with restrictions
        try {
            // Create sandboxed context
            ExecutionContext sandboxedContext = createSandboxedContext(context);

            // Execute the code
            Value result = executeUnsandboxed(language, code, sandboxedContext);

            // Check result for violations
            validateResult(result);

            return result;

        } catch (Exception e) {
            return Value.Error("Sandbox execution failed: " ~ e.msg);
        }
    }

    private Value executeUnsandboxed(CustomLanguage language, string code, ExecutionContext context) {
        // This would be the actual language interpreter
        // For now, return a placeholder result

        // Simple example: interpret basic expressions
        return interpretBasicExpression(code, context);
    }

    private Value interpretBasicExpression(string code, ExecutionContext context) {
        string trimmed = code.strip();

        // Handle simple literals
        if (trimmed.startsWith("\"") && trimmed.endsWith("\"")) {
            return Value.String(trimmed[1..$-1]);
        }

        try {
            // Try to parse as number
            int number = to!int(trimmed);
            return Value.Number(cast(double)number);
        } catch (Exception) {
            // Not a number
        }

        try {
            // Try to parse as float
            double number = to!double(trimmed);
            return Value.Number(number);
        } catch (Exception) {
            // Not a number
        }

        // Handle boolean literals
        if (trimmed == "true") return Value.Boolean(true);
        if (trimmed == "false") return Value.Boolean(false);
        if (trimmed == "null") return Value.Null();

        // Handle variable references
        if (context.hasVariable(trimmed)) {
            return context.getVariable(trimmed);
        }

        // Handle basic arithmetic (very simplified)
        if (trimmed.canFind('+')) {
            auto parts = trimmed.split('+');
            if (parts.length == 2) {
                Value left = interpretBasicExpression(parts[0].strip(), context);
                Value right = interpretBasicExpression(parts[1].strip(), context);
                if (left.type == ValueType.Number && right.type == ValueType.Number) {
                    return Value.Number(left.number + right.number);
                }
            }
        }

        return Value.Error("Unrecognized expression: " ~ trimmed);
    }

    private ExecutionContext createSandboxedContext(ExecutionContext parent) {
        ExecutionContext sandboxed = parent.createChild();

        // Add restricted built-in functions
        // This would implement sandboxed versions of functions

        return sandboxed;
    }

    private void validateResult(Value result) {
        // Check if result violates sandbox restrictions
        // For now, just log memory usage
        memoryUsage += estimateMemoryUsage(result);

        if (config.maxMemoryBytes > 0 && memoryUsage > config.maxMemoryBytes) {
            throw new Exception("Memory limit exceeded");
        }
    }

    private long estimateMemoryUsage(Value value) {
        // Simplified memory usage estimation
        switch (value.type) {
            case ValueType.String:
                return value.string_.length;
            case ValueType.List:
                long total = 0;
                foreach(item; value.list) {
                    total += estimateMemoryUsage(item);
                }
                return total;
            case ValueType.Map:
                long total = 0;
                foreach(key, val; value.map) {
                    total += key.length + estimateMemoryUsage(val);
                }
                return total;
            default:
                return 8; // Basic size for other types
        }
    }
}

/// Language template
class LanguageTemplate {
    private string name;
    private string description;
    private LanguageBuilder templateBuilder;

    this(string name, string description) {
        this.name = name;
        this.description = description;
        this.templateBuilder = createTemplateBuilder();
    }

    LanguageBuilder createBuilder() {
        // Create a copy of the template builder
        LanguageBuilder builder = new LanguageBuilder()
            .setName(templateBuilder.spec.name)
            .setDescription(templateBuilder.spec.description)
            .setVersion(templateBuilder.spec.version);

        // Copy other properties
        // This is simplified - in a real implementation, this would copy all properties

        return builder;
    }

    protected LanguageBuilder createTemplateBuilder() {
        // Subclasses should implement this
        return new LanguageBuilder();
    }
}

/// Expression language template
class ExpressionLanguageTemplate : LanguageTemplate {
    this() {
        super("expression", "Simple arithmetic expression language");
    }

    protected override LanguageBuilder createTemplateBuilder() {
        return new LanguageBuilder()
            .setName("expression")
            .setDescription("Simple arithmetic expressions")
            .setVersion("1.0.0")

            // Tokens
            .addToken("NUMBER", @"\d+(\.\d+)?", 100)
            .addToken("PLUS", @"\+", 90)
            .addToken("MINUS", @"-", 90)
            .addToken("TIMES", @"\*", 90)
            .addToken("DIVIDE", @"/", 90)
            .addToken("LPAREN", @"\(", 80)
            .addToken("RPAREN", @"\)", 80)
            .addSkipToken(@"\s+")

            // Grammar
            .setStartSymbol("expr")
            .addRule("expr", ["term"])
            .addRule("expr", ["expr", "PLUS", "term"])
            .addRule("expr", ["expr", "MINUS", "term"])
            .addRule("term", ["factor"])
            .addRule("term", ["term", "TIMES", "factor"])
            .addRule("term", ["term", "DIVIDE", "factor"])
            .addRule("factor", ["NUMBER"])
            .addRule("factor", ["LPAREN", "expr", "RPAREN"])

            // Runtime config
            .setSandboxEnabled(true)
            .setMaxMemory(10 * 1024 * 1024) // 10MB
            .setMaxExecutionTime(dur!"seconds"(5))
            .allowFileAccess(false)
            .allowNetworkAccess(false);
    }
}

/// Scripting language template
class ScriptingLanguageTemplate : LanguageTemplate {
    this() {
        super("scripting", "Basic scripting language with variables and functions");
    }

    protected override LanguageBuilder createTemplateBuilder() {
        return new LanguageBuilder()
            .setName("scripting")
            .setDescription("Basic scripting language")
            .setVersion("1.0.0")

            // Tokens
            .addToken("IDENTIFIER", @"[a-zA-Z_][a-zA-Z0-9_]*", 100)
            .addToken("NUMBER", @"\d+(\.\d+)?", 90)
            .addToken("STRING", "\"([^\"\\\\]|\\\\.)*\"", 90)
            .addToken("ASSIGN", @"=", 80)
            .addToken("PLUS", @"\+", 70)
            .addToken("SEMICOLON", @";", 60)
            .addToken("LPAREN", @"\(", 50)
            .addToken("RPAREN", @"\)", 50)
            .addToken("LBRACE", @"\{", 50)
            .addToken("RBRACE", @"\}", 50)
            .addSkipToken(@"\s+")
            .addSkipToken(@"//.*")
            .addSkipToken(@"/\*[\s\S]*?\*/")

            // Keywords
            .addKeyword("var")
            .addKeyword("if")
            .addKeyword("else")
            .addKeyword("while")
            .addKeyword("function")
            .addKeyword("return")

            // Grammar
            .setStartSymbol("program")
            .addRule("program", ["statement_list"])
            .addRule("statement_list", ["statement"])
            .addRule("statement_list", ["statement", "statement_list"])
            .addRule("statement", ["var_declaration"])
            .addRule("statement", ["assignment"])
            .addRule("statement", ["if_statement"])
            .addRule("statement", ["while_statement"])
            .addRule("statement", ["function_call"])
            .addRule("var_declaration", ["var", "IDENTIFIER", "SEMICOLON"])
            .addRule("assignment", ["IDENTIFIER", "ASSIGN", "expression", "SEMICOLON"])
            .addRule("if_statement", ["if", "LPAREN", "expression", "RPAREN", "LBRACE", "statement_list", "RBRACE"])
            .addRule("while_statement", ["while", "LPAREN", "expression", "RPAREN", "LBRACE", "statement_list", "RBRACE"])

            // Built-in functions
            .addBuiltinFunction("print", ["value"], "void", "writeln(value);", "Print a value to console")
            .addBuiltinFunction("input", [], "string", "readln();", "Read input from user")
            .addBuiltinFunction("len", ["array"], "number", "array.length;", "Get length of array")

            // Runtime config
            .setSandboxEnabled(true)
            .setMaxMemory(50 * 1024 * 1024) // 50MB
            .setMaxExecutionTime(dur!"seconds"(30))
            .allowFileAccess(false)
            .allowNetworkAccess(false);
    }
}

/// Language Development Kit Manager
class LanguageDevelopmentKit {
    private ConfigManager configManager;
    private LanguageRegistry registry;
    private LanguageTemplate[string] templates;
    private CustomLanguage[string] customLanguages;

    this(ConfigManager configManager, LanguageRegistry registry) {
        this.configManager = configManager;
        this.registry = registry;
        initializeTemplates();
    }

    private void initializeTemplates() {
        templates["expression"] = new ExpressionLanguageTemplate();
        templates["scripting"] = new ScriptingLanguageTemplate();
    }

    /// Create a new language from template
    LanguageBuilder createLanguageFromTemplate(string templateName, string languageName) {
        if (templateName !in templates) {
            throw new Exception("Unknown template: " ~ templateName);
        }

        LanguageTemplate template = templates[templateName];
        LanguageBuilder builder = template.createBuilder();
        builder.setName(languageName);

        return builder;
    }

    /// Create a new language from scratch
    LanguageBuilder createLanguage(string name) {
        return new LanguageBuilder().setName(name);
    }

    /// Register a custom language
    void registerLanguage(CustomLanguage language) {
        customLanguages[language.name()] = language;
        registry.registerLanguage(language, language.extensions(), [], 50);
    }

    /// Unregister a custom language
    void unregisterLanguage(string name) {
        if (name in customLanguages) {
            customLanguages.remove(name);
            // Note: This would need to unregister from registry too
        }
    }

    /// List available templates
    string[] listTemplates() {
        string[] result;
        foreach(name, template; templates) {
            result ~= name ~ " - " ~ template.description;
        }
        return result;
    }

    /// List custom languages
    string[] listCustomLanguages() {
        string[] result;
        foreach(name, language; customLanguages) {
            result ~= name ~ " - " ~ language.getDescription();
        }
        return result;
    }

    /// Get language specification
    LanguageSpec getLanguageSpec(string name) {
        if (name in customLanguages) {
            return customLanguages[name].getSpec();
        }
        throw new Exception("Language not found: " ~ name);
    }

    /// Save language to file
    void saveLanguage(string name, string filepath) {
        if (name !in customLanguages) {
            throw new Exception("Language not found: " ~ name);
        }

        LanguageSpec spec = customLanguages[name].getSpec();
        saveLanguageSpec(spec, filepath);
    }

    /// Load language from file
    CustomLanguage loadLanguage(string filepath) {
        LanguageSpec spec = loadLanguageSpec(filepath);
        CustomLanguage language = new CustomLanguage(spec, registry);
        registerLanguage(language);
        return language;
    }

    private void saveLanguageSpec(LanguageSpec spec, string filepath) {
        JSONValue json = JSONValue();

        // Basic info
        json.object["name"] = JSONValue(spec.name);
        json.object["version"] = JSONValue(spec.version);
        json.object["description"] = JSONValue(spec.description);
        json.object["author"] = JSONValue(spec.author);

        // Lexer specification
        JSONValue tokens = JSONValue();
        foreach(tokenSpec; spec.tokenSpecs) {
            JSONValue tokenJson = JSONValue();
            tokenJson.object["name"] = JSONValue(tokenSpec.name);
            tokenJson.object["pattern"] = JSONValue(tokenSpec.pattern);
            tokenJson.object["priority"] = JSONValue(tokenSpec.priority);
            tokenJson.object["isKeyword"] = JSONValue(tokenSpec.isKeyword);
            tokens.array ~= tokenJson;
        }
        json.object["tokens"] = tokens;

        // Grammar rules
        JSONValue grammar = JSONValue();
        foreach(rule; spec.grammarRules) {
            JSONValue ruleJson = JSONValue();
            ruleJson.object["lhs"] = JSONValue(rule.lhs);
            JSONValue rhsArray = JSONValue();
            foreach(symbol; rule.rhs) {
                rhsArray.array ~= JSONValue(symbol);
            }
            ruleJson.object["rhs"] = rhsArray;
            ruleJson.object["action"] = JSONValue(rule.action);
            grammar.array ~= ruleJson;
        }
        json.object["grammar"] = grammar;

        // Runtime configuration
        JSONValue runtime = JSONValue();
        runtime.object["sandboxEnabled"] = JSONValue(spec.runtimeConfig.sandboxEnabled);
        runtime.object["maxMemoryBytes"] = JSONValue(spec.runtimeConfig.maxMemoryBytes);
        runtime.object["maxExecutionTime"] = JSONValue(spec.runtimeConfig.maxExecutionTime.total!"msecs");
        runtime.object["allowFileAccess"] = JSONValue(spec.runtimeConfig.allowFileAccess);
        runtime.object["allowNetworkAccess"] = JSONValue(spec.runtimeConfig.allowNetworkAccess);
        json.object["runtime"] = runtime;

        std.file.write(filepath, json.toPrettyString());
    }

    private LanguageSpec loadLanguageSpec(string filepath) {
        string content = readText(filepath);
        JSONValue json = parseJSON(content);

        LanguageSpec spec;

        // Basic info
        spec.name = json.object["name"].str;
        spec.version = json.object.get("version", JSONValue("1.0.0")).str;
        spec.description = json.object.get("description", JSONValue("")).str;
        spec.author = json.object.get("author", JSONValue("")).str;

        // Parse tokens
        if ("tokens" in json.object) {
            foreach(tokenJson; json["tokens"].array) {
                TokenSpec tokenSpec;
                tokenSpec.name = tokenJson.object["name"].str;
                tokenSpec.pattern = tokenJson.object["pattern"].str;
                tokenSpec.priority = tokenJson.object.get("priority", JSONValue(0)).integer;
                tokenSpec.isKeyword = tokenJson.object.get("isKeyword", JSONValue(false)).bool_;
                spec.tokenSpecs ~= tokenSpec;
            }
        }

        // Parse grammar
        if ("grammar" in json.object) {
            foreach(ruleJson; json["grammar"].array) {
                GrammarRule rule;
                rule.lhs = ruleJson.object["lhs"].str;

                foreach(symbolJson; ruleJson.object["rhs"].array) {
                    rule.rhs ~= symbolJson.str;
                }

                rule.action = ruleJson.object.get("action", JSONValue("")).str;
                spec.grammarRules ~= rule;
            }
        }

        // Parse runtime configuration
        if ("runtime" in json.object) {
            JSONValue runtimeJson = json["runtime"];
            spec.runtimeConfig.sandboxEnabled = runtimeJson.object.get("sandboxEnabled", JSONValue(true)).bool_;
            spec.runtimeConfig.maxMemoryBytes = runtimeJson.object.get("maxMemoryBytes", JSONValue(100*1024*1024)).integer;
            spec.runtimeConfig.maxExecutionTime = dur!"msecs"(runtimeJson.object.get("maxExecutionTime", JSONValue(30000)).integer);
            spec.runtimeConfig.allowFileAccess = runtimeJson.object.get("allowFileAccess", JSONValue(false)).bool_;
            spec.runtimeConfig.allowNetworkAccess = runtimeJson.object.get("allowNetworkAccess", JSONValue(false)).bool_;
        }

        return spec;
    }
}
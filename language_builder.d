module language_builder;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.json;
import std.file;

/// Language definition structure
struct LanguageDefinition {
    string name;
    string description;
    string author;
    string version_;

    // Syntax definition
    TokenDefinition[] tokens;
    GrammarRule[] grammar;

    // Built-in functions
    BuiltinFunction[] builtins;

    // Runtime configuration
    bool sandboxEnabled = true;
    int maxExecutionTime = 30; // seconds
    int maxMemoryMB = 50;
}

/// Token definition
struct TokenDefinition {
    string name;
    string pattern; // regex pattern
    string example;
    string description;
}

/// Grammar rule definition
struct GrammarRule {
    string pattern; // Left-Hand-Side -> Right-Hand-Side
    string description;
    string action; // Action code
}

/// Built-in function
struct BuiltinFunction {
    string name;
    string[] parameters;
    string description;
    string code; // Functional code
}

/// Fluid language builder
class LanguageBuilder {
    private LanguageDefinition definition;
    private TokenDefinition[string] tokenRegistry;
    private GrammarRule[] grammarRules;
    private BuiltinFunction[string] builtinRegistry;

    this() {
        definition.name = "";
        definition.description = "";
        definition.author = "";
        definition.version_ = "1.0.0";
    }

    /// Set basic language metadata
    LanguageBuilder meta(string name, string description = "") {
        definition.name = name;
        definition.description = description;
        return this;
    }

    /// Define author and version
    LanguageBuilder version_(string ver, string author = "") {
        definition.version_ = ver;
        definition.author = author;
        return this;
    }

    /// Add a token definition
    LanguageBuilder token(string name, string pattern, string example = "", string description = "") {
        TokenDefinition tokenDef;
        tokenDef.name = name;
        tokenDef.pattern = pattern;
        tokenDef.example = example;
        tokenDef.description = description;

        definition.tokens ~= tokenDef;
        tokenRegistry[name] = tokenDef;
        return this;
    }

    /// Add multiple tokens
    LanguageBuilder tokens(TokenDefinition[] tokens) {
        foreach(token; tokens) {
            definition.tokens ~= token;
            tokenRegistry[token.name] = token;
        }
        return this;
    }

    /// Add common programming language tokens
    LanguageBuilder addCommonTokens() {
        return tokens([
            TokenDefinition("IDENTIFIER", "[a-zA-Z_][a-zA-Z0-9_]*", "variableName", "Variable and function names"),
            TokenDefinition("NUMBER", "[0-9]+(\\.[0-9]+)?", "42", "Numeric literals"),
            TokenDefinition("STRING", "\"([^\"\\\\]|\\\\.)*\"", "\"hello\"", "String literals"),
            TokenDefinition("COMMENT", "//.*", "// comment", "Line comments"),
            TokenDefinition("COMMENT", "/\\*[\\s\\S]*?\\*/", "/* block comment */", "Block comments"),
            TokenDefinition("WHITESPACE", "\\s+", "", "Whitespace (ignored)"),
            TokenDefinition("OPERATOR", "[+\\-*/=<>!&|^%]+", "+", "Operators"),
            TokenDefinition("DELIMITER", "[,;:(){}[\\]]", "(", "Punctuation and delimiters")
        ]);
    }

    /// Add grammar rule
    LanguageBuilder rule(string pattern, string description = "", string action = "") {
        GrammarRule rule;
        rule.pattern = pattern;
        rule.description = description;
        rule.action = action;

        grammarRules ~= rule;
        definition.grammar ~= rule;
        return this;
    }

    /// Add multiple grammar rules
    LanguageBuilder rules(GrammarRule[] rules) {
        foreach(rule; rules) {
            grammarRules ~= rule;
            definition.grammar ~= rule;
        }
        return this;
    }

    /// Add common programming grammar
    LanguageBuilder addExpressionGrammar() {
        return rules([
            GrammarRule("program -> statements", "Complete program", "evalStatements"),
            GrammarRule("statements -> statement", "Single statement", "evalStatement"),
            GrammarRule("statements -> statement statements", "Multiple statements", "evalStatement(evalStatements)"),
            GrammarRule("statement -> expression ;", "Expression with semicolon", "evalExpression"),
            GrammarRule("expression -> term", "Single term", "evalTerm"),
            GrammarRule("expression -> expression + term", "Addition", "add(evalExpression, evalTerm)"),
            GrammarRule("expression -> expression - term", "Subtraction", "subtract(evalExpression, evalTerm)"),
            GrammarRule("term -> factor", "Single factor", "evalFactor"),
            GrammarRule("term -> term * factor", "Multiplication", "multiply(evalTerm, evalFactor)"),
            GrammarRule("term -> term / factor", "Division", "divide(evalTerm, evalFactor)"),
            GrammarRule("factor -> ( expression )", "Parenthesized expression", "evalExpression"),
            GrammarRule("factor -> IDENTIFIER", "Variable reference", "lookupVariable"),
            GrammarRule("factor -> NUMBER", "Number literal", "parseNumber"),
            GrammarRule("factor -> STRING", "String literal", "parseString"),
            GrammarRule("factor -> function_call", "Function call", "callFunction"),
            GrammarRule("function_call -> IDENTIFIER ( arguments )", "Function with arguments", "callFunction")
        ]);
    }

    /// Add built-in function
    LanguageBuilder builtin(string name, string[] params, string description, string code) {
        BuiltinFunction func;
        func.name = name;
        func.parameters = params;
        func.description = description;
        func.code = code;

        definition.builtins ~= func;
        builtinRegistry[name] = func;
        return this;
    }

    /// Add multiple built-in functions
    LanguageBuilder builtins(BuiltinFunction[] funcs) {
        foreach(func; funcs) {
            definition.builtins ~= func;
            builtinRegistry[func.name] = func;
        }
        return this;
    }

    /// Add common built-in functions
    LanguageBuilder addCommonBuiltins() {
        return builtins([
            BuiltinFunction("print", ["value"], "Print value to output", "printValue(value)"),
            BuiltinFunction("input", [], "Get user input", "readInput()"),
            BuiltinFunction("len", ["array"], "Get array length", "array.length"),
            BuiltinFunction("push", ["array", "item"], "Add item to array", "array.addItem(item)"),
            BuiltinFunction("pop", ["array"], "Remove last item from array", "array.pop()"),
            BuiltinFunction("typeof", ["value"], "Get type of value", "typeOf(value)"),
            BuiltinFunction("sqrt", ["number"], "Square root", "math.sqrt(number)"),
            BuiltinFunction("abs", ["number"], "Absolute value", "math.abs(number)")
        ]);
    }

    /// Configure runtime settings
    LanguageBuilder runtime(bool sandbox = true, int maxTimeSec = 30, int maxMemoryMB = 50) {
        definition.sandboxEnabled = sandbox;
        definition.maxExecutionTime = maxTimeSec;
        definition.maxMemoryMB = maxMemoryMB;
        return this;
    }

    /// Generate language as executable DSL
    string build() {
        if (definition.name.length == 0) {
            throw new Exception("Language name cannot be empty");
        }

        return generateLanguageSpec();
    }

    /// Save language definition to file
    void save(string filename) {
        string spec = build();
        std.file.write(filename, spec);
    }

    /// Load language definition from file
    static LanguageBuilder load(string filename) {
        string content = readText(filename);
        LanguageBuilder builder = new LanguageBuilder();

        // Parse the custom language specification format
        return parseLanguageSpec(content, builder);
    }

    /// Get current definition
    LanguageDefinition getDefinition() {
        return definition;
    }

    private string generateLanguageSpec() {
        string result = "# Language: " ~ definition.name ~ "\n";
        result ~= "# Description: " ~ definition.description ~ "\n";
        result ~= "# Author: " ~ definition.author ~ "\n";
        result ~= "# Version: " ~ definition.version_ ~ "\n\n";

        result ~= "## Token Definitions\n";
        foreach(token; definition.tokens) {
            result ~= "TOKEN " ~ token.name ~ " : " ~ token.pattern;
            if (token.example.length > 0) result ~= "  (example: " ~ token.example ~ ")";
            if (token.description.length > 0) result ~= "  # " ~ token.description;
            result ~= "\n";
        }

        result ~= "\n## Grammar Rules\n";
        foreach(rule; definition.grammar) {
            result ~= rule.pattern;
            if (rule.description.length > 0) result ~= "  # " ~ rule.description;
            if (rule.action.length > 0) result ~= "  -> " ~ rule.action;
            result ~= "\n";
        }

        result ~= "\n## Built-in Functions\n";
        foreach(func; definition.builtins) {
            result ~= "FUNC " ~ func.name ~ "(" ~ func.parameters.join(", ") ~ ")  # " ~ func.description ~ "\n";
            result ~= "    " ~ func.code ~ "\n";
        }

        result ~= "\n## Runtime Configuration\n";
        result ~= "SANDBOX " ~ (definition.sandboxEnabled ? "enabled" : "disabled") ~ "\n";
        result ~= "MAX_TIME " ~ to!string(definition.maxExecutionTime) ~ " seconds\n";
        result ~= "MAX_MEMORY " ~ to!string(definition.maxMemoryMB) ~ " MB\n";

        return result;
    }

    private static LanguageBuilder parseLanguageSpec(string content, LanguageBuilder builder) {
        string[] lines = content.splitLines();
        string currentSection = "";

        foreach(line; lines) {
            line = line.strip();
            if (line.length == 0 || line.startsWith("#")) continue;

            // Section headers
            if (line.startsWith("## ")) {
                currentSection = line[3..$];
                continue;
            }

            if (currentSection == "Token Definitions" && line.startsWith("TOKEN ")) {
                parseTokenDefinition(line, builder);
            } else if (currentSection == "Grammar Rules" && line.length > 0) {
                parseGrammarRule(line, builder);
            } else if (currentSection == "Built-in Functions" && line.startsWith("FUNC ")) {
                parseBuiltinFunction(line, builder);
            } else if (currentSection == "Runtime Configuration") {
                parseRuntimeConfig(line, builder);
            }
        }

        return builder;
    }

    private static void parseTokenDefinition(string line, LanguageBuilder builder) {
        // Format: TOKEN NAME : pattern (example: ...) # description
        auto colonPos = line.indexOf(':');
        if (colonPos < 0) return;

        string name = line[5..colonPos].strip();
        string pattern = line[colonPos + 1..$].strip();

        // Extract example and description
        string example = "";
        string description = "";

        auto examplePos = pattern.indexOf("(example:");
        if (examplePos >= 0) {
            string afterExample = pattern[examplePos + 9..$];
            auto endExample = afterExample.indexOf(')');
            if (endExample >= 0) {
                example = afterExample[1..endExample];
                pattern = pattern[0..examplePos].strip();
            }
        }

        auto descPos = pattern.indexOf('#');
        if (descPos >= 0) {
            description = pattern[descPos + 1..$].strip();
            pattern = pattern[0..descPos].strip();
        }

        builder.token(name, pattern, example, description);
    }

    private static void parseGrammarRule(string line, LanguageBuilder builder) {
        // Format: pattern -> action # description
        auto arrowPos = line.indexOf("->");
        string pattern = line[0..arrowPos].strip();
        string action = "";
        string description = "";

        string afterArrow = line[arrowPos + 2..$];
        auto descPos = afterArrow.indexOf('#');
        if (descPos >= 0) {
            description = afterArrow[descPos + 1..$].strip();
            action = afterArrow[0..descPos].strip();
        } else {
            action = afterArrow.strip();
        }

        builder.rule(pattern, description, action);
    }

    private static void parseBuiltinFunction(string line, LanguageBuilder builder) {
        // Format: FUNC name(params)  # description
        string content = line[5..$];
        auto descPos = content.indexOf("  #");
        string signature;
        string description;

        if (descPos >= 0) {
            signature = content[0..descPos].strip();
            description = content[descPos + 2..$].strip();
        } else {
            signature = content;
            description = "";
        }

        auto parenPos = signature.indexOf('(');
        string name = (parenPos >= 0) ? signature[0..parenPos].strip() : signature;
        string params = "";

        if (parenPos >= 0) {
            string afterParen = signature[parenPos + 1..$];
            auto endParen = afterParen.indexOf(')');
            if (endParen >= 0) {
                params = afterParen[0..endParen].strip();
            }
        }

        string[] paramArray = params.length > 0 ? params.split(',') : new string[0];

        builder.builtin(name, paramArray, description, "");
    }

    private static void parseRuntimeConfig(string line, LanguageBuilder builder) {
        if (line.startsWith("SANDBOX ")) {
            string value = line[8..$].strip();
            bool sandbox = (value == "enabled");
        } else if (line.startsWith("MAX_TIME ")) {
            string value = line[9..$].strip();
            int time = to!int(value.split()[0]);
            builder.runtime(true, time, builder.getDefinition().maxMemoryMB);
        } else if (line.startsWith("MAX_MEMORY ")) {
            string value = line[11..$].strip();
            int memory = to!int(value.split()[0]);
            builder.runtime(true, builder.getDefinition().maxExecutionTime, memory);
        }
    }
}

/// Language template for common patterns
class LanguageTemplate {
    private string name;
    private LanguageBuilder builder;

    this(string name, LanguageBuilder builder) {
        this.name = name;
        this.builder = builder;
    }

    string getName() { return name; }
    LanguageBuilder getBuilder() { return builder; }
}

/// Expression language template
class ExpressionLanguageTemplate : LanguageTemplate {
    this() {
        super("expression", new LanguageBuilder()
            .meta("Expression Language", "Simple mathematical expression language")
            .version_("1.0")
            .addCommonTokens()
            .addExpressionGrammar()
            .builtin("eval", ["expr"], "Evaluate expression string", "evaluateExpression(expr)")
            .builtin("clear", [], "Clear environment", "clearEnvironment()")
            .runtime(true, 30, 10));
    }
}

/// Scripting language template
class ScriptingLanguageTemplate : LanguageTemplate {
    this() {
        super("scripting", new LanguageBuilder()
            .meta("Scripting Language", "General purpose scripting language")
            .version_("1.0")
            .addCommonTokens()
            .rule("program -> statement_list", "Complete program")
            .rule("statement_list -> statement", "Single statement")
            .rule("statement_list -> statement statement_list", "Multiple statements")
            .rule("statement -> if_statement", "If statement")
            .rule("statement -> while_statement", "While loop")
            .rule("statement -> for_statement", "For loop")
            .rule("statement -> function_definition", "Function definition")
            .rule("statement -> variable_assignment", "Variable assignment")
            .rule("statement -> expression ;", "Expression with semicolon")
            .rule("if_statement -> if ( expression ) block", "If statement")
            .rule("while_statement -> while ( expression ) block", "While loop")
            .rule("for_statement -> for ( variable : range ) block", "For loop")
            .rule("function_definition -> function IDENTIFIER ( parameters ) block", "Function")
            .rule("variable_assignment -> let IDENTIFIER = expression ;", "Variable assignment")
            .rule("block -> { statement_list }", "Code block")
            .addCommonBuiltins()
            .builtin("if", ["condition", "thenBlock", "elseBlock"], "Conditional execution", "ifThenElse(condition, thenBlock, elseBlock)")
            .builtin("loop", ["count", "body"], "Loop N times", "loopN(count, body)")
            .builtin("range", ["start", "end"], "Number range", "createRange(start, end)")
            .runtime(true, 60, 100));
    }
}

/// Template registry
class TemplateRegistry {
    private LanguageTemplate[string] templates;

    this() {
        templates["expression"] = new ExpressionLanguageTemplate();
        templates["scripting"] = new ScriptingLanguageTemplate();
    }

    LanguageTemplate getTemplate(string name) {
        return templates.get(name, null);
    }

    string[] listTemplates() {
        string[] names;
        foreach(name, tmpl; templates) {
            names ~= name ~ " - " ~ tmpl.getBuilder().getDefinition().description;
        }
        return names;
    }

    LanguageBuilder createFromTemplate(string name, string languageName) {
        LanguageTemplate tmpl = getTemplate(name);
        if (tmpl is null) {
            throw new Exception("Unknown template: " ~ name);
        }

        LanguageBuilder builder = tmpl.getBuilder();
        builder.meta(languageName, "Created from " ~ name ~ " template");

        return builder;
    }
}
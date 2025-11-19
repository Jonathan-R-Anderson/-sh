module shell_runtime;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.ascii : isWhite;
import std.file : readText;

/// Functional expression types
enum ExprType {
    Atom,
    List,
    Symbol,
    Number,
    String,
    Function,
    Native,
    Macro
}

/// Functional expression
struct Expression {
    ExprType type;
    string value;
    Expression[] list;
    int line = 1;

    this(ExprType type, string value = "", Expression[] list = []) {
        this.type = type;
        this.value = value;
        this.list = list;
    }

    bool isAtom() { return type == ExprType.Atom; }
    bool isList() { return type == ExprType.List; }
    bool isSymbol() { return type == ExprType.Symbol; }
    bool isNumber() { return type == ExprType.Number; }
    bool isString() { return type == ExprType.String; }
    bool isFunction() { return type == ExprType.Function; }
    bool isNative() { return type == ExprType.Native; }

    string toString() {
        switch (type) {
            case ExprType.Atom:
            case ExprType.Symbol:
            case ExprType.Number:
            case ExprType.String:
            case ExprType.Function:
                return value;
            case ExprType.List:
                string result = "(";
                foreach(i, expr; list) {
                    if (i > 0) result ~= " ";
                    result ~= expr.toString();
                }
                result ~= ")";
                return result;
            case ExprType.Native:
                return "<native:" ~ value ~ ">";
            default:
                return "<?>";
        }
    }
}

/// Environment for variable binding
class Environment {
    private Environment parent;
    private string[string] bindings;

    this(Environment parent = null) {
        this.parent = parent;
    }

    void bind(string name, string value) {
        bindings[name] = value;
    }

    string lookup(string name) {
        if (name in bindings) {
            return bindings[name];
        } else if (parent !is null) {
            return parent.lookup(name);
        }
        return null;
    }

    bool has(string name) {
        return (name in bindings) || (parent !is null && parent.has(name));
    }
}

/// Native function type
alias NativeFunction = Expression delegate(Expression[], Environment);

/// TUI layout definition
struct Layout {
    string type; // "panel", "split", "overlay"
    int x, y, width, height;
    string content;
    Layout[] children;
}

/// TUI widget definition
struct Widget {
    string type; // "text", "button", "input", "list", "table"
    string id;
    string[string] properties;
    Layout layout;
}

/// Functional language interpreter
class FunctionalInterpreter {
    private Environment globalEnv;
    private NativeFunction[string] natives;
    private Layout[] layouts;
    private Widget[string] widgets;

    this() {
        globalEnv = new Environment();
        registerNatives();
    }

    /// Parse string into expressions
    Expression[] parse(string input) {
        string[] tokens = tokenize(input);
        return parseTokens(tokens);
    }

    /// Execute expressions and return result
    Expression eval(Expression[] exprs, Environment env = null) {
        if (env is null) env = globalEnv;

        Expression result = Expression(ExprType.Atom, "null");
        foreach(expr; exprs) {
            result = evalExpression(expr, env);
        }
        return result;
    }

    /// Define TUI layout
    void defineLayout(string name, string type, int x, int y, int w, int h, string content) {
        Layout layout;
        layout.type = type;
        layout.x = x;
        layout.y = y;
        layout.width = w;
        layout.height = h;
        layout.content = content;

        // Store layout definition
        globalEnv.bind("layout:" ~ name, serializeLayout(layout));
        layouts ~= layout;
    }

    /// Define TUI widget
    void defineWidget(string id, string type, string[string] props) {
        Widget widget;
        widget.type = type;
        widget.id = id;
        widget.properties = props;

        widgets[id] = widget;
        globalEnv.bind("widget:" ~ id, serializeWidget(widget));
    }

    /// Generate TUI representation from functional definitions
    string generateTUI() {
        string result = "=== TUI Layout ===\n";

        foreach(layout; layouts) {
            result ~= "Layout: " ~ layout.type ~ " at (" ~
                     to!string(layout.x) ~ "," ~ to!string(layout.y) ~
                     ") size " ~ to!string(layout.width) ~ "x" ~ to!string(layout.height) ~ "\n";
            result ~= "Content: " ~ layout.content ~ "\n";
        }

        result ~= "\n=== Widgets ===\n";
        foreach(id, widget; widgets) {
            result ~= "Widget " ~ id ~ " (" ~ widget.type ~ "): ";
            foreach(key, value; widget.properties) {
                result ~= key ~ "=" ~ value ~ " ";
            }
            result ~= "\n";
        }

        return result;
    }

    private Expression evalExpression(Expression expr, Environment env) {
        switch (expr.type) {
            case ExprType.Atom:
            case ExprType.Number:
            case ExprType.String:
            case ExprType.Function:
                return expr;

            case ExprType.Symbol:
                string value = env.lookup(expr.value);
                if (value !is null) {
                    return Expression(ExprType.String, value);
                }
                return Expression(ExprType.Atom, expr.value);

            case ExprType.List:
                if (expr.list.length == 0) return expr;

                Expression first = expr.list[0];
                Expression[] args = expr.list[1..$];

                if (first.isSymbol() && (first.value in natives)) {
                    return natives[first.value](args, env);
                }

                // Function call
                return evalFunctionCall(first, args, env);

            default:
                return expr;
        }
    }

    private Expression evalFunctionCall(Expression func, Expression[] args, Environment env) {
        // Simplified function call evaluation
        string funcName = func.value;

        if (funcName == "layout") {
            return Expression(ExprType.Native, "layout");
        }

        if (funcName == "widget") {
            return Expression(ExprType.Native, "widget");
        }

        return Expression(ExprType.List, "", [func] ~ args);
    }

    private string[] tokenize(string input) {
        string[] tokens;
        string current;
        bool inString = false;
        bool escapeNext = false;

        foreach(char ch; input) {
            if (escapeNext) {
                current ~= ch;
                escapeNext = false;
                continue;
            }

            if (ch == '\\' && inString) {
                escapeNext = true;
                continue;
            }

            if (ch == '"') {
                inString = !inString;
                current ~= ch;
                continue;
            }

            if (!inString && (ch == '(' || ch == ')' || isWhite(ch))) {
                if (current.length > 0) {
                    tokens ~= current;
                    current = "";
                }
                if (ch == '(' || ch == ')') {
                    tokens ~= to!string(ch);
                }
            } else {
                current ~= ch;
            }
        }

        if (current.length > 0) {
            tokens ~= current;
        }

        return tokens;
    }

    private Expression[] parseTokens(string[] tokens) {
        Expression[] result;
        int i = 0;

        while (i < tokens.length) {
            Expression expr = parseToken(tokens, i);
            result ~= expr;
            i += getTokenLength(expr);
        }

        return result;
    }

    private Expression parseToken(string[] tokens, int startIndex) {
        string token = tokens[startIndex];

        if (token == "(") {
            Expression[] list;
            int i = startIndex + 1;

            while (i < tokens.length && tokens[i] != ")") {
                Expression expr = parseToken(tokens, i);
                list ~= expr;
                i += getTokenLength(expr);
            }

            return Expression(ExprType.List, "", list);
        } else {
            ExprType type = parseTokenType(token);
            return Expression(type, token);
        }
    }

    private ExprType parseTokenType(string token) {
        if (token == "(" || token == ")") return ExprType.Atom;
        if (token.startsWith("\"") && token.endsWith("\"")) return ExprType.String;

        try {
            to!int(token);
            return ExprType.Number;
        } catch (Exception) {
            try {
                to!double(token);
                return ExprType.Number;
            } catch (Exception) {
                return ExprType.Symbol;
            }
        }
    }

    private int getTokenLength(Expression expr) {
        switch (expr.type) {
            case ExprType.List:
                int length = 2; // for parentheses
                foreach(item; expr.list) {
                    length += getTokenLength(item);
                }
                return length;
            default:
                return 1;
        }
    }

    private void registerNatives() {
        natives["define"] = &nativeDefine;
        natives["layout"] = &nativeLayout;
        natives["widget"] = &nativeWidget;
        natives["render"] = &nativeRender;
        natives["+"] = &nativeAdd;
        natives["-"] = &nativeSubtract;
        natives["*"] = &nativeMultiply;
        natives["/"] = &nativeDivide;
    }

    // Native function implementations
    private Expression nativeDefine(Expression[] args, Environment env) {
        if (args.length >= 2 && args[0].isSymbol()) {
            string value = evalExpression(args[1], env).value;
            env.bind(args[0].value, value);
            return Expression(ExprType.String, "defined: " ~ args[0].value ~ "=" ~ value);
        }
        return Expression(ExprType.String, "define requires name and value");
    }

    private Expression nativeLayout(Expression[] args, Environment env) {
        if (args.length >= 6) {
            string name = evalExpression(args[0], env).value;
            string type = evalExpression(args[1], env).value;
            int x = to!int(evalExpression(args[2], env).value);
            int y = to!int(evalExpression(args[3], env).value);
            int w = to!int(evalExpression(args[4], env).value);
            int h = to!int(evalExpression(args[5], env).value);
            string content = (args.length > 6) ? evalExpression(args[6], env).value : "";

            defineLayout(name, type, x, y, w, h, content);
            return Expression(ExprType.String, "layout defined: " ~ name);
        }
        return Expression(ExprType.String, "layout requires name, type, x, y, width, height");
    }

    private Expression nativeWidget(Expression[] args, Environment env) {
        if (args.length >= 2) {
            string id = evalExpression(args[0], env).value;
            string type = evalExpression(args[1], env).value;
            string[string] props;

            // Parse properties from remaining args
            for (int i = 2; i < args.length; i += 2) {
                if (i + 1 < args.length) {
                    string key = evalExpression(args[i], env).value;
                    string value = evalExpression(args[i + 1], env).value;
                    props[key] = value;
                }
            }

            defineWidget(id, type, props);
            return Expression(ExprType.String, "widget defined: " ~ id ~ " (" ~ type ~ ")");
        }
        return Expression(ExprType.String, "widget requires id and type");
    }

    private Expression nativeRender(Expression[] args, Environment env) {
        return Expression(ExprType.String, generateTUI());
    }

    private Expression nativeAdd(Expression[] args, Environment env) {
        double sum = 0;
        foreach(arg; args) {
            sum += to!double(evalExpression(arg, env).value);
        }
        return Expression(ExprType.Number, to!string(sum));
    }

    private Expression nativeSubtract(Expression[] args, Environment env) {
        if (args.length == 0) return Expression(ExprType.Number, "0");
        if (args.length == 1) return Expression(ExprType.Number, to!string(-to!double(evalExpression(args[0], env).value)));

        double result = to!double(evalExpression(args[0], env).value);
        for (int i = 1; i < args.length; i++) {
            result -= to!double(evalExpression(args[i], env).value);
        }
        return Expression(ExprType.Number, to!string(result));
    }

    private Expression nativeMultiply(Expression[] args, Environment env) {
        double product = 1;
        foreach(arg; args) {
            product *= to!double(evalExpression(arg, env).value);
        }
        return Expression(ExprType.Number, to!string(product));
    }

    private Expression nativeDivide(Expression[] args, Environment env) {
        if (args.length == 0) return Expression(ExprType.Number, "1");
        if (args.length == 1) return Expression(ExprType.Number, to!string(1.0 / to!double(evalExpression(args[0], env).value)));

        double result = to!double(evalExpression(args[0], env).value);
        for (int i = 1; i < args.length; i++) {
            result /= to!double(evalExpression(args[i], env).value);
        }
        return Expression(ExprType.Number, to!string(result));
    }

    private string serializeLayout(Layout layout) {
        return layout.type ~ "(" ~ to!string(layout.x) ~ "," ~ to!string(layout.y) ~
               "," ~ to!string(layout.width) ~ "," ~ to!string(layout.height) ~ ")";
    }

    private string serializeWidget(Widget widget) {
        return widget.type ~ ":" ~ widget.id;
    }

    Environment getGlobalEnvironment() {
        return globalEnv;
    }

    Layout[] getLayouts() {
        return layouts;
    }

    Widget[string] getWidgets() {
        return widgets;
    }
}

/// Create a functional interpreter instance
FunctionalInterpreter createFunctionalInterpreter() {
    return new FunctionalInterpreter();
}
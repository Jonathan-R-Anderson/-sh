module tui_language;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.file : write;
import std.format : format;

/// Simple string repeat function
string repeat(string s, int count) {
    string result = "";
    for (int i = 0; i < count; i++) {
        result ~= s;
    }
    return result;
}
import shell_runtime;

/// TUI Element Types
enum TUIElementType {
    Window,
    Panel,
    Text,
    Button,
    Input,
    List,
    Table,
    Layout,
    Style
}

/// TUI Element - functional representation
struct TUIElement {
    TUIElementType type;
    string id;
    string[string] attributes;
    TUIElement[] children;
    string content;

    this(TUIElementType type, string id = "", string content = "", string[string] attrs = null, TUIElement[] children = null) {
        this.type = type;
        this.id = id;
        this.content = content;
        this.attributes = attrs ? attrs : (string[string]).init;
        this.children = children ? children : [];
    }
}

/// Style definition
struct TUIStyle {
    string name;
    string foreground; // color
    string background; // color
    string[] modifiers; // bold, italic, underline, etc.
    string padding;
    string margin;

    string toString() {
        return "style(" ~ name ~ ", fg=" ~ foreground ~ ", bg=" ~ background ~ ")";
    }
}

/// Layout definition
struct TUILayout {
    string type; // "hbox", "vbox", "grid", "absolute"
    int x, y, width, height;
    string alignment;
    TUIElement[] children;

    this(string type, int x = 0, int y = 0, int w = -1, int h = -1, TUIElement[] children = null) {
        this.type = type;
        this.x = x;
        this.y = y;
        this.width = w;
        this.height = h;
        this.children = children ? children : [];
    }
}

/// Event types
enum TUIEventType {
    Click,
    KeyPress,
    Focus,
    Blur,
    Change
}

/// Event handler
struct TUIEvent {
    TUIEventType type;
    string elementId;
    string[string] data;
    string handler;
}

/// TUI Language Interpreter
class TUILanguage {
    private FunctionalInterpreter interpreter;
    private TUIElement[string] elements;
    private TUIStyle[string] styles;
    private TUILayout[] layouts;
    private TUIEvent[] events;

    this() {
        interpreter = new FunctionalInterpreter();
        registerTUIBuiltin();
    }

    /// Parse TUI definition string
    TUIElement parse(string input) {
        Expression[] exprs = interpreter.parse(input);
        Expression result = interpreter.eval(exprs);

        if (result.isList() && result.list.length > 0) {
            return parseElement(result.list[0]);
        }
        return TUIElement(TUIElementType.Window);
    }

    /// Execute TUI definition string
    void execute(string input) {
        Expression[] exprs = interpreter.parse(input);
        interpreter.eval(exprs);

        // Extract elements, layouts, and styles from environment
        extractFromEnvironment();
    }

    /// Create TUI element from functional expression
    TUIElement parseElement(Expression expr) {
        if (expr.isSymbol()) {
            string symbol = expr.value;

            switch (symbol) {
                case "window":    return TUIElement(TUIElementType.Window);
                case "panel":     return TUIElement(TUIElementType.Panel);
                case "text":      return TUIElement(TUIElementType.Text);
                case "button":    return TUIElement(TUIElementType.Button);
                case "input":     return TUIElement(TUIElementType.Input);
                case "list":      return TUIElement(TUIElementType.List);
                case "table":     return TUIElement(TUIElementType.Table);
                case "layout":    return TUIElement(TUIElementType.Layout);
                default:          return TUIElement(TUIElementType.Text, "", symbol);
            }
        }

        if (expr.isList() && expr.list.length > 0) {
            string firstSymbol = expr.list[0].isSymbol() ? expr.list[0].value : "";

            switch (firstSymbol) {
                case "element":
                    return createElementFromList(expr.list[1..$]);
                case "window":
                    return TUIElement(TUIElementType.Window, extractAttribute(expr.list, "id"), extractAttribute(expr.list, "content"), extractAttributes(expr.list));
                case "panel":
                    return TUIElement(TUIElementType.Panel, extractAttribute(expr.list, "id"), extractAttribute(expr.list, "content"), extractAttributes(expr.list), parseChildren(expr.list));
                case "text":
                    return TUIElement(TUIElementType.Text, extractAttribute(expr.list, "id"), extractAttribute(expr.list, "content"), extractAttributes(expr.list));
                case "button":
                    return TUIElement(TUIElementType.Button, extractAttribute(expr.list, "id"), extractAttribute(expr.list, "content"), extractAttributes(expr.list));
                case "input":
                    return TUIElement(TUIElementType.Input, extractAttribute(expr.list, "id"), extractAttribute(expr.list, "placeholder"), extractAttributes(expr.list));
                case "list":
                    return TUIElement(TUIElementType.List, extractAttribute(expr.list, "id"), "", extractAttributes(expr.list), parseChildren(expr.list));
                case "table":
                    return TUIElement(TUIElementType.Table, extractAttribute(expr.list, "id"), "", extractAttributes(expr.list), parseChildren(expr.list));
                case "style":
                    createStyle(expr.list[1..$]);
                    break;
                case "layout":
                    createLayout(expr.list[1..$]);
                    break;
                case "on":
                    createEvent(expr.list[1..$]);
                    break;
                default:
                    return TUIElement(TUIElementType.Text, "", firstSymbol, extractAttributes(expr.list));
            }
        }

        return TUIElement(TUIElementType.Text);
    }

    private TUIElement[] parseChildren(Expression[] exprs) {
        TUIElement[] children;

        foreach(expr; exprs) {
            if (expr.type == ExprType.List && expr.list.length > 0) {
                TUIElement child = parseElement(expr);
                if (child.type != TUIElementType.Style) { // Skip style elements
                    children ~= child;
                }
            }
        }

        return children;
    }

    private string extractAttribute(Expression[] exprs, string attrName) {
        foreach(expr; exprs) {
            if (expr.isList() && expr.list.length == 2 && expr.list[0].isSymbol()) {
                if (expr.list[0].value == attrName) {
                    return evalExpression(expr.list[1]).value;
                }
            }
        }
        return "";
    }

    private string[string] extractAttributes(Expression[] exprs) {
        string[string] attrs;

        foreach(expr; exprs) {
            if (expr.isList() && expr.list.length == 2 && expr.list[0].isSymbol()) {
                attrs[expr.list[0].value] = evalExpression(expr.list[1]).value;
            }
        }

        return attrs;
    }

    private TUIElement createElementFromList(Expression[] exprs) {
        if (exprs.length > 0) {
            return parseElement(exprs[0]);
        }
        return TUIElement(TUIElementType.Text);
    }

    private Expression evalExpression(Expression expr) {
        // For now, just return the expression value
        // In a real implementation, this would evaluate properly
        return expr;
    }

    private void createStyle(Expression[] exprs) {
        if (exprs.length < 2) return;

        string name = evalExpression(exprs[0]).value;
        string[string] attrs = extractAttributes(exprs[1..$]);

        TUIStyle style;
        style.name = name;
        style.foreground = attrs.get("fg", "default");
        style.background = attrs.get("bg", "default");

        if ("bold" in attrs) style.modifiers ~= "bold";
        if ("italic" in attrs) style.modifiers ~= "italic";
        if ("underline" in attrs) style.modifiers ~= "underline";

        style.padding = attrs.get("padding", "0");
        style.margin = attrs.get("margin", "0");

        styles[name] = style;
    }

    private void createLayout(Expression[] exprs) {
        if (exprs.length < 1) return;

        string type = evalExpression(exprs[0]).value;
        string[string] attrs = extractAttributes(exprs[1..$]);

        TUILayout layout;
        layout.type = type;
        layout.x = to!int(attrs.get("x", "0"));
        layout.y = to!int(attrs.get("y", "0"));
        layout.width = to!int(attrs.get("width", "-1"));
        layout.height = to!int(attrs.get("height", "-1"));

        layouts ~= layout;
    }

    private void createEvent(Expression[] exprs) {
        if (exprs.length < 2) return;

        string eventType = evalExpression(exprs[0]).value;
        string handler = evalExpression(exprs[1]).value;
        string elementId = extractAttribute(exprs, "id");

        TUIEvent event;
        event.type = parseEventType(eventType);
        event.elementId = elementId;
        event.handler = handler;
        event.data = extractAttributes(exprs);

        events ~= event;
    }

    private TUIEventType parseEventType(string eventType) {
        switch (eventType) {
            case "click": return TUIEventType.Click;
            case "keypress": return TUIEventType.KeyPress;
            case "focus": return TUIEventType.Focus;
            case "blur": return TUIEventType.Blur;
            case "change": return TUIEventType.Change;
            default: return TUIEventType.Click;
        }
    }

    private void extractFromEnvironment() {
        // This would extract elements, layouts, styles, and events
        // from the interpreter's environment
        // For now, it's a placeholder implementation
    }

    /// Register TUI-specific built-in functions
    private void registerTUIBuiltin() {
        // These would be registered with the interpreter
        // For now, it's a placeholder
    }

    /// Generate TUI as terminal output
    string renderTerminal(TUIElement rootElement) {
        string result = generateTerminalOutput(rootElement, 0);
        return result;
    }

    private string generateTerminalOutput(TUIElement element, int indent) {
        string indentStr = repeat("    ", indent);

        string result = indentStr;

        switch (element.type) {
            case TUIElementType.Window:
                result = "┌─ Window" ~ (element.id.length > 0 ? ": " ~ element.id : "") ~ " ─";
                result ~= "\n" ~ generateWindowContent(element, indent + 1);
                result ~= "\n" ~ indentStr ~ "└───────────────────────────────────────────┘";
                break;

            case TUIElementType.Panel:
                result = "┌─ Panel" ~ (element.id.length > 0 ? ": " ~ element.id : "") ~ " ─";
                result ~= "\n" ~ generatePanelContent(element, indent + 1);
                result ~= "\n" ~ indentStr ~ "└───────────────────────────────────────────┘";
                break;

            case TUIElementType.Text:
                result = "Text: " ~ (element.id.length > 0 ? "[" ~ element.id ~ "] " : "") ~ element.content;
                if (element.attributes.length > 0) {
                    result ~= " " ~ attributesToString(element.attributes);
                }
                break;

            case TUIElementType.Button:
                result = "Button: " ~ (element.id.length > 0 ? "[" ~ element.id ~ "] " : "") ~ element.content;
                if (element.attributes.length > 0) {
                    result ~= " " ~ attributesToString(element.attributes);
                }
                break;

            case TUIElementType.Input:
                result = "Input: " ~ (element.id.length > 0 ? "[" ~ element.id ~ "] " : "");
                string placeholder = element.attributes.get("placeholder", "");
                if (placeholder.length > 0) result ~= placeholder ~ " ";
                result ~= "│";
                break;

            case TUIElementType.List:
                result = "List: " ~ (element.id.length > 0 ? "[" ~ element.id ~ "] " : "");
                result ~= "(" ~ to!string(element.children.length) ~ " items)";
                if (element.attributes.length > 0) {
                    result ~= " " ~ attributesToString(element.attributes);
                }
                break;

            case TUIElementType.Table:
                result = "Table: " ~ (element.id.length > 0 ? "[" ~ element.id ~ "] " : "");
                result ~= "(" ~ to!string(element.children.length) ~ " cells)";
                if (element.attributes.length > 0) {
                    result ~= " " ~ attributesToString(element.attributes);
                }
                break;

            default:
                result = "Unknown element type: " ~ to!string(element.type);
                break;
        }

        // Render children
        if (element.children.length > 0) {
            result ~= "\n";
            foreach(child; element.children) {
                result ~= generateTerminalOutput(child, indent + 1);
            }
        }

        return result;
    }

    private string generateWindowContent(TUIElement element, int indent) {
        return "Content: " ~ (element.content.length > 0 ? element.content : "[empty]");
    }

    private string generatePanelContent(TUIElement element, int indent) {
        string result = "Content: " ~ (element.content.length > 0 ? element.content : "[empty]");

        if (element.children.length > 0) {
            result ~= " (contains " ~ to!string(element.children.length) ~ " children)";
        }

        return result;
    }

    private string attributesToString(string[string] attrs) {
        string[] pairs;

        foreach(key, value; attrs) {
            pairs ~= key ~ "=" ~ value;
        }

        return "[" ~ pairs.join(", ") ~ "]";
    }

    /// Generate functional TUI definition
    string generateFunctionalDefinition(TUIElement rootElement) {
        string result = "(tui\n";
        result ~= generateFunctionalElement(rootElement, 1);
        result ~= ")";
        return result;
    }

    private string generateFunctionalElement(TUIElement element, int indent) {
        string indentStr = repeat("  ", indent);

        string result = indentStr ~ "(element " ~ to!string(element.type);

        if (element.id.length > 0) {
            result ~= " id:" ~ element.id;
        }

        if (element.content.length > 0) {
            result ~= " content:" ~ "\"" ~ element.content ~ "\"";
        }

        // Add attributes
        string[] attrs;
        foreach(key, value; element.attributes) {
            attrs ~= key ~ ":" ~ value;
        }
        if (attrs.length > 0) {
            result ~= " {" ~ attrs.join(" ") ~ "}";
        }

        // Add children
        if (element.children.length > 0) {
            result ~= "\n";
            foreach(child; element.children) {
                result ~= generateFunctionalElement(child, indent + 1) ~ "\n";
            }
        }

        result ~= indentStr ~ ")";

        return result;
    }

    /// Get all elements
    TUIElement[] getElements() {
        TUIElement[] result;

        foreach(id, element; elements) {
            result ~= element;
            result ~= getAllChildren(element);
        }

        return result;
    }

    private TUIElement[] getAllChildren(TUIElement element) {
        TUIElement[] result;

        foreach(child; element.children) {
            result ~= child;
            result ~= getAllChildren(child);
        }

        return result;
    }

    /// Get styles
    TUIStyle[string] getStyles() {
        return styles;
    }

    /// Get layouts
    TUILayout[] getLayouts() {
        return layouts;
    }

    /// Get events
    TUIEvent[] getEvents() {
        return events;
    }

    /// Save TUI definition to file
    void save(string filename) {
        string definition = generateFunctionalDefinition(
            TUIElement(TUIElementType.Window, "main", "", null, getElements())
        );

        write(filename, definition);
    }
}


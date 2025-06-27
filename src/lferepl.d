module lferepl;

import dlexer;
import dparser;
import std.regex : regex;
import std.stdio;
import std.string;
import std.ascii : isDigit;
import std.algorithm;
import std.conv : to;
import std.file : readText;

struct Expr {
    bool isList;
    string atom;
    Expr[] list;
    bool isAtom;
    bool isTuple;
    bool isMap;
}

enum ValueKind { Number, Atom, Tuple, List, Map }

struct Value {
    ValueKind kind;
    double number;
    string atom;
    Value[] tuple;
    Value[] list;
    Value[string] map;
}

Value num(double n) { return Value(ValueKind.Number, n, "", null, null, null); }
Value atomVal(string a) { return Value(ValueKind.Atom, 0, a, null, null, null); }
Value tupleVal(Value[] t) { return Value(ValueKind.Tuple, 0, "", t, null, null); }
Value listVal(Value[] l) { return Value(ValueKind.List, 0, "", null, l, null); }
Value mapVal(Value[string] m) { return Value(ValueKind.Map, 0, "", null, null, m); }

string valueToString(Value v) {
    final switch(v.kind) {
        case ValueKind.Number:
            return to!string(v.number);
        case ValueKind.Atom:
            return "'" ~ v.atom;
        case ValueKind.Tuple:
            string s;
            foreach(elem; v.tuple) {
                s ~= valueToString(elem) ~ " ";
            }
            if(s.length > 0) s = s[0 .. $-1];
            return "#(" ~ s ~ ")";
        case ValueKind.List:
            string ls;
            foreach(elem; v.list) {
                ls ~= valueToString(elem) ~ " ";
            }
            if(ls.length > 0) ls = ls[0 .. $-1];
            return "(" ~ ls ~ ")";
        case ValueKind.Map:
            string ms;
            foreach(k, val; v.map) {
                ms ~= k ~ " " ~ valueToString(val) ~ " ";
            }
            if(ms.length > 0) ms = ms[0 .. $-1];
            return "#M(" ~ ms ~ ")";
    }
    return "";
}

class LfeParser : Parser {
    this(Token[] toks) {
        super(toks);
    }

    Expr parseExpr() {
        if (peek("QUOTE")) {
            consume("QUOTE");
            auto q = parseExpr();
            Expr[] elems = [Expr(false, "quote", null, false, false, false), q];
            return Expr(true, "", elems, false, false, false);
        } else if (peek("HASHMAP")) {
            consume("HASHMAP");
            Expr[] elems;
            while (!peek("RPAREN")) {
                elems ~= parseExpr();
                if (pos >= tokens.length) break;
            }
            consume("RPAREN");
            return Expr(true, "", elems, false, false, true);
        } else if (peek("HASHLPAREN")) {
            consume("HASHLPAREN");
            Expr[] elems;
            while (!peek("RPAREN")) {
                elems ~= parseExpr();
                if (pos >= tokens.length) break;
            }
            consume("RPAREN");
            return Expr(true, "", elems, false, true, false);
        } else if (peek("LPAREN") || peek("LBRACK")) {
            bool br = peek("LBRACK");
            if(br) consume("LBRACK"); else consume("LPAREN");
            Expr[] elems;
            while (!(br ? peek("RBRACK") : peek("RPAREN"))) {
                elems ~= parseExpr();
                if (pos >= tokens.length) break;
            }
            if(br) consume("RBRACK"); else consume("RPAREN");
            return Expr(true, "", elems, false, false, false);
        } else if (peek("NUMBER")) {
            auto t = consume("NUMBER");
            return Expr(false, t.value, null, false, false, false);
        } else if (peek("STRING")) {
            auto t = consume("STRING");
            return Expr(false, t.value, null, false, false, false);
        } else if (peek("ATOM")) {
            auto t = consume("ATOM");
            return Expr(false, t.value[1 .. $], null, true, false, false);
        } else if (peek("SYMBOL")) {
            auto t = consume("SYMBOL");
            return Expr(false, t.value, null, false, false, false);
        }
        throw new Exception("Unexpected token");
    }
}

struct FunctionClause {
    Expr[] params;
    Expr body;
}

Value[string] variables;
FunctionClause[][string] functions;

bool isNumber(string s) {
    bool seenDot = false;
    if(s.length == 0) return false;
    foreach(ch; s) {
        if(ch == '.') {
            if(seenDot) return false;
            seenDot = true;
        } else if(!ch.isDigit) {
            return false;
        }
    }
    return true;
}

Value evalExpr(Expr e);
Value quoteValue(Expr e);

immutable Rule[] rules = [
    Rule("HASHMAP", regex("#M\\(")),
    Rule("HASHLPAREN", regex("#\\(")),
    Rule("LPAREN", regex("\\(")),
    Rule("LBRACK", regex("\\[")),
    Rule("RBRACK", regex("\\]")),
    Rule("RPAREN", regex("\\)")),
    Rule("STRING", regex("\"[^\"]*\"")),
    Rule("NUMBER", regex("[0-9]+(\\.[0-9]+)?")),
    Rule("ATOM", regex("'[a-zA-Z_+*/:<>=!?-][a-zA-Z0-9_+*/:<>=!?-]*")),
    Rule("QUOTE", regex("'")),
    Rule("SYMBOL", regex("[a-zA-Z_+*/:<>=!?-][a-zA-Z0-9_+*/:<>=!?-]*")),
    Rule("WS", regex("\\s+"))
];

Token[] lexInput(string input) {
    auto lex = new Lexer(rules);
    auto toks = lex.tokenize(input);
    return toks.filter!(t => t.type != "WS").array;
}

Expr parseString(string code) {
    auto toks = lexInput(code);
    auto parser = new LfeParser(toks);
    return parser.parseExpr();
}

void loadFile(string path) {
    auto text = readText(path);
    auto ast = parseString(text);
    evalExpr(ast);
    if(ast.isList && ast.list.length > 0 && ast.list[0].atom == "defmodule") {
        auto modName = ast.list[1].atom;
        writeln("#(module ", modName, ")");
    } else {
        writeln("ok");
    }
}

bool matchPattern(Value val, Expr pat, ref string[] varNames, ref Value[string] saved) {
    if(pat.isAtom) {
        return val.kind == ValueKind.Atom && val.atom == pat.atom;
    }
    if(pat.isTuple || (pat.isList && pat.list.length > 0 && !pat.list[0].isList && pat.list[0].atom == "tuple")) {
        auto elems = pat.isTuple ? pat.list : pat.list[1 .. $];
        if(val.kind != ValueKind.Tuple || val.tuple.length != elems.length) return false;
        foreach(i, pe; elems) {
            if(!matchPattern(val.tuple[i], pe, varNames, saved)) return false;
        }
        return true;
    }
    if(pat.isMap || (pat.isList && pat.list.length > 0 && !pat.list[0].isList && pat.list[0].atom == "map")) {
        auto elems = pat.isMap ? pat.list : pat.list[1 .. $];
        if(val.kind != ValueKind.Map) return false;
        for(size_t i = 0; i + 1 < elems.length; i += 2) {
            auto keyStr = valueToString(evalExpr(elems[i]));
            if(!(keyStr in val.map)) return false;
            if(!matchPattern(val.map[keyStr], elems[i+1], varNames, saved)) return false;
        }
        return true;
    }
    if(pat.isList) {
        if(pat.list.length == 0) {
            return val.kind == ValueKind.List && val.list.length == 0;
        }
        if(pat.list.length == 3 && !pat.list[0].isList && pat.list[0].atom == "cons") {
            if(val.kind != ValueKind.List || val.list.length == 0) return false;
            auto headVal = val.list[0];
            auto tailVal = listVal(val.list[1 .. $]);
            if(!matchPattern(headVal, pat.list[1], varNames, saved)) return false;
            if(!matchPattern(tailVal, pat.list[2], varNames, saved)) return false;
            return true;
        }
    }
    if(!pat.isList) {
        auto name = pat.atom;
        if(name in variables) saved[name] = variables[name];
        variables[name] = val;
        varNames ~= name;
        return true;
    }
    return false;
}

Value quoteValue(Expr e) {
    if(!e.isList) {
        if(e.isAtom) return atomVal(e.atom);
        if(isNumber(e.atom)) return num(to!double(e.atom));
        return atomVal(e.atom);
    }
    if(e.isTuple) {
        Value[] elems; foreach(sub; e.list) elems ~= quoteValue(sub);
        return tupleVal(elems);
    }
    if(e.isMap) {
        Value[string] m;
        for(size_t i = 0; i + 1 < e.list.length; i += 2) {
            auto k = quoteValue(e.list[i]);
            auto v = quoteValue(e.list[i+1]);
            m[valueToString(k)] = v;
        }
        return mapVal(m);
    }
    Value[] els; foreach(sub; e.list) els ~= quoteValue(sub);
    return listVal(els);
}

Value evalList(Expr e) {
    if(e.list.length == 0) return listVal([]);
    auto head = e.list[0].atom;
    if(head == "+") {
        double result = 0;
        foreach(arg; e.list[1 .. $]) result += evalExpr(arg).number;
        return num(result);
    } else if(head == "-") {
        double result = evalExpr(e.list[1]).number;
        foreach(arg; e.list[2 .. $]) result -= evalExpr(arg).number;
        return num(result);
    } else if(head == "*") {
        double result = 1;
        foreach(arg; e.list[1 .. $]) result *= evalExpr(arg).number;
        return num(result);
    } else if(head == "/") {
        double result = evalExpr(e.list[1]).number;
        foreach(arg; e.list[2 .. $]) result /= evalExpr(arg).number;
        return num(result);
    } else if(head == "tuple") {
        Value[] els;
        foreach(arg; e.list[1 .. $]) els ~= evalExpr(arg);
        return tupleVal(els);
    } else if(head == "list") {
        Value[] els;
        foreach(arg; e.list[1 .. $]) els ~= evalExpr(arg);
        return listVal(els);
    } else if(head == "cons") {
        auto first = evalExpr(e.list[1]);
        auto rest = evalExpr(e.list[2]);
        Value[] combined = [first];
        if(rest.kind == ValueKind.List)
            combined ~= rest.list;
        return listVal(combined);
    } else if(head == "quote") {
        auto q = e.list[1];
        return quoteValue(q);
    } else if(head == "set") {
        auto name = e.list[1].atom;
        auto val = evalExpr(e.list[2]);
        variables[name] = val;
        return val;
    } else if(head == "map") {
        Value[string] m;
        for(size_t i = 1; i + 1 < e.list.length; i += 2) {
            auto k = evalExpr(e.list[i]);
            auto v = evalExpr(e.list[i+1]);
            m[valueToString(k)] = v;
        }
        return mapVal(m);
    } else if(head == "map-update") {
        auto base = evalExpr(e.list[1]);
        Value[string] m = base.kind == ValueKind.Map ? base.map.dup : Value[string].init;
        for(size_t i = 2; i + 1 < e.list.length; i += 2) {
            auto k = evalExpr(e.list[i]);
            auto v = evalExpr(e.list[i+1]);
            m[valueToString(k)] = v;
        }
        return mapVal(m);
    } else if(head == "proplists:get_value") {
        auto key = evalExpr(e.list[1]);
        auto plist = evalExpr(e.list[2]);
        Value defval = e.list.length > 3 ? evalExpr(e.list[3]) : atomVal("undefined");
        if(plist.kind != ValueKind.List) return defval;
        auto kstr = valueToString(key);
        foreach(item; plist.list) {
            if(item.kind == ValueKind.Tuple && item.tuple.length >= 2) {
                if(valueToString(item.tuple[0]) == kstr) return item.tuple[1];
            }
        }
        return defval;
    } else if(head == "defun") {
        auto name = e.list[1].atom;
        FunctionClause[] clauses;
        if(e.list.length > 4 || (e.list[2].isList && e.list[2].list.length == 2 && e.list[2].list[0].isList)) {
            foreach(cl; e.list[2 .. $]) {
                auto params = cl.list[0].list;
                auto body = cl.list[1];
                clauses ~= FunctionClause(params, body);
            }
        } else {
            auto params = e.list[2].list;
            auto body = e.list[3];
            clauses ~= FunctionClause(params, body);
        }
        functions[name] = clauses;
        return num(0);
    } else if(head == "defmodule") {
        auto modName = e.list[1].atom;
        foreach(expr; e.list[2 .. $]) {
            if(expr.isList && expr.list.length > 0 && expr.list[0].atom == "defun") {
                auto fname = expr.list[1].atom;
                FunctionClause[] clauses;
                if(expr.list.length > 4 || (expr.list[2].isList && expr.list[2].list.length == 2 && expr.list[2].list[0].isList)) {
                    foreach(cl; expr.list[2 .. $]) {
                        auto params = cl.list[0].list;
                        auto body = cl.list[1];
                        clauses ~= FunctionClause(params, body);
                    }
                } else {
                    auto params = expr.list[2].list;
                    auto body = expr.list[3];
                    clauses ~= FunctionClause(params, body);
                }
                functions[modName ~ ":" ~ fname] = clauses;
            }
        }
        return num(0);
    } else if(head == "c") {
        auto fexpr = e.list[1];
        auto path = fexpr.atom;
        if(path.length >= 2 && path[0] == '"' && path[$-1] == '"')
            path = path[1 .. $-1];
        loadFile(path);
        return num(0);
    } else if(head == "exit") {
        // signal to caller
        throw new Exception("__exit__");
    } else if(auto fn = head in functions) {
        auto clauses = *fn;
        auto args = e.list[1 .. $];
        foreach(clause; clauses) {
            if(clause.params.length != args.length) continue;
            bool match = true;
            string[] varNames;
            Value[string] saved;
            Value[] argVals;
            foreach(a; args) argVals ~= evalExpr(a);
            foreach(i, pexp; clause.params) {
                auto val = argVals[i];
                if(!matchPattern(val, pexp, varNames, saved)) { match = false; break; }
            }
            if(match) {
                auto result = evalExpr(clause.body);
                foreach(k,v; saved) variables[k] = v;
                foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                return result;
            } else {
                foreach(k,v; saved) variables[k] = v;
                foreach(n; varNames) if(!(n in saved)) variables.remove(n);
            }
        }
        return num(0);
    }
    return num(0);
}

Value evalExpr(Expr e) {
    if(!e.isList) {
        if(e.isAtom) return atomVal(e.atom);
        if(isNumber(e.atom)) return num(to!double(e.atom));
        if(auto v = e.atom in variables) return *v;
        return num(0);
    }
    if(e.isTuple) {
        Value[] elems;
        foreach(sub; e.list) elems ~= evalExpr(sub);
        return tupleVal(elems);
    }
    if(e.isMap) {
        Value[string] m;
        for(size_t i = 0; i + 1 < e.list.length; i += 2) {
            auto k = evalExpr(e.list[i]);
            auto v = evalExpr(e.list[i+1]);
            m[valueToString(k)] = v;
        }
        return mapVal(m);
    }
    return evalList(e);
}

void repl() {
    writeln("LFE REPL -- type (exit) to quit");
    auto lex = new Lexer(rules);
    for(;;) {
        write("lfe> ");
        auto line = readln();
        if(line is null) break;
        line = line.strip;
        if(line.length == 0) continue;
        auto toks = lex.tokenize(line);
        toks = toks.filter!(t => t.type != "WS").array;
        auto parser = new LfeParser(toks);
        Expr ast;
        try {
            ast = parser.parseExpr();
            auto result = evalExpr(ast);
            writeln(valueToString(result));
        } catch(Exception e) {
            if(e.msg == "__exit__") break;
            writeln("Error: ", e.msg);
        }
    }
}

void main() {
    repl();
}


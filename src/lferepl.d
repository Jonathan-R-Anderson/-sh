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
import std.parallelism;

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

string formatValue(Value v) {
    final switch(v.kind) {
        case ValueKind.Number:
            return to!string(v.number);
        case ValueKind.Atom:
            return v.atom;
        case ValueKind.Tuple:
            string s;
            foreach(elem; v.tuple) {
                s ~= formatValue(elem) ~ " ";
            }
            if(s.length > 0) s = s[0 .. $-1];
            return "#(" ~ s ~ ")";
        case ValueKind.List:
            string ls;
            foreach(elem; v.list) {
                ls ~= formatValue(elem) ~ " ";
            }
            if(ls.length > 0) ls = ls[0 .. $-1];
            return "(" ~ ls ~ ")";
        case ValueKind.Map:
            string ms;
            foreach(k, val; v.map) {
                ms ~= k ~ " " ~ formatValue(val) ~ " ";
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
    Expr guard;
    bool hasGuard;
}

Value[string] variables;
FunctionClause[][string] functions;
string[][string] moduleFunctions;
size_t pidCounter;

immutable string[] builtinModules = [
    "application", "application_controller", "application_master",
    "beam_lib", "binary", "c", "code", "code_server",
    "edlin", "edlin_expand", "epp", "erl_distribution", "erl_eval",
    "erl_parse", "erl_prim_loader", "erl_scan", "erlang", "error_handler",
    "error_logger", "error_logger_tty_h", "erts_internal", "ets",
    "file", "file_io_server", "file_server", "filename", "gb_sets",
    "gb_trees", "gen", "gen_event", "gen_server", "global",
    "global_group", "group", "heart", "hipe_unified_loader", "inet",
    "inet_config", "inet_db", "inet_parse", "inet_udp", "init", "io",
    "io_lib", "io_lib_format", "kernel", "kernel_config", "lfe_env",
    "lfe_eval", "lfe_init", "lfe_io", "lfe_shell", "lists",
    "net_kernel", "orddict", "os", "otp_ring0", "prim_eval",
    "prim_file", "prim_inet", "prim_zip", "proc_lib", "proplists",
    "ram_file", "rpc", "standard_error", "supervisor",
    "supervisor_bridge", "sys", "unicode", "user_drv", "user_sup",
    "zlib"
];

immutable string[][string] builtinModuleFunctions = [
    "gb_trees" : [
        "add/2", "add_element/2", "balance/1", "del_element/2",
        "delete/2", "delete_any/2", "difference/2", "empty/0",
        "filter/2", "fold/3", "from_list/1", "from_ordset/1",
        "insert/2", "intersection/1", "intersection/2",
        "is_disjoint/2", "is_element/2", "is_empty/1",
        "is_member/2", "is_set/1", "is_subset/2", "iterator/1",
        "largest/1", "module_info/0", "module_info/1", "new/0",
        "next/1", "singleton/1", "size/1", "smallest/1",
        "subtract/2", "take_largest/1", "take_smallest/1",
        "to_list/1", "union/1", "union/2"
    ]
];

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

void showCompletions(string prefix) {
    if(prefix.indexOf(":") == -1) {
        string[] mods;
        foreach(m; builtinModules) if(m.startsWith(prefix)) mods ~= m;
        foreach(m; moduleFunctions.keys) if(m.startsWith(prefix)) mods ~= m;
        mods.sort;
        foreach(m; mods) write(m ~ "    ");
        writeln();
    } else {
        auto parts = prefix.split(":");
        auto mod = parts[0];
        auto funPref = parts.length > 1 ? parts[1] : "";
        string[] funcs;
        if(auto arr = mod in builtinModuleFunctions)
            foreach(f; *arr) if(f.startsWith(funPref)) funcs ~= f;
        if(auto arr2 = mod in moduleFunctions)
            foreach(f; *arr2) if(f.startsWith(funPref)) funcs ~= f;
        funcs.sort;
        foreach(f; funcs) write(f ~ "    ");
        writeln();
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

bool isTruthy(Value v) {
    if(v.kind == ValueKind.Number) return v.number != 0;
    if(v.kind == ValueKind.Atom) return v.atom != "false";
    return true;
}

bool valuesEqual(Value a, Value b) {
    if(a.kind != b.kind) return false;
    final switch(a.kind) {
        case ValueKind.Number:
            return a.number == b.number;
        case ValueKind.Atom:
            return a.atom == b.atom;
        case ValueKind.Tuple:
            if(a.tuple.length != b.tuple.length) return false;
            foreach(i, av; a.tuple)
                if(!valuesEqual(av, b.tuple[i])) return false;
            return true;
        case ValueKind.List:
            if(a.list.length != b.list.length) return false;
            foreach(i, av; a.list)
                if(!valuesEqual(av, b.list[i])) return false;
            return true;
        case ValueKind.Map:
            if(a.map.length != b.map.length) return false;
            foreach(k, v; a.map) {
                if(!(k in b.map)) return false;
                if(!valuesEqual(v, b.map[k])) return false;
            }
            return true;
    }
    return false;
}

Value callFunctionDirect(string name, Value[] argVals) {
    if(auto fn = name in functions) {
        auto clauses = *fn;
        foreach(clause; clauses) {
            if(clause.params.length != argVals.length) continue;
            bool match = true;
            string[] varNames;
            Value[string] saved;
            foreach(i, pexp; clause.params) {
                auto val = argVals[i];
                if(!matchPattern(val, pexp, varNames, saved)) { match = false; break; }
            }
            if(match) {
                if(clause.hasGuard) {
                    auto gval = evalExpr(clause.guard);
                    bool pass = false;
                    if(gval.kind == ValueKind.Number) pass = gval.number != 0;
                    else if(gval.kind == ValueKind.Atom) pass = gval.atom != "false";
                    else pass = true;
                    if(!pass) {
                        foreach(k,v; saved) variables[k] = v;
                        foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                        continue;
                    }
                }
                auto result = evalExpr(clause.body);
                foreach(k,v; saved) variables[k] = v;
                foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                return result;
            } else {
                foreach(k,v; saved) variables[k] = v;
                foreach(n; varNames) if(!(n in saved)) variables.remove(n);
            }
        }
    }
    return num(0);
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
    } else if(head == ">") {
        auto a = evalExpr(e.list[1]).number;
        auto b = evalExpr(e.list[2]).number;
        return atomVal(a > b ? "true" : "false");
    } else if(head == "<") {
        auto a = evalExpr(e.list[1]).number;
        auto b = evalExpr(e.list[2]).number;
        return atomVal(a < b ? "true" : "false");
    } else if(head == "=:=") {
        auto a = evalExpr(e.list[1]);
        auto b = evalExpr(e.list[2]);
        return atomVal(valuesEqual(a, b) ? "true" : "false");
    } else if(head == "is_atom") {
        auto v = evalExpr(e.list[1]);
        return atomVal(v.kind == ValueKind.Atom ? "true" : "false");
    } else if(head == "is_tuple") {
        auto v = evalExpr(e.list[1]);
        return atomVal(v.kind == ValueKind.Tuple ? "true" : "false");
    } else if(head == "is_list") {
        auto v = evalExpr(e.list[1]);
        return atomVal(v.kind == ValueKind.List ? "true" : "false");
    } else if(head == "is_number") {
        auto v = evalExpr(e.list[1]);
        return atomVal(v.kind == ValueKind.Number ? "true" : "false");
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
    } else if(head == "if") {
        auto condVal = evalExpr(e.list[1]);
        if(isTruthy(condVal))
            return evalExpr(e.list[2]);
        else
            return evalExpr(e.list[3]);
    } else if(head == "cond") {
        for(size_t i = 1; i < e.list.length; i++) {
            auto clause = e.list[i];
            if(clause.list.length < 2) continue;
            auto test = clause.list[0];
            auto body = clause.list[1];
            if(test.isList && test.list.length > 0 && !test.list[0].isList && test.list[0].atom == "?=") {
                auto pat = test.list[1];
                Expr guard; bool hasGuard = false; Expr valExpr;
                if(test.list.length == 4 && test.list[2].isList && test.list[2].list.length > 0 && !test.list[2].list[0].isList && test.list[2].list[0].atom == "when") {
                    guard = test.list[2].list[1];
                    hasGuard = true;
                    valExpr = test.list[3];
                } else if(test.list.length >= 3) {
                    valExpr = test.list[2];
                } else continue;
                auto val = evalExpr(valExpr);
                string[] varNames; Value[string] saved;
                if(matchPattern(val, pat, varNames, saved)) {
                    if(hasGuard && !isTruthy(evalExpr(guard))) {
                        foreach(k,v; saved) variables[k] = v;
                        foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                        continue;
                    }
                    auto res = evalExpr(body);
                    foreach(k,v; saved) variables[k] = v;
                    foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                    return res;
                } else {
                    foreach(k,v; saved) variables[k] = v;
                    foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                }
            } else {
                auto val = evalExpr(test);
                if(isTruthy(val)) return evalExpr(body);
            }
        }
        return num(0);
    } else if(head == "case") {
        auto val = evalExpr(e.list[1]);
        for(size_t i = 2; i < e.list.length; i++) {
            auto clause = e.list[i];
            if(clause.list.length < 2) continue;
            auto pat = clause.list[0];
            Expr guard; bool hasGuard = false; Expr body;
            if(clause.list.length == 3 && clause.list[1].isList && clause.list[1].list.length > 0 && !clause.list[1].list[0].isList && clause.list[1].list[0].atom == "when") {
                guard = clause.list[1].list[1];
                hasGuard = true;
                body = clause.list[2];
            } else {
                body = clause.list[1];
            }
            string[] varNames; Value[string] saved;
            if(matchPattern(val, pat, varNames, saved)) {
                if(hasGuard && !isTruthy(evalExpr(guard))) {
                    foreach(k,v; saved) variables[k] = v;
                    foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                    continue;
                }
                auto res = evalExpr(body);
                foreach(k,v; saved) variables[k] = v;
                foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                return res;
            } else {
                foreach(k,v; saved) variables[k] = v;
                foreach(n; varNames) if(!(n in saved)) variables.remove(n);
            }
        }
        return num(0);
    } else if(head == "set") {
        auto name = e.list[1].atom;
        auto val = evalExpr(e.list[2]);
        variables[name] = val;
        return val;
    } else if(head == "let") {
        auto bindings = e.list[1];
        string[] names;
        Value[string] saved;
        foreach(b; bindings.list) {
            auto var = b.list[0].atom;
            auto val = evalExpr(b.list[1]);
            if(var in variables) saved[var] = variables[var];
            names ~= var;
            variables[var] = val;
        }
        Value result = num(0);
        for(size_t i = 2; i < e.list.length; i++) {
            result = evalExpr(e.list[i]);
        }
        foreach(n; names) {
            if(n in saved) variables[n] = saved[n];
            else variables.remove(n);
        }
        return result;
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
    } else if(head == "spawn") {
        auto modVal = evalExpr(e.list[1]);
        auto funVal = evalExpr(e.list[2]);
        auto argsVal = evalExpr(e.list[3]);
        if(modVal.kind != ValueKind.Atom || funVal.kind != ValueKind.Atom || argsVal.kind != ValueKind.List)
            throw new Exception("badarg");
        string mod = modVal.atom;
        string fun = funVal.atom;
        auto argVals = argsVal.list.dup;
        auto pid = pidCounter++;
        taskPool.put(() {
            callFunctionDirect(mod ~ ":" ~ fun, argVals);
        });
        return atomVal("<" ~ to!string(pid) ~ ">");
    } else if(head == "lfe_io:format") {
        auto fmtExpr = e.list[1];
        string fmt = fmtExpr.atom;
        if(fmt.length >= 2 && fmt[0] == '"' && fmt[$-1] == '"')
            fmt = fmt[1 .. $-1];
        auto argsVal = evalExpr(e.list[2]);
        if(argsVal.kind != ValueKind.List)
            throw new Exception("badarg");
        string out;
        size_t ai = 0;
        for(size_t i = 0; i < fmt.length; i++) {
            if(fmt[i] == '~' && i + 1 < fmt.length) {
                auto n = fmt[i+1];
                if(n == 'w') {
                    if(ai >= argsVal.list.length) throw new Exception("badarg");
                    out ~= formatValue(argsVal.list[ai++]);
                    i++;
                    continue;
                } else if(n == 'n') {
                    out ~= "\n";
                    i++;
                    continue;
                }
            }
            out ~= fmt[i];
        }
        write(out);
        return atomVal("ok");
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
                Expr guard;
                bool hasGuard = false;
                Expr body;
                if(cl.list.length == 3 && cl.list[1].isList && cl.list[1].list.length > 0 && !cl.list[1].list[0].isList && cl.list[1].list[0].atom == "when") {
                    guard = cl.list[1].list[1];
                    hasGuard = true;
                    body = cl.list[2];
                } else {
                    body = cl.list[1];
                }
                clauses ~= FunctionClause(params, body, guard, hasGuard);
            }
        } else {
            auto params = e.list[2].list;
            Expr guard;
            bool hasGuard = false;
            auto body = e.list[3];
            clauses ~= FunctionClause(params, body, guard, hasGuard);
        }
        functions[name] = clauses;
        string entry = name ~ "/" ~ to!string(clauses[0].params.length);
        if(!("global" in moduleFunctions)) moduleFunctions["global"] = [];
        if(entry !in moduleFunctions["global"]) moduleFunctions["global"] ~= entry;
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
                        Expr guard;
                        bool hasGuard = false;
                        Expr body;
                        if(cl.list.length == 3 && cl.list[1].isList && cl.list[1].list.length > 0 && !cl.list[1].list[0].isList && cl.list[1].list[0].atom == "when") {
                            guard = cl.list[1].list[1];
                            hasGuard = true;
                            body = cl.list[2];
                        } else {
                            body = cl.list[1];
                        }
                        clauses ~= FunctionClause(params, body, guard, hasGuard);
                    }
                } else {
                    auto params = expr.list[2].list;
                    Expr guard;
                    bool hasGuard = false;
                    auto body = expr.list[3];
                    clauses ~= FunctionClause(params, body, guard, hasGuard);
                }
                functions[modName ~ ":" ~ fname] = clauses;
                string entry = fname ~ "/" ~ to!string(clauses[0].params.length);
                if(!(modName in moduleFunctions)) moduleFunctions[modName] = [];
                if(entry !in moduleFunctions[modName]) moduleFunctions[modName] ~= entry;
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
                if(clause.hasGuard) {
                    auto gval = evalExpr(clause.guard);
                    bool pass = false;
                    if(gval.kind == ValueKind.Number) pass = gval.number != 0;
                    else if(gval.kind == ValueKind.Atom) pass = gval.atom != "false";
                    else pass = true;
                    if(!pass) {
                        foreach(k,v; saved) variables[k] = v;
                        foreach(n; varNames) if(!(n in saved)) variables.remove(n);
                        continue;
                    }
                }
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
        auto tabPos = line.indexOf('\t');
        if(tabPos >= 0) {
            auto prefix = line[0 .. tabPos];
            showCompletions(prefix);
            continue;
        }
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


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
}

class LfeParser : Parser {
    this(Token[] toks) {
        super(toks);
    }

    Expr parseExpr() {
        if (peek("LPAREN")) {
            consume("LPAREN");
            Expr[] elems;
            while (!peek("RPAREN")) {
                elems ~= parseExpr();
                if (pos >= tokens.length) break;
            }
            consume("RPAREN");
            return Expr(true, "", elems, false);
        } else if (peek("NUMBER")) {
            auto t = consume("NUMBER");
            return Expr(false, t.value, null, false);
        } else if (peek("STRING")) {
            auto t = consume("STRING");
            return Expr(false, t.value, null, false);
        } else if (peek("ATOM")) {
            auto t = consume("ATOM");
            return Expr(false, t.value[1 .. $], null, true);
        } else if (peek("SYMBOL")) {
            auto t = consume("SYMBOL");
            return Expr(false, t.value, null, false);
        }
        throw new Exception("Unexpected token");
    }
}

struct FunctionClause {
    Expr[] params;
    Expr body;
}

double[string] variables;
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

double evalExpr(Expr e);

immutable Rule[] rules = [
    Rule("LPAREN", regex("\\(")),
    Rule("RPAREN", regex("\\)")),
    Rule("STRING", regex("\"[^\"]*\"")),
    Rule("NUMBER", regex("[0-9]+(\\.[0-9]+)?")),
    Rule("ATOM", regex("'[a-zA-Z_+*/:<>=!?-][a-zA-Z0-9_+*/:<>=!?-]*")),
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

double evalList(Expr e) {
    if(e.list.length == 0) return 0;
    auto head = e.list[0].atom;
    if(head == "+") {
        double result = 0;
        foreach(arg; e.list[1 .. $]) result += evalExpr(arg);
        return result;
    } else if(head == "-") {
        double result = evalExpr(e.list[1]);
        foreach(arg; e.list[2 .. $]) result -= evalExpr(arg);
        return result;
    } else if(head == "*") {
        double result = 1;
        foreach(arg; e.list[1 .. $]) result *= evalExpr(arg);
        return result;
    } else if(head == "/") {
        double result = evalExpr(e.list[1]);
        foreach(arg; e.list[2 .. $]) result /= evalExpr(arg);
        return result;
    } else if(head == "set") {
        auto name = e.list[1].atom;
        auto val = evalExpr(e.list[2]);
        variables[name] = val;
        return val;
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
        return 0;
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
        return 0;
    } else if(head == "c") {
        auto fexpr = e.list[1];
        auto path = fexpr.atom;
        if(path.length >= 2 && path[0] == '"' && path[$-1] == '"')
            path = path[1 .. $-1];
        loadFile(path);
        return 0;
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
            double[string] saved;
            foreach(i, pexp; clause.params) {
                auto arg = args[i];
                if(pexp.isAtom) {
                    if(!(arg.isAtom && arg.atom == pexp.atom)) { match = false; break; }
                } else {
                    auto val = evalExpr(arg);
                    auto name = pexp.atom;
                    if(name in variables) saved[name] = variables[name];
                    variables[name] = val;
                    varNames ~= name;
                }
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
        return 0;
    }
    return 0;
}

double evalExpr(Expr e) {
    if(!e.isList) {
        if(isNumber(e.atom)) return to!double(e.atom);
        if(auto v = e.atom in variables) return *v;
        return 0;
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
            writeln(result);
        } catch(Exception e) {
            if(e.msg == "__exit__") break;
            writeln("Error: ", e.msg);
        }
    }
}

void main() {
    repl();
}


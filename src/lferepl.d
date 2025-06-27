module lferepl;

import dlexer;
import dparser;
import std.regex : regex;
import std.stdio;
import std.string;
import std.ascii : isDigit;
import std.algorithm;
import std.conv : to;

struct Expr {
    bool isList;
    string atom;
    Expr[] list;
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
            return Expr(true, "", elems);
        } else if (peek("NUMBER")) {
            auto t = consume("NUMBER");
            return Expr(false, t.value, null);
        } else if (peek("STRING")) {
            auto t = consume("STRING");
            return Expr(false, t.value, null);
        } else if (peek("SYMBOL")) {
            auto t = consume("SYMBOL");
            return Expr(false, t.value, null);
        }
        throw new Exception("Unexpected token");
    }
}

struct FunctionDef {
    string[] params;
    Expr body;
}

long[string] variables;
FunctionDef[string] functions;

bool isNumber(string s) {
    foreach(ch; s) if(!ch.isDigit) return false;
    return s.length > 0;
}

long evalExpr(Expr e);

long evalList(Expr e) {
    if(e.list.length == 0) return 0;
    auto head = e.list[0].atom;
    if(head == "+") {
        long result = 0;
        foreach(arg; e.list[1 .. $]) result += evalExpr(arg);
        return result;
    } else if(head == "*") {
        long result = 1;
        foreach(arg; e.list[1 .. $]) result *= evalExpr(arg);
        return result;
    } else if(head == "set") {
        auto name = e.list[1].atom;
        auto val = evalExpr(e.list[2]);
        variables[name] = val;
        return val;
    } else if(head == "defun") {
        auto name = e.list[1].atom;
        auto params = e.list[2].list.map!(p => p.atom).array;
        auto body = e.list[3];
        functions[name] = FunctionDef(params, body);
        return 0;
    } else if(head == "exit") {
        // signal to caller
        throw new Exception("__exit__");
    } else if(auto fn = head in functions) {
        auto def = *fn;
        long[string] saved;
        foreach(i, p; def.params) {
            auto val = evalExpr(e.list[i+1]);
            if(p in variables) saved[p] = variables[p];
            variables[p] = val;
        }
        auto result = evalExpr(def.body);
        foreach(k, v; saved) variables[k] = v;
        foreach(p; def.params) if(!(p in saved)) variables.remove(p);
        return result;
    }
    return 0;
}

long evalExpr(Expr e) {
    if(!e.isList) {
        if(isNumber(e.atom)) return to!long(e.atom);
        if(auto v = e.atom in variables) return *v;
        return 0;
    }
    return evalList(e);
}

void repl() {
    writeln("LFE REPL -- type (exit) to quit");
    auto rules = [
        Rule("LPAREN", regex("\\(")),
        Rule("RPAREN", regex("\\)")),
        Rule("STRING", regex("\"[^\"]*\"")),
        Rule("NUMBER", regex("[0-9]+")),
        Rule("SYMBOL", regex("[a-zA-Z_+*/:<>=!?-][a-zA-Z0-9_+*/:<>=!?-]*")),
        Rule("WS", regex("\\s+"))
    ];
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


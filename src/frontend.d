module frontend;

import lferepl : evalString, valueToString;
import std.ascii : isWhite;
import std.string : strip, startsWith, indexOf;

bool forceLfe(ref string line) {
    auto trimmed = line.strip;
    enum prefix = ":lfe";
    if(trimmed.startsWith(prefix)) {
        // Remove prefix and any following whitespace
        auto rest = trimmed[prefix.length .. $];
        line = rest.strip;
        return true;
    }
    return false;
}

bool isLfeInput(string s) {
    if(s.length == 0) return false;
    auto c = s[0];
    if(c == '(' || c == '\'') return true;
    if(c == '#') {
        return s.length > 1 && (s[1] == '(' || s[1] == 'M');
    }
    return false;
}

string evalToString(string code) {
    auto val = evalString(code);
    return valueToString(val);
}

string interpolateLfe(string line) {
    string result = line;
    // $(lfe ...)
    size_t pos;
    while((pos = result.indexOf("$(lfe")) != -1) {
        size_t start = pos + 5; // after $(lfe
        while(start < result.length && isWhite(result[start])) start++;
        size_t i = start;
        int depth = 0;
        for(; i < result.length; i++) {
            auto ch = result[i];
            if(ch == '(') depth++;
            else if(ch == ')') {
                if(depth == 0) break;
                else depth--;
            }
        }
        if(i >= result.length) break;
        auto expr = result[start .. i];
        string evald;
        try {
            evald = evalToString(expr);
        } catch(Exception e) {
            evald = "";
        }
        result = result[0 .. pos] ~ evald ~ result[i+1 .. $];
    }
    // ${lfe:...}
    while((pos = result.indexOf("${lfe:")) != -1) {
        size_t start = pos + 6; // after ${lfe:
        size_t i = start;
        int depth = 0;
        for(; i < result.length; i++) {
            auto ch = result[i];
            if(ch == '{') depth++;
            else if(ch == '}') {
                if(depth == 0) break;
                else depth--;
            }
        }
        if(i >= result.length) break;
        auto expr = result[start .. i];
        string evald;
        try {
            evald = evalToString(expr);
        } catch(Exception e) {
            evald = "";
        }
        result = result[0 .. pos] ~ evald ~ result[i+1 .. $];
    }
    return result;
}

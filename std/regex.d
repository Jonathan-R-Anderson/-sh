module std.regex;

import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset, strlen;
import core.sys.posix.regex;

struct Regex
{
    regex_t rx;
}

Regex regex(string pattern)
{
    Regex r;
    if(regcomp(&r.rx, pattern.toStringz(), REG_EXTENDED) != 0)
        throw new Exception("invalid regex");
    return r;
}

struct Captures
{
    string hit;
    string pre;
}

Captures match(string input, Regex r)
{
    regmatch_t[1] pm;
    int rc = regexec(&r.rx, input.toStringz(), 1, pm.ptr, 0);
    if(rc != 0)
        return Captures();
    size_t b = pm[0].rm_so;
    size_t e = pm[0].rm_eo;
    return Captures(input[b .. e], input[0 .. b]);
}

Captures matchFirst(string input, Regex r)
{
    return match(input, r);
}

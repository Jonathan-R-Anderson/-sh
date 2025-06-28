module mstd.path;

import mstd.string : split, join;

string baseName(string path)
{
    auto parts = split(path, "/");
    return parts.length ? parts[$-1] : path;
}

string dirName(string path)
{
    auto pos = path.lastIndexOf("/");
    if(pos == -1) return ".";
    if(pos == 0) return "/";
    return path[0 .. pos];
}

string buildPath(string a, string b)
{
    if(a.length && a[$-1] == '/')
        return a ~ b;
    else
        return a ~ "/" ~ b;
}

string buildNormalizedPath(string p)
{
    // This minimal version just removes duplicate separators.
    string result;
    bool prevSlash = false;
    foreach(ch; p)
    {
        if(ch == '/')
        {
            if(!prevSlash) result ~= ch;
            prevSlash = true;
        }
        else
        {
            result ~= ch;
            prevSlash = false;
        }
    }
    return result.length ? result : ".";
}

bool globMatch(string pattern, string name)
{
    size_t p = 0, n = 0;
    while(p < pattern.length && n < name.length)
    {
        if(pattern[p] == '*')
        {
            ++p;
            if(p >= pattern.length) return true;
            while(n < name.length && !globMatch(pattern[p .. $], name[n .. $]))
                ++n;
            return n < name.length;
        }
        else if(pattern[p] == '?' || pattern[p] == name[n])
        {
            ++p; ++n;
        }
        else
        {
            return false;
        }
    }
    while(p < pattern.length && pattern[p] == '*') ++p;
    return p == pattern.length && n == name.length;
}

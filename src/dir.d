module dir;

import std.stdio;
import std.file : dirEntries, SpanMode;
import std.algorithm : sort;
import std.format : format;

string escapeName(string name)
{
    string out;
    foreach(dchar c; name) {
        if(c == '\\')
            out ~= "\\\\";
        else if(c < 32 || c == 127)
            out ~= "\\" ~ format("%03o", cast(int)c);
        else
            out ~= cast(char)c;
    }
    return out;
}

void dirCommand(string[] tokens)
{
    string path = tokens.length > 1 ? tokens[1] : ".";
    string[] entries;
    foreach(e; dirEntries(path, SpanMode.shallow))
        entries ~= e.name;
    entries.sort;
    size_t cols = 4;
    for(size_t i=0;i<entries.length;i++) {
        auto n = escapeName(entries[i]);
        writef("%-20s", n);
        if((i+1)%cols==0 || i+1==entries.length)
            writeln();
    }
}


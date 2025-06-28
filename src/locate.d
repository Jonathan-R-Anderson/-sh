module locate;

import mstd.stdio;
import mstd.file : dirEntries, SpanMode;
import mstd.string : indexOf;

void search(string path, string pattern)
{
    foreach(entry; dirEntries(path, SpanMode.shallow))
    {
        string name = entry.name;
        if(name.indexOf(pattern) >= 0)
            writeln(name);
        if(entry.isDir)
        {
            try
                search(name, pattern);
            catch(Exception) {}
        }
    }
}

/// Very small locate implementation searching directories recursively.
void locateCommand(string[] tokens)
{
    if(tokens.length < 2)
    {
        writeln("Usage: locate pattern [start]");
        return;
    }
    string pattern = tokens[1];
    string start = tokens.length > 2 ? tokens[2] : "/";
    try
        search(start, pattern);
    catch(Exception e)
        writeln("locate: error searching ", start);
}

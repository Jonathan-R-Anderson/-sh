module klist;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system klist command with the provided arguments.
void klistCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "klist" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("klist failed with code ", rc);
}

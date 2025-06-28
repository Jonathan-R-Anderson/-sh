module iostat;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system iostat command with the provided arguments.
void iostatCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "iostat" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("iostat failed with code ", rc);
}

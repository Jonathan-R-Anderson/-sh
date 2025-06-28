module groupadd;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system groupadd command with the provided arguments.
void groupaddCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "groupadd" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("groupadd failed with code ", rc);
}

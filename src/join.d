module join;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system join command with the provided arguments.
void joinCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "join" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("join failed with code ", rc);
}

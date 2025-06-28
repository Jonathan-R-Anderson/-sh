module groupmod;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system groupmod command with the provided arguments.
void groupmodCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "groupmod" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("groupmod failed with code ", rc);
}

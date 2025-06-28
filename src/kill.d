module kill;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system kill command with the provided arguments.
void killCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "kill" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("kill failed with code ", rc);
}

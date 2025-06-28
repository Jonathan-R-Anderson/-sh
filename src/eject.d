module eject;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system eject command with the provided arguments.
void ejectCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "eject" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("eject failed with code ", rc);
}

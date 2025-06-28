module install;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system install command with the provided arguments.
void installCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "install" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("install failed with code ", rc);
}

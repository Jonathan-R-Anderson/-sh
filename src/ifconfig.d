module ifconfig;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system ifconfig command with the provided arguments.
void ifconfigCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "ifconfig" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("ifconfig failed with code ", rc);
}

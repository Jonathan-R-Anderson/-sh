module ip;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system ip command with the provided arguments.
void ipCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "ip" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("ip failed with code ", rc);
}

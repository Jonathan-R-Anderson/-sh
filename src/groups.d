module groups;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system groups command with the provided arguments.
void groupsCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "groups" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("groups failed with code ", rc);
}

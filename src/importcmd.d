module importcmd;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system import command with the provided arguments.
void importCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "import" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("import failed with code ", rc);
}

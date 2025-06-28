module fdformat;

import mstd.stdio;
import mstd.string : join;
import core.stdc.stdlib : system;

/// Execute the system fdformat command with the provided arguments.
void fdformatCommand(string[] tokens)
{
    if(tokens.length < 2) {
        writeln("Usage: fdformat [-n] device");
        return;
    }
    string args = tokens[1 .. $].join(" ");
    string cmd = "fdformat" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd);
    if(rc != 0)
        writeln("fdformat failed with code ", rc);
}

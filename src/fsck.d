module fsck;

import std.stdio;
import std.string : join, toStringz;
import core.stdc.stdlib : system;

/// Execute the system fsck command with the provided arguments.
void fsckCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "fsck" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd.toStringz);
    if(rc != 0)
        writeln("fsck failed with code ", rc);
}


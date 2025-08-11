module getfacl;

import std.stdio;
import std.string : join, toStringz;
import core.stdc.stdlib : system;

/// Execute the system getfacl command with the provided arguments.
void getfaclCommand(string[] tokens)
{
    string args = tokens.length > 1 ? tokens[1 .. $].join(" ") : "";
    string cmd = "getfacl" ~ (args.length ? " " ~ args : "");
    auto rc = system(cmd.toStringz);
    if(rc != 0)
        writeln("getfacl failed with code ", rc);
}

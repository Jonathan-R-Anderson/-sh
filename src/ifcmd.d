module ifcmd;

import mstd.stdio;
import mstd.string : join, replace;
import core.stdc.stdlib : system;

/// Evaluate a shell if statement using /bin/sh.
void ifCommand(string[] tokens)
{
    if(tokens.length < 2) {
        writeln("if: missing condition");
        return;
    }
    string script = "if " ~ tokens[1 .. $].join(" ");
    string escaped = script.replace("\"", "\\\"");
    string cmd = "sh -c \"" ~ escaped ~ "\"";
    auto rc = system(cmd);
    if(rc != 0)
        writeln("if command failed with code ", rc);
}

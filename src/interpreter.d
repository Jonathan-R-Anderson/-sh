import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.parallelism;
import std.range;

/**
 * Simple interpreter skeleton for a Lisp-like language.
 * This implementation is intentionally minimal and is
 * provided as an example of building language tooling
 * with the D cross-compiler.
 */

void runCommand(string cmd);

void run(string input) {
    auto cmds = input.split("&");
    if(cmds.length > 1) {
        foreach(c; cmds) {
            taskPool.put(() { runCommand(c.strip); });
        }
        taskPool.finish();
    } else {
        runCommand(input.strip);
    }
}

void runCommand(string cmd) {
    auto tokens = cmd.split();
    if(tokens.length == 0) return;
    auto op = tokens[0];
    if(op == "echo") {
        writeln(tokens[1 .. $].join(" "));
    } else if(op == "+" || op == "-") {
        if(tokens.length < 3) {
            writeln("Invalid arithmetic expression");
            return;
        }
        int a = to!int(tokens[1]);
        int b = to!int(tokens[2]);
        auto result = (op == "+") ? a + b : a - b;
        writeln(result);
    } else if(op == "for") {
        if(tokens.length < 3) {
            writeln("Usage: for start..end command");
            return;
        }
        auto rangeParts = tokens[1].split("..");
        if(rangeParts.length != 2) {
            writeln("Invalid range");
            return;
        }
        int start = to!int(rangeParts[0]);
        int finish = to!int(rangeParts[1]);
        string sub = tokens[2 .. $].join(" ");
        foreach(i; iota(start, finish + 1)) {
            runCommand(sub);
        }
    } else {
        writeln("Unknown command: ", op);
    }
}

void main(string[] args) {
    if(args.length < 2) {
        writeln("Usage: interpreter \"command string\"");
        return;
    }
    run(args[1]);
}

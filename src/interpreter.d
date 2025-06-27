import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.parallelism;
import std.range;
import std.file : chdir, getcwd, dirEntries, SpanMode, readText,
    copy, rename, remove, mkdir, rmdir;
import std.process : system, environment;
import std.regex : regex, matchFirst;
import std.path : globMatch;
import std.conv : to;
import core.thread : Thread;
import std.datetime : Clock, SysTime;
import core.time : dur;

string[] history;
string[string] aliases;

string[string] variables;

string[string] colorCodes = [
    "black": "\033[30m",
    "red": "\033[31m",
    "green": "\033[32m",
    "yellow": "\033[33m",
    "blue": "\033[34m",
    "magenta": "\033[35m",
    "cyan": "\033[36m",
    "white": "\033[37m"
];

struct AtJob {
    size_t id;
    string cmd;
    SysTime runAt;
    bool canceled;
}

AtJob[] atJobs;
size_t nextAtId;

/**
 * Simple interpreter skeleton for a Lisp-like language.
 * This implementation is intentionally minimal and is
 * provided as an example of building language tooling
 * with the D cross-compiler.
 */

void runCommand(string cmd);
void runParallel(string input);

void run(string input) {
    auto seqs = input.split(";");
    foreach(s; seqs) {
        auto trimmed = s.strip;
        if(trimmed.length == 0) continue;
        runParallel(trimmed);
    }
}

void runParallel(string input) {
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

void runBackground(string cmd) {
    // Execute a command asynchronously without waiting
    taskPool.put(() { run(cmd); });
}

void runCommand(string cmd) {
    history ~= cmd;
    auto tokens = cmd.split();
    if(tokens.length == 0) return;

    string lastAlias;
    int aliasDepth = 0;
    while(auto ali = tokens[0] in aliases) {
        if(tokens[0] == lastAlias || aliasDepth > 10) break;
        lastAlias = tokens[0];
        auto aliStr = *ali;
        auto aliTokens = aliStr.split();
        tokens = aliTokens ~ tokens[1 .. $];
        aliasDepth++;
    }

    // variable expansion
    foreach(ref t; tokens) {
        if(t.length > 1 && t[0] == '$') {
            auto key = t[1 .. $];
            if(auto val = key in variables) t = *val;
        }
    }

    // variable assignment of form name=value
    auto eqPos = tokens[0].indexOf('=');
    if(eqPos > 0 && tokens.length == 1) {
        auto name = tokens[0][0 .. eqPos];
        auto value = tokens[0][eqPos + 1 .. $];
        variables[name] = value;
        return;
    }

    auto op = tokens[0];
    if(op == "echo") {
        writeln(tokens[1 .. $].join(" "));
    } else if(op == "+" || op == "-" || op == "*" || op == "/") {
        if(tokens.length < 3) {
            writeln("Invalid arithmetic expression");
            return;
        }
        int a = to!int(tokens[1]);
        int b = to!int(tokens[2]);
        int result;
        final switch(op) {
            case "+": result = a + b; break;
            case "-": result = a - b; break;
            case "*": result = a * b; break;
            case "/": result = b == 0 ? 0 : a / b; break;
        }
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
    } else if(op == "cd") {
        if(tokens.length < 2) {
            writeln("cd: missing operand");
            return;
        }
        chdir(tokens[1]);
    } else if(op == "pwd") {
        writeln(getcwd());
    } else if(op == "ls") {
        string path = tokens.length > 1 ? tokens[1] : ".";
        foreach(entry; dirEntries(path, SpanMode.shallow)) {
            writeln(entry.name);
        }
    } else if(op == "cat") {
        if(tokens.length < 2) {
            writeln("cat: missing file operand");
            return;
        }
        foreach(f; tokens[1 .. $]) {
            try {
                writeln(readText(f));
            } catch(Exception e) {
                writeln("cat: cannot read ", f);
            }
        }
    } else if(op == "head") {
        if(tokens.length < 2) {
            writeln("head: missing file operand");
            return;
        }
        string file = tokens[1];
        size_t lines = 10;
        try {
            auto text = readText(file).splitLines;
            foreach(i, l; text) {
                if(i >= lines) break;
                writeln(l);
            }
        } catch(Exception e) {
            writeln("head: cannot read ", file);
        }
    } else if(op == "tail") {
        if(tokens.length < 2) {
            writeln("tail: missing file operand");
            return;
        }
        string file = tokens[1];
        size_t lines = 10;
        try {
            auto text = readText(file).splitLines;
            auto start = text.length > lines ? text.length - lines : 0;
            foreach(l; text[start .. $]) {
                writeln(l);
            }
        } catch(Exception e) {
            writeln("tail: cannot read ", file);
        }
    } else if(op == "grep") {
        if(tokens.length < 3) {
            writeln("grep pattern file...");
            return;
        }
        auto pattern = tokens[1];
        foreach(f; tokens[2 .. $]) {
            try {
                foreach(line; readText(f).splitLines) {
                    if(line.canFind(pattern)) writeln(line);
                }
            } catch(Exception e) {
                writeln("grep: cannot read ", f);
            }
        }
    } else if(op == "mkdir") {
        if(tokens.length < 2) {
            writeln("mkdir: missing operand");
            return;
        }
        foreach(dir; tokens[1 .. $]) {
            try {
                std.file.mkdir(dir);
            } catch(Exception e) {
                writeln("mkdir: cannot create directory ", dir);
            }
        }
    } else if(op == "rmdir") {
        if(tokens.length < 2) {
            writeln("rmdir: missing operand");
            return;
        }
        foreach(dir; tokens[1 .. $]) {
            try {
                std.file.rmdir(dir);
            } catch(Exception e) {
                writeln("rmdir: failed to remove ", dir);
            }
        }
    } else if(op == "touch") {
        if(tokens.length < 2) {
            writeln("touch: missing file operand");
            return;
        }
        foreach(f; tokens[1 .. $]) {
            try {
                auto file = File(f, "a");
                file.close();
            } catch(Exception e) {
                writeln("touch: cannot touch ", f);
            }
        }
    } else if(op == "cp") {
        if(tokens.length != 3) {
            writeln("cp source dest");
            return;
        }
        try {
            std.file.copy(tokens[1], tokens[2]);
        } catch(Exception e) {
            writeln("cp: failed to copy");
        }
    } else if(op == "mv") {
        if(tokens.length != 3) {
            writeln("mv source dest");
            return;
        }
        try {
            std.file.rename(tokens[1], tokens[2]);
        } catch(Exception e) {
            writeln("mv: failed to move");
        }
    } else if(op == "rm") {
        if(tokens.length < 2) {
            writeln("rm: missing operand");
            return;
        }
        foreach(f; tokens[1 .. $]) {
            try {
                std.file.remove(f);
            } catch(Exception e) {
                writeln("rm: cannot remove ", f);
            }
        }
    } else if(op == "date") {
        import std.datetime : Clock;
        auto now = Clock.currTime();
        writeln(now.toISOExtString());
    } else if(op == "bg") {
        if(tokens.length < 2) {
            writeln("Usage: bg command");
            return;
        }
        auto sub = tokens[1 .. $].join(" ");
        runBackground(sub);
    } else if(op == "at") {
        if(tokens.length < 3) {
            writeln("Usage: at seconds command");
            return;
        }
        auto delay = to!long(tokens[1]);
        auto sub = tokens[2 .. $].join(" ");
        auto runAt = Clock.currTime() + dur!"seconds"(delay);
        auto job = AtJob(nextAtId++, sub, runAt, false);
        atJobs ~= job;
        auto idx = atJobs.length - 1;
        taskPool.put(() {
            Thread.sleep(dur!"seconds"(delay));
            if(!atJobs[idx].canceled) {
                run(sub);
                atJobs[idx].canceled = true;
            }
        });
        writeln("job ", job.id, " scheduled for ", runAt.toISOExtString());
    } else if(op == "atq") {
        foreach(job; atJobs) {
            if(!job.canceled)
                writeln(job.id, "\t", job.runAt.toISOExtString(), "\t", job.cmd);
        }
    } else if(op == "atrm") {
        if(tokens.length < 2) {
            writeln("Usage: atrm jobid [jobid ...]");
            return;
        }
        foreach(idStr; tokens[1 .. $]) {
            auto jid = to!size_t(idStr);
            foreach(ref job; atJobs)
                if(job.id == jid) job.canceled = true;
        }
    } else if(op == "alias") {
        if(tokens.length == 1 || (tokens.length == 2 && tokens[1] == "-p")) {
            foreach(name, val; aliases) {
                writeln("alias ", name, "='", val, "'");
            }
        } else {
            size_t start = 1;
            if(tokens.length > 1 && tokens[1] == "-p") start = 2;
            foreach(arg; tokens[start .. $]) {
                auto eq = arg.indexOf('=');
                if(eq > 0) {
                    auto name = arg[0 .. eq];
                    auto value = arg[eq+1 .. $];
                    aliases[name] = value;
                } else {
                    auto name = arg;
                    if(auto val = name in aliases)
                        writeln("alias ", name, "='", *val, "'");
                }
            }
        }
    } else if(op == "unalias") {
        if(tokens.length == 2 && tokens[1] == "-a") {
            aliases.clear();
        } else if(tokens.length >= 2) {
            foreach(name; tokens[1 .. $]) {
                aliases.remove(name);
            }
        } else {
            writeln("unalias: usage: unalias [-a] name [name ...]");
        }
    } else if(op == "apropos") {
        if(tokens.length < 2) {
            writeln("Usage: apropos [-a] [-e|-r|-w] keyword [...]");
            return;
        }

        bool useRegex = false;
        bool useWildcard = false;
        bool useExact = false;
        bool requireAll = false;
        size_t idx = 1;
        while(idx < tokens.length && tokens[idx].startsWith("-")) {
            auto t = tokens[idx];
            if(t == "-r" || t == "--regex") useRegex = true;
            else if(t == "-w" || t == "--wildcard") useWildcard = true;
            else if(t == "-e" || t == "--exact") useExact = true;
            else if(t == "-a" || t == "--and") requireAll = true;
            idx++;
        }
        auto keywords = tokens[idx .. $];
        if(keywords.length == 0) {
            writeln("Usage: apropos [-a] [-e|-r|-w] keyword [...]");
            return;
        }

        string helpText;
        try {
            helpText = readText("commands.txt");
        } catch(Exception e) {
            writeln("commands.txt not found");
            return;
        }

        foreach(line; helpText.splitLines) {
            bool matched = requireAll ? true : false;
            foreach(kw; keywords) {
                bool local = false;
                auto lowerLine = line.toLower;
                auto lowerKw = kw.toLower;
                if(useRegex) {
                    try {
                        auto r = regex(lowerKw, "i");
                        local = matchFirst(lowerLine, r) !is null;
                    } catch(Exception) {
                        continue;
                    }
                } else if(useWildcard) {
                    local = globMatch(lowerLine, lowerKw);
                } else if(useExact) {
                    foreach(word; lowerLine.split()) {
                        if(word == lowerKw) { local = true; break; }
                    }
                } else {
                    local = lowerLine.canFind(lowerKw);
                }
                if(requireAll) matched &= local; else matched |= local;
            }
            if(matched) writeln(line);
        }
    } else if(op == "help") {
        string helpText;
        try {
            helpText = readText("commands.txt");
        } catch(Exception e) {
            helpText = "commands.txt not found";
        }
        writeln(helpText);
    } else if(op == "history") {
        foreach(i, cmdLine; history) {
            writeln(i + 1, " ", cmdLine);
        }
    } else if(op == "apt" || op == "apt-get") {
        auto rc = system(cmd);
        if(rc != 0) {
            writeln(op, " failed with code ", rc);
        }
    } else {
        // attempt to run external command
        auto rc = system(cmd);
        if(rc != 0) {
            writeln("Unknown command: ", op);
        }
    }
}

void repl() {
    auto ps1 = environment.get("PS1", "sh> ");
    auto colorName = environment.get("PS_COLOR", "");
    string colorCode;
    if(auto c = colorName in colorCodes) colorCode = *c;
    auto reset = colorCode.length ? "\033[0m" : "";
    for(;;) {
        write(colorCode, ps1, reset);
        auto line = readln();
        if(line is null) break;
        line = line.strip;
        if(line == "exit") break;
        if(line.length == 0) continue;
        if(line == "!!" && history.length) {
            line = history[$-1];
            writeln(line);
        }
        run(line);
    }
}

void main(string[] args) {
    if(args.length < 2) {
        repl();
        return;
    }
    run(args[1]);
}

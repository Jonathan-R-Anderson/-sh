import std.stdio;
import std.string;
import core.stdc.stdlib;
import core.stdc.stdio;
import core.sys.posix.unistd : isatty, STDIN_FILENO;
import frontend;
import lferepl;
import shell.executor : execute, initializeShell;
import shell.parser : parseShellCommand;
import shell.ast : Node;

// D bindings for GNU Readline
extern (C) {
    char* readline(const char* prompt);
    void add_history(const char* line);
    int read_history(const char* filename);
    int write_history(const char* filename);
}

// Processes a single line of input (either shell or LFE)
void processLine(string line) {
    if (line.length == 0) {
        return;
    }

    string interpolatedLine = interpolateLfe(line);

    if (isLfeInput(interpolatedLine)) {
        try {
            auto result = evalString(interpolatedLine);
            writeln(valueToString(result));
        } catch (Exception e) {
            writeln("LFE Error: ", e.msg);
        }
    } else {
        Node ast = parseShellCommand(interpolatedLine);
        execute(ast);
    }
}

// The main interactive shell loop
void runInteractiveShell() {
    char* line_read;
    while ((line_read = readline("lfe-sh> ")) !is null) {
        if (line_read[0] != '\0') {
            add_history(line_read);
        }

        string line = fromStringz(line_read).strip.idup;
        free(line_read);

        if (line == "exit") {
            break;
        }

        processLine(line);
    }
    writeln("\nexit");
}

// Main entry point for the shell
void main(string[] args) {
    if (isatty(STDIN_FILENO)) {
        initializeShell();
        runInteractiveShell();
    } else {
        // Non-interactive mode (e.g., from a pipe)
        string line;
        while((line = std.stdio.stdin.readln()) !is null) {
            processLine(line.strip);
        }
    }
}

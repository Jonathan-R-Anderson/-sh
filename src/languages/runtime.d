module languages.runtime;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.datetime;
import core.thread;
import core.time;
import languages.framework;
import languages.ldk;
import shell.config;

/// Security policy for language execution
enum SecurityPolicy {
    None,           // No restrictions
    Basic,          // Basic sandboxing (memory, time limits)
    Strict,         // Strict sandboxing (no file/network access)
    LockedDown      // Maximum restrictions
}

/// Resource limits
struct ResourceLimits {
    long maxMemoryBytes = -1;        // -1 = unlimited
    Duration maxExecutionTime = Duration.init; // Duration.init = unlimited
    int maxFileDescriptors = 100;
    int maxOpenSockets = 10;
    size_t maxOutputSize = 1024 * 1024; // 1MB
}

/// Execution context with security
class SecureExecutionContext {
    private ExecutionContext baseContext;
    private SecurityPolicy securityPolicy;
    private ResourceLimits limits;
    private long memoryUsage = 0;
    private Clock.TimePoint startTime;
    private int fileDescriptors = 0;
    private int openSockets = 0;
    private string outputBuffer;
    private bool executionStopped = false;

    this(ExecutionContext baseContext, SecurityPolicy policy, ResourceLimits limits) {
        this.baseContext = baseContext;
        this.securityPolicy = policy;
        this.limits = limits;
        this.startTime = Clock.currTime();
    }

    // Variable access with security checks
    void setVariable(string name, Value value) {
        checkMemoryUsage();
        baseContext.setVariable(name, value);
    }

    Value getVariable(string name) {
        checkExecutionTime();
        return baseContext.getVariable(name);
    }

    bool hasVariable(string name) {
        return baseContext.hasVariable(name);
    }

    // Function access with security checks
    void setFunction(string name, Value value) {
        checkMemoryUsage();
        baseContext.setFunction(name, value);
    }

    Value getFunction(string name) {
        checkExecutionTime();
        return baseContext.getFunction(name);
    }

    bool hasFunction(string name) {
        return baseContext.hasFunction(name);
    }

    // Security enforcement methods
    private void checkMemoryUsage() {
        if (executionStopped) {
            throw new SecurityException("Execution stopped due to policy violation");
        }

        if (limits.maxMemoryBytes >= 0 && memoryUsage > limits.maxMemoryBytes) {
            executionStopped = true;
            throw new SecurityException("Memory limit exceeded");
        }
    }

    private void checkExecutionTime() {
        if (executionStopped) {
            throw new SecurityException("Execution stopped due to policy violation");
        }

        if (limits.maxExecutionTime != Duration.init) {
            Duration elapsed = Clock.currTime() - startTime;
            if (elapsed > limits.maxExecutionTime) {
                executionStopped = true;
                throw new SecurityException("Execution time limit exceeded");
            }
        }
    }

    private void checkFileDescriptorLimit() {
        if (securityPolicy == SecurityPolicy.LockedDown) {
            throw new SecurityException("File access not allowed in locked down policy");
        }

        if (limits.maxFileDescriptors >= 0 && fileDescriptors >= limits.maxFileDescriptors) {
            throw new SecurityException("File descriptor limit exceeded");
        }
    }

    private void checkSocketLimit() {
        if (securityPolicy != SecurityPolicy.None) {
            throw new SecurityException("Network access not allowed in this security policy");
        }

        if (limits.maxOpenSockets >= 0 && openSockets >= limits.maxOpenSockets) {
            throw new SecurityException("Socket limit exceeded");
        }
    }

    // Resource tracking
    void allocateMemory(long bytes) {
        memoryUsage += bytes;
        checkMemoryUsage();
    }

    void deallocateMemory(long bytes) {
        memoryUsage = max(0, memoryUsage - bytes);
    }

    void openFileDescriptor() {
        checkFileDescriptorLimit();
        fileDescriptors++;
    }

    void closeFileDescriptor() {
        fileDescriptors = max(0, fileDescriptors - 1);
    }

    void openSocket() {
        checkSocketLimit();
        openSockets++;
    }

    void closeSocket() {
        openSockets = max(0, openSockets - 1);
    }

    // Output management
    void addOutput(string text) {
        outputBuffer ~= text;
        if (limits.maxOutputSize > 0 && outputBuffer.length > limits.maxOutputSize) {
            executionStopped = true;
            throw new SecurityException("Output size limit exceeded");
        }
    }

    string getOutput() {
        return outputBuffer;
    }

    // Getters
    SecurityPolicy getSecurityPolicy() { return securityPolicy; }
    ResourceLimits getLimits() { return limits; }
    long getMemoryUsage() { return memoryUsage; }
    Duration getExecutionTime() { return Clock.currTime() - startTime; }
    bool isExecutionStopped() { return executionStopped; }
}

/// Language runtime environment
class LanguageRuntime {
    private ConfigManager configManager;
    private LanguageDevelopmentKit ldk;
    private SecurityPolicy defaultPolicy;
    private ResourceLimits defaultLimits;

    this(ConfigManager configManager, LanguageDevelopmentKit ldk) {
        this.configManager = configManager;
        this.ldk = ldk;
        this.defaultPolicy = SecurityPolicy.Basic;
        this.defaultLimits = ResourceLimits();
        configureDefaultLimits();
    }

    private void configureDefaultLimits() {
        defaultLimits.maxMemoryBytes = configManager.getConfigInt("MAX_LANGUAGE_MEMORY", 50 * 1024 * 1024); // 50MB
        defaultLimits.maxExecutionTime = dur!"seconds"(configManager.getConfigInt("MAX_LANGUAGE_TIME", 30));
        defaultLimits.maxFileDescriptors = configManager.getConfigInt("MAX_LANGUAGE_FILES", 10);
        defaultLimits.maxOpenSockets = configManager.getConfigInt("MAX_LANGUAGE_SOCKETS", 0); // No network by default
        defaultLimits.maxOutputSize = configManager.getConfigInt("MAX_LANGUAGE_OUTPUT", 1024 * 1024); // 1MB
    }

    /// Execute code with default security settings
    ExecutionResult executeCode(string languageName, string code, ExecutionContext context) {
        return executeCodeWithPolicy(languageName, code, context, defaultPolicy, defaultLimits);
    }

    /// Execute code with custom security settings
    ExecutionResult executeCodeWithPolicy(string languageName, string code, ExecutionContext context,
                                         SecurityPolicy policy, ResourceLimits limits) {
        ExecutionResult result;
        result.languageName = languageName;
        result.code = code;

        Clock.TimePoint startTime = Clock.currTime();

        try {
            // Get language
            CustomLanguage language = getLanguage(languageName);
            if (language is null) {
                result.error = "Language not found: " ~ languageName;
                result.exitCode = 1;
                return result;
            }

            // Create secure execution context
            SecureExecutionContext secureContext = new SecureExecutionContext(context, policy, limits);

            // Execute the code
            Value returnValue = executeLanguage(language, code, secureContext);

            // Set result
            result.returnValue = returnValue;
            result.output = secureContext.getOutput();
            result.exitCode = (returnValue.type == ValueType.Error) ? 1 : 0;

        } catch (SecurityException e) {
            result.error = "Security violation: " ~ e.msg;
            result.exitCode = 2;
        } catch (Exception e) {
            result.error = "Execution error: " ~ e.msg;
            result.exitCode = 3;
        }

        result.executionTime = Clock.currTime() - startTime;
        return result;
    }

    /// Interactive execution (REPL)
    void startInteractiveREPL(string languageName, ExecutionContext context) {
        CustomLanguage language = getLanguage(languageName);
        if (language is null) {
            writeln("Language not found: " ~ languageName);
            return;
        }

        if (!language.supportsInteractive()) {
            writeln("Language '" ~ languageName ~ "' does not support interactive mode");
            return;
        }

        writeln("Interactive " ~ languageName ~ " REPL");
        writeln("Type 'exit' to quit, 'help' for help");

        SecureExecutionContext secureContext = new SecureExecutionContext(context, defaultPolicy, defaultLimits);

        while (true) {
            write(languageName ~ "> ");
            string line = readln();

            if (line is null) break;

            line = line.strip();
            if (line.length == 0) continue;

            if (line == "exit") break;
            if (line == "help") {
                showREPLHelp(languageName);
                continue;
            }

            try {
                ExecutionResult result = executeCodeWithPolicy(languageName, line, context, defaultPolicy, defaultLimits);

                if (result.error.length > 0) {
                    writeln("Error: " ~ result.error);
                } else if (result.returnValue.type != ValueType.Null) {
                    writeln("=> " ~ result.returnValue.toString());
                }

            } catch (Exception e) {
                writeln("Error: " ~ e.msg);
            }
        }
    }

    /// Batch execution of multiple lines
    ExecutionResult[] executeBatch(string languageName, string[] lines, ExecutionContext context) {
        ExecutionResult[] results;

        foreach(line; lines) {
            if (line.strip().length == 0) continue;
            ExecutionResult result = executeCode(languageName, line, context);
            results ~= result;

            // Stop on error if configured
            if (result.exitCode != 0 && configManager.getConfigBool("STOP_ON_ERROR", true)) {
                break;
            }
        }

        return results;
    }

    /// Compile language to intermediate code
    CompilationResult compileCode(string languageName, string code) {
        CompilationResult result;
        result.languageName = languageName;
        result.code = code;

        Clock.TimePoint startTime = Clock.currTime();

        try {
            CustomLanguage language = getLanguage(languageName);
            if (language is null) {
                result.error = "Language not found: " ~ languageName;
                result.success = false;
                return result;
            }

            if (!language.supportsCompilation()) {
                result.error = "Language does not support compilation";
                result.success = false;
                return result;
            }

            Value compileResult = language.compile(code);
            if (compileResult.type == ValueType.Error) {
                result.error = compileResult.error;
                result.success = false;
            } else {
                result.intermediateCode = compileResult.string_;
                result.success = true;
            }

        } catch (Exception e) {
            result.error = "Compilation error: " ~ e.msg;
            result.success = false;
        }

        result.compilationTime = Clock.currTime() - startTime;
        return result;
    }

    /// Get performance statistics
    PerformanceStats getPerformanceStats() {
        PerformanceStats stats;

        // This would collect actual statistics
        // For now, return basic information
        stats.totalExecutions = 0;
        stats.totalErrors = 0;
        stats.totalExecutionTime = Duration.zero;
        stats.averageExecutionTime = Duration.zero;
        stats.memoryUsageMB = 0.0;

        return stats;
    }

    private CustomLanguage getLanguage(string name) {
        // Try to get from LDK first
        try {
            return ldk.getLanguageSpec(name);
        } catch (Exception) {
            return null;
        }
    }

    private Value executeLanguage(CustomLanguage language, string code, SecureExecutionContext context) {
        // This would delegate to the language's interpreter
        // For now, use the built-in sandboxed execution
        return language.execute(code, context);
    }

    private void showREPLHelp(string languageName) {
        writeln("Help for " ~ languageName ~ " REPL:");
        writeln("  exit  - Exit the REPL");
        writeln("  help  - Show this help message");
        writeln("  Any other input will be executed as " ~ languageName ~ " code");
    }
}

/// Execution result
struct ExecutionResult {
    string languageName;
    string code;
    Value returnValue;
    string output;
    string error;
    int exitCode;
    Duration executionTime;

    @property bool success() {
        return exitCode == 0 && error.length == 0;
    }
}

/// Compilation result
struct CompilationResult {
    string languageName;
    string code;
    string intermediateCode;
    string error;
    bool success;
    Duration compilationTime;
}

/// Performance statistics
struct PerformanceStats {
    int totalExecutions;
    int totalErrors;
    Duration totalExecutionTime;
    Duration averageExecutionTime;
    double memoryUsageMB;
    string[] errorMessages;
}

/// Security exception
class SecurityException : Exception {
    this(string message) {
        super(message);
    }
}

/// Language optimizer
class LanguageOptimizer {
    private LanguageSpec spec;

    this(LanguageSpec spec) {
        this.spec = spec;
    }

    /// Optimize language for better performance
    LanguageSpec optimize() {
        LanguageSpec optimized = spec;

        // Optimize token patterns
        optimized = optimizeTokenPatterns(optimized);

        // Optimize grammar
        optimized = optimizeGrammar(optimized);

        // Optimize built-in functions
        optimized = optimizeBuiltinFunctions(optimized);

        return optimized;
    }

    private LanguageSpec optimizeTokenPatterns(LanguageSpec spec) {
        // Sort tokens by priority and merge compatible patterns
        TokenSpec[] optimizedTokens = spec.tokenSpecs.dup;
        optimizedTokens.sort!((a, b) => b.priority > a.priority);

        // Remove duplicate tokens
        TokenSpec[] uniqueTokens;
        string[string] seenNames;
        foreach(token; optimizedTokens) {
            if (!(token.name in seenNames)) {
                uniqueTokens ~= token;
                seenNames[token.name] = token.name;
            }
        }

        spec.tokenSpecs = uniqueTokens;
        return spec;
    }

    private LanguageSpec optimizeGrammar(LanguageSpec spec) {
        // Remove unreachable grammar rules
        // This would require more complex analysis
        return spec;
    }

    private LanguageSpec optimizeBuiltinFunctions(LanguageSpec spec) {
        // Optimize built-in function implementations
        // This could involve inlining, caching, etc.
        return spec;
    }
}

/// Language debugger
class LanguageDebugger {
    private CustomLanguage language;
    private ExecutionContext context;
    private bool[] breakpoints;
    private int currentLine = 0;
    private bool stepping = false;

    this(CustomLanguage language, ExecutionContext context) {
        this.language = language;
        this.context = context;
    }

    /// Start debugging session
    void startDebugging(string code) {
        writeln("Starting debugging session for " ~ language.name());
        writeln("Commands: step, continue, break <line>, variables, quit");

        breakpoints.length = code.splitLines().length + 1;
        breakpoints[] = false;

        stepping = true;

        while (true) {
            write("debug> ");
            string command = readln();
            if (command is null) break;

            command = command.strip().toLower();

            if (command == "quit") break;
            if (command == "step") {
                stepping = true;
                executeNextLine();
            } else if (command == "continue") {
                stepping = false;
                continueExecution();
            } else if (command.startsWith("break ")) {
                try {
                    int lineNum = to!int(command[6..$]);
                    setBreakpoint(lineNum);
                } catch (Exception) {
                    writeln("Invalid line number");
                }
            } else if (command == "variables") {
                showVariables();
            } else {
                writeln("Unknown command. Available: step, continue, break <line>, variables, quit");
            }
        }
    }

    private void executeNextLine() {
        // This would execute the next line of code
        writeln("Executing line " ~ to!string(currentLine + 1));
        currentLine++;
    }

    private void continueExecution() {
        // Continue execution until next breakpoint
        writeln("Continuing execution...");
        while (currentLine < breakpoints.length && !breakpoints[currentLine]) {
            executeNextLine();
        }
        writeln("Breakpoint hit at line " ~ to!string(currentLine));
    }

    private void setBreakpoint(int line) {
        if (line >= 0 && line < breakpoints.length) {
            breakpoints[line] = true;
            writeln("Breakpoint set at line " ~ to!string(line));
        } else {
            writeln("Invalid line number");
        }
    }

    private void showVariables() {
        // This would show current variable values
        writeln("Current variables:");
        // Implementation would depend on the language's variable system
    }
}
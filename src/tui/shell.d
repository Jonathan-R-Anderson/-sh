module tui.shell;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.path;
import std.file;
import core.thread;
import core.time;
import tui.core;
import tui.widgets;
import shell.config;
import shell.themes;
import shell.completion;
import shell.plugins;
import languages.framework;
import frontend;
import lferepl;
import shell.executor : execute;
import shell.parser : parseShellCommand;
import shell.ast : Node;

/// Panel types for TUI layout
enum PanelType {
    Command,
    Output,
    FileExplorer,
    ProcessManager,
    Help,
    Settings
}

/// Command history entry
struct HistoryEntry {
    string command;
    long timestamp;
    int returnCode;
}

/// TUI shell interface
class TUIShell {
    private TUIManager tuiManager;
    private ConfigManager configManager;
    private PluginManager pluginManager;
    private LanguageRegistry languageRegistry;
    private Theme currentTheme;
    private CompletionEngine completionEngine;

    // UI Components
    private CommandPane commandPane;
    private OutputPane outputPane;
    private FileExplorerPane fileExplorer;
    private ProcessManagerPane processManager;
    private HelpPane helpPane;
    private SettingsPane settingsPane;
    private StatusBar statusBar;

    // Layout
    private PanelType[PanelType] panels;
    private PanelType activePanel = PanelType.Command;
    private bool splitMode = false;
    private int mainPanelHeight = 0;

    // State
    private HistoryEntry[] commandHistory;
    private int historyPosition = -1;
    private string currentInput = "";
    private bool running = false;
    private bool needsRedraw = true;

    this(TUIManager tuiManager, ConfigManager configManager, PluginManager pluginManager, LanguageRegistry languageRegistry) {
        this.tuiManager = tuiManager;
        this.configManager = configManager;
        this.pluginManager = pluginManager;
        this.languageRegistry = languageRegistry;
        this.currentTheme = configManager.getShellContext().currentTheme;
        this.completionEngine = new CompletionEngine(configManager);

        initializeComponents();
        loadCommandHistory();
    }

    private void initializeComponents() {
        TerminalScreen screen = tuiManager.getScreen();
        int width = screen.getWidth();
        int height = screen.getHeight();

        // Calculate layout
        int statusHeight = 2;
        int helpHeight = 0;
        mainPanelHeight = height - statusHeight - helpHeight;

        // Create UI components
        commandPane = new CommandPane(tuiManager, configManager, completionEngine);
        outputPane = new OutputPane(tuiManager, configManager);
        fileExplorer = new FileExplorerPane(tuiManager, configManager);
        processManager = new ProcessManagerPane(tuiManager, configManager);
        helpPane = new HelpPane(tuiManager, configManager);
        settingsPane = new SettingsPane(tuiManager, configManager);
        statusBar = new StatusBar(tuiManager, configManager);

        // Register panels
        panels[PanelType.Command] = PanelType.Command;
        panels[PanelType.Output] = PanelType.Output;
        panels[PanelType.FileExplorer] = PanelType.FileExplorer;
        panels[PanelType.ProcessManager] = PanelType.ProcessManager;
        panels[PanelType.Help] = PanelType.Help;
        panels[PanelType.Settings] = PanelType.Settings;
    }

    void runInTUIMode() {
        running = true;
        TerminalScreen screen = tuiManager.getScreen();
        InputHandler inputHandler = tuiManager.getInputHandler();

        while (running) {
            if (needsRedraw) {
                render();
                needsRedraw = false;
            }

            // Handle input
            KeyEvent key = inputHandler.readKey();
            if (key.type != KeyType.Unknown) {
                handleInput(key);
            }

            // Handle resize
            tuiManager.handleResize();

            // Small delay to prevent high CPU usage
            Thread.sleep(dur!"msecs"(10));
        }
    }

    private void render() {
        TerminalScreen screen = tuiManager.getScreen();
        int width = screen.getWidth();
        int height = screen.getHeight();

        // Clear screen
        screen.clear();

        if (splitMode) {
            renderSplitLayout(width, height);
        } else {
            renderSingleLayout(width, height);
        }

        // Render status bar
        statusBar.render(Rect(0, height - 2, width, 2));

        // Render command input
        commandPane.render(Rect(0, height - 1, width, 1));

        screen.render();
    }

    private void renderSingleLayout(int width, int height) {
        Rect contentArea = Rect(0, 0, width, height - 3);

        switch (activePanel) {
            case PanelType.Command:
                // Command panel fills most of the screen with command history
                outputPane.render(contentArea);
                break;
            case PanelType.Output:
                outputPane.render(contentArea);
                break;
            case PanelType.FileExplorer:
                fileExplorer.render(contentArea);
                break;
            case PanelType.ProcessManager:
                processManager.render(contentArea);
                break;
            case PanelType.Help:
                helpPane.render(contentArea);
                break;
            case PanelType.Settings:
                settingsPane.render(contentArea);
                break;
            default:
                outputPane.render(contentArea);
                break;
        }
    }

    private void renderSplitLayout(int width, int height) {
        Rect contentArea = Rect(0, 0, width, height - 3);
        int splitWidth = width / 2;

        // Left panel - command output
        Rect leftArea = Rect(0, 0, splitWidth, contentArea.height);
        outputPane.render(leftArea);

        // Right panel - file explorer or process manager
        Rect rightArea = Rect(splitWidth + 1, 0, width - splitWidth - 1, contentArea.height);
        fileExplorer.render(rightArea);

        // Draw split divider
        screen.drawVLine(splitWidth, 0, contentArea.height, '│', Color.Gray);
    }

    private void handleInput(KeyEvent key) {
        // Handle global keys first
        if (handleGlobalKeys(key)) {
            return;
        }

        // Pass input to active panel
        switch (activePanel) {
            case PanelType.Command:
            case PanelType.Output:
                if (commandPane.handleInput(key)) {
                    // Command pane handled the input
                    return;
                }
                break;
            case PanelType.FileExplorer:
                if (fileExplorer.handleInput(key)) {
                    return;
                }
                break;
            case PanelType.ProcessManager:
                if (processManager.handleInput(key)) {
                    return;
                }
                break;
            case PanelType.Help:
                if (helpPane.handleInput(key)) {
                    return;
                }
                break;
            case PanelType.Settings:
                if (settingsPane.handleInput(key)) {
                    return;
                }
                break;
            default:
                break;
        }

        needsRedraw = true;
    }

    private bool handleGlobalKeys(KeyEvent key) {
        if (key.type == KeyType.Special) {
            switch (key.special) {
                case "f1":
                    activePanel = PanelType.Help;
                    needsRedraw = true;
                    return true;
                case "f2":
                    splitMode = !splitMode;
                    needsRedraw = true;
                    return true;
                case "f3":
                    activePanel = PanelType.FileExplorer;
                    needsRedraw = true;
                    return true;
                case "f4":
                    activePanel = PanelType.ProcessManager;
                    needsRedraw = true;
                    return true;
                case "f5":
                    // Refresh current panel
                    refreshCurrentPanel();
                    return true;
                case "f10":
                    // Toggle menu
                    return true;
                case "f12":
                    activePanel = PanelType.Settings;
                    needsRedraw = true;
                    return true;
                case "tab":
                    // Cycle through panels
                    cyclePanels();
                    return true;
                case "ctrl-q":
                    running = false;
                    return true;
                case "ctrl-o":
                    splitMode = !splitMode;
                    needsRedraw = true;
                    return true;
                default:
                    break;
            }
        }

        return false;
    }

    private void cyclePanels() {
        PanelType[] panelOrder = [
            PanelType.Command, PanelType.Output, PanelType.FileExplorer,
            PanelType.ProcessManager, PanelType.Help, PanelType.Settings
        ];

        int currentIndex = panelOrder.countUntil(activePanel);
        if (currentIndex >= 0) {
            activePanel = panelOrder[(currentIndex + 1) % panelOrder.length];
            needsRedraw = true;
        }
    }

    private void refreshCurrentPanel() {
        switch (activePanel) {
            case PanelType.FileExplorer:
                fileExplorer.refresh();
                break;
            case PanelType.ProcessManager:
                processManager.refresh();
                break;
            case PanelType.Output:
                outputPane.refresh();
                break;
            default:
                break;
        }
        needsRedraw = true;
    }

    void displayCommandResult(CommandResult result) {
        outputPane.addOutput(result.command, result.output, result.error);
        addToHistory(result.command, result.returnCode);
        needsRedraw = true;
    }

    void showCompletionSuggestions(CompletionResult[] suggestions) {
        if (suggestions.length > 0) {
            // Display completion popup
            displayCompletionPopup(suggestions);
        }
    }

    private void displayCompletionPopup(CompletionResult[] suggestions) {
        // TODO: Implement completion popup
        // For now, just add to output
        string completions = suggestions.map!(s => s.text).join(" ");
        outputPane.addOutput("Completions: " ~ completions, "", "");
        needsRedraw = true;
    }

    void showHelpDialog(string topic) {
        helpPane.showTopic(topic);
        activePanel = PanelType.Help;
        needsRedraw = true;
    }

    void toggleFileExplorer() {
        if (activePanel == PanelType.FileExplorer) {
            activePanel = PanelType.Output;
        } else {
            activePanel = PanelType.FileExplorer;
        }
        needsRedraw = true;
    }

    void showProcessManager() {
        processManager.refresh();
        activePanel = PanelType.ProcessManager;
        needsRedraw = true;
    }

    void exit() {
        running = false;
        saveCommandHistory();
    }

    private void loadCommandHistory() {
        string historyFile = configManager.getConfig("HISTFILE", "~/.sh_history");
        string expandedPath = expandTilde(historyFile);

        if (exists(expandedPath)) {
            try {
                string content = readText(expandedPath);
                foreach(line; content.splitLines()) {
                    if (line.strip().length > 0) {
                        HistoryEntry entry;
                        entry.command = line.strip();
                        entry.timestamp = Clock.currTime().stdTime();
                        entry.returnCode = 0;
                        commandHistory ~= entry;
                    }
                }
            } catch (Exception e) {
                // Could not load history
            }
        }
    }

    private void saveCommandHistory() {
        string historyFile = configManager.getConfig("HISTFILE", "~/.sh_history");
        string expandedPath = expandTilde(historyFile);

        try {
            string[] historyLines;
            foreach(entry; commandHistory) {
                historyLines ~= entry.command;
            }

            // Keep only the last N entries
            int maxSize = configManager.getConfigInt("HISTSIZE", 1000);
            if (historyLines.length > maxSize) {
                historyLines = historyLines[$-maxSize..$];
            }

            std.file.write(expandedPath, historyLines.join("\n") ~ "\n");
        } catch (Exception e) {
            // Could not save history
        }
    }

    private void addToHistory(string command, int returnCode) {
        if (command.strip().length == 0) return;

        HistoryEntry entry;
        entry.command = command.strip();
        entry.timestamp = Clock.currTime().stdTime();
        entry.returnCode = returnCode;

        commandHistory ~= entry;

        // Limit history size
        int maxSize = configManager.getConfigInt("HISTSIZE", 1000);
        if (commandHistory.length > maxSize) {
            commandHistory = commandHistory[$-maxSize..$];
        }

        historyPosition = -1; // Reset to end of history
    }

    HistoryEntry[] getHistory() {
        return commandHistory;
    }

    private TerminalScreen screen() {
        return tuiManager.getScreen();
    }

    private string expandTilde(string path) {
        if (path.startsWith("~/")) {
            string homeDir = environment.get("HOME", "");
            return homeDir ~ path[1..$];
        }
        return path;
    }
}

/// Command result structure
struct CommandResult {
    string command;
    string output;
    string error;
    int returnCode;
    Duration executionTime;

    this(string command, string output, string error, int returnCode, Duration executionTime = Duration.zero) {
        this.command = command;
        this.output = output;
        this.error = error;
        this.returnCode = returnCode;
        this.executionTime = executionTime;
    }
}
module tui.panes;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.path;
import std.file;
import std.datetime;
import core.thread;
import core.time;
import core.sys.posix.unistd;
import core.sys.posix.sys.wait;
import core.process;
import tui.core;
import shell.config;
import shell.themes;
import shell.completion;
import languages.framework;

/// Base class for all TUI panels
abstract class Panel {
    protected TUIManager tuiManager;
    protected ConfigManager configManager;
    protected Theme currentTheme;

    this(TUIManager tuiManager, ConfigManager configManager) {
        this.tuiManager = tuiManager;
        this.configManager = configManager;
        this.currentTheme = configManager.getShellContext().currentTheme;
    }

    abstract void render(Rect area);
    abstract bool handleInput(KeyEvent key);

    protected TerminalScreen screen() {
        return tuiManager.getScreen();
    }

    protected void writeCentered(Rect area, string text, Color fg = Color.White, Color bg = Color.Black, Style style = Style.Normal) {
        int textLength = cast(int)text.length;
        if (textLength > area.width) textLength = area.width;

        int startX = area.x + (area.width - textLength) / 2;
        int y = area.y + area.height / 2;

        screen().writeString(startX, y, text, fg, bg, style);
    }
}

/// Command input pane
class CommandPane : Panel {
    private CompletionEngine completionEngine;
    private string currentInput = "";
    private int cursorPosition = 0;
    private string[] completions;
    private int completionIndex = 0;
    private bool completionMode = false;
    private string prompt = ">> ";

    this(TUIManager tuiManager, ConfigManager configManager, CompletionEngine completionEngine) {
        super(tuiManager, configManager);
        this.completionEngine = completionEngine;
    }

    void render(Rect area) {
        // Draw prompt
        screen().writeString(area.x, area.y, prompt, Color.Green, Color.Black, Style.Bold);

        // Draw current input
        int inputX = area.x + cast(int)prompt.length;
        screen().writeString(inputX, area.y, currentInput, Color.White, Color.Black);

        // Set cursor position
        screen().setCursor(inputX + cursorPosition, area.y);

        // Show completions if in completion mode
        if (completionMode && completions.length > 0) {
            renderCompletionPopup(area);
        }
    }

    bool handleInput(KeyEvent key) {
        if (key.type == KeyType.Character) {
            insertChar(key.ch);
            return true;
        } else if (key.type == KeyType.Special) {
            return handleSpecialKey(key);
        }

        return false;
    }

    private bool handleSpecialKey(KeyEvent key) {
        switch (key.special) {
            case "backspace":
                deleteChar();
                return true;
            case "delete":
                deleteCharForward();
                return true;
            case "left":
                moveCursor(-1);
                return true;
            case "right":
                moveCursor(1);
                return true;
            case "home":
                cursorPosition = 0;
                return true;
            case "end":
                cursorPosition = cast(int)currentInput.length;
                return true;
            case "up":
                // Navigate through history
                return navigateHistory(-1);
            case "down":
                return navigateHistory(1);
            case "tab":
                toggleCompletion();
                return true;
            case "enter":
                executeCommand();
                return true;
            default:
                break;
        }
        return false;
    }

    private void insertChar(dchar ch) {
        if (ch >= 32 && ch <= 126) { // Printable characters
            currentInput = currentInput[0..cursorPosition] ~ ch ~ currentInput[cursorPosition..$];
            cursorPosition++;
            completionMode = false;
        }
    }

    private void deleteChar() {
        if (cursorPosition > 0) {
            currentInput = currentInput[0..cursorPosition-1] ~ currentInput[cursorPosition..$];
            cursorPosition--;
            completionMode = false;
        }
    }

    private void deleteCharForward() {
        if (cursorPosition < cast(int)currentInput.length) {
            currentInput = currentInput[0..cursorPosition] ~ currentInput[cursorPosition+1..$];
            completionMode = false;
        }
    }

    private void moveCursor(int delta) {
        cursorPosition += delta;
        if (cursorPosition < 0) cursorPosition = 0;
        if (cursorPosition > cast(int)currentInput.length) {
            cursorPosition = cast(int)currentInput.length;
        }
    }

    private void toggleCompletion() {
        if (!completionMode) {
            generateCompletions();
            completionMode = true;
            completionIndex = 0;
        } else {
            // Cycle through completions
            if (completions.length > 0) {
                completionIndex = (completionIndex + 1) % completions.length;
                applyCompletion();
            }
        }
    }

    private void generateCompletions() {
        if (currentInput.strip().length > 0) {
            CompletionResult[] results = completionEngine.generateCompletions(currentInput, cursorPosition);
            completions = results.map!(r => r.text).array;
        } else {
            completions.length = 0;
        }
    }

    private void applyCompletion() {
        if (completions.length > 0 && completionIndex < completions.length) {
            string completion = completions[completionIndex];

            // Find prefix to replace
            int wordStart = cursorPosition;
            while (wordStart > 0 && currentInput[wordStart-1] != ' ') {
                wordStart--;
            }

            currentInput = currentInput[0..wordStart] ~ completion ~ " ";
            cursorPosition = cast(int)currentInput.length;
        }
    }

    private void renderCompletionPopup(Rect area) {
        if (completions.length == 0) return;

        int popupWidth = 60;
        int popupHeight = min(10, cast(int)completions.length);
        int popupX = area.x + 2;
        int popupY = area.y - popupHeight - 1;

        // Ensure popup stays on screen
        if (popupY < 1) popupY = area.y + 1;

        Rect popupRect = Rect(popupX, popupY, popupWidth, popupHeight);

        // Draw popup box
        screen().drawBox(popupRect, Color.White, Color.Blue);
        screen().fillRect(Rect(popupX+1, popupY+1, popupWidth-2, popupHeight-2), ' ', Color.Black, Color.Blue);

        // Draw completions
        for (int i = 0; i < min(popupHeight-2, cast(int)completions.length); i++) {
            int completionIdx = (completionIndex + i) % completions.length;
            Color bgColor = (i == 0) ? Color.Yellow : Color.Blue;
            Color fgColor = (i == 0) ? Color.Black : Color.White;

            string completion = completions[completionIdx];
            if (completion.length > popupWidth - 4) {
                completion = completion[0..popupWidth-7] ~ "...";
            }

            screen().writeString(popupX + 2, popupY + 1 + i, completion, fgColor, bgColor);
        }
    }

    private bool navigateHistory(int direction) {
        // TODO: Implement history navigation
        return false;
    }

    private void executeCommand() {
        if (currentInput.strip().length > 0) {
            string command = currentInput.strip();
            currentInput = "";
            cursorPosition = 0;
            completionMode = false;

            // TODO: Execute command and handle result
        }
    }

    string getCurrentInput() { return currentInput; }
    void setCurrentInput(string input) { currentInput = input; cursorPosition = cast(int)input.length; }
    void setPrompt(string newPrompt) { prompt = newPrompt; }
}

/// Output display pane
class OutputPane : Panel {
    private string[] outputLines;
    private int scrollPosition = 0;
    private int maxLines = 1000;

    this(TUIManager tuiManager, ConfigManager configManager) {
        super(tuiManager, configManager);
    }

    void render(Rect area) {
        // Draw border
        screen().drawBox(area, Color.Gray, Color.Black);

        // Title
        screen().writeString(area.x + 2, area.y, "Output", Color.White, Color.Gray, Style.Bold);

        // Content area
        Rect contentArea = Rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2);

        int visibleLines = contentArea.height;
        int startIndex = max(0, cast(int)outputLines.length - visibleLines - scrollPosition);
        int endIndex = min(startIndex + visibleLines, cast(int)outputLines.length);

        for (int i = startIndex; i < endIndex; i++) {
            int lineY = contentArea.y + (i - startIndex);
            screen().writeLine(contentArea.x + 1, lineY, outputLines[i], Color.White, Color.Black);
        }

        // Scroll indicator
        if (outputLines.length > visibleLines) {
            float scrollPercent = cast(float)scrollPosition / (outputLines.length - visibleLines);
            int scrollThumbPos = contentArea.y + cast(int)(scrollPercent * contentArea.height);
            screen().writeChar(area.x + area.width - 2, scrollThumbPos, '█', Color.White);
        }
    }

    bool handleInput(KeyEvent key) {
        switch (key.special) {
            case "up":
            case "pageup":
                scrollUp();
                return true;
            case "down":
            case "pagedown":
                scrollDown();
                return true;
            case "home":
                scrollToTop();
                return true;
            case "end":
                scrollToBottom();
                return true;
            default:
                break;
        }
        return false;
    }

    void addOutput(string command, string output, string error) {
        // Add timestamp
        auto now = Clock.currTime();
        string timestamp = now.toISOExtString().split("T")[1][0..8]; // HH:MM:SS

        if (command.length > 0) {
            outputLines ~= timestamp ~ " > " ~ command;
        }

        if (output.length > 0) {
            foreach(line; output.splitLines()) {
                outputLines ~= line;
            }
        }

        if (error.length > 0) {
            outputLines ~= timestamp ~ " ERROR: " ~ error;
        }

        // Limit output lines
        if (outputLines.length > maxLines) {
            outputLines = outputLines[$-maxLines..$];
        }

        // Auto-scroll to bottom
        scrollPosition = 0;
    }

    void clear() {
        outputLines.length = 0;
        scrollPosition = 0;
    }

    void refresh() {
        // Output pane doesn't need refreshing
    }

    private void scrollUp() {
        scrollPosition = min(scrollPosition + 5, max(0, cast(int)outputLines.length - 10));
    }

    private void scrollDown() {
        scrollPosition = max(0, scrollPosition - 5);
    }

    private void scrollToTop() {
        scrollPosition = max(0, cast(int)outputLines.length - 10);
    }

    private void scrollToBottom() {
        scrollPosition = 0;
    }
}

/// File explorer pane
class FileExplorerPane : Panel {
    private string currentPath;
    private string[] directories;
    private string[] files;
    private int selectedIndex = 0;
    private int scrollPosition = 0;

    this(TUIManager tuiManager, ConfigManager configManager) {
        super(tuiManager, configManager);
        currentPath = getcwd();
        refresh();
    }

    void render(Rect area) {
        // Draw border
        screen().drawBox(area, Color.Gray, Color.Black);

        // Title with path
        string title = "File Explorer - " ~ currentPath;
        if (title.length > area.width - 4) {
            title = "..." ~ title[title.length - area.width + 7..$];
        }
        screen().writeString(area.x + 2, area.y, title, Color.White, Color.Gray, Style.Bold);

        // Content area
        Rect contentArea = Rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2);

        // List directories first
        int y = contentArea.y;
        int visibleItems = contentArea.height;
        int startIndex = scrollPosition;

        // Draw parent directory option
        if (currentPath != "/") {
            Color bgColor = (selectedIndex == 0) ? Color.Blue : Color.Black;
            Color fgColor = (selectedIndex == 0) ? Color.White : Color.Cyan;
            screen().writeLine(contentArea.x + 1, y, "..", fgColor, bgColor, Style.Bold);
            y++;
            startIndex--;
        }

        // Draw directories
        for (int i = max(0, startIndex); i < directories.length && y < contentArea.y + visibleItems - 1; i++) {
            int displayIndex = (currentPath != "/") ? i + 1 : i;
            Color bgColor = (displayIndex == selectedIndex) ? Color.Blue : Color.Black;
            Color fgColor = (displayIndex == selectedIndex) ? Color.White : Color.Cyan;

            screen().writeLine(contentArea.x + 1, y, directories[i] ~ "/", fgColor, bgColor, Style.Bold);
            y++;
        }

        // Draw files
        for (int i = max(0, startIndex - cast(int)directories.length); i < files.length && y < contentArea.y + visibleItems - 1; i++) {
            int displayIndex = (currentPath != "/") ? i + directories.length + 1 : i + directories.length;
            Color bgColor = (displayIndex == selectedIndex) ? Color.Blue : Color.Black;
            Color fgColor = (displayIndex == selectedIndex) ? Color.White : Color.White;

            screen().writeLine(contentArea.x + 1, y, files[i], fgColor, bgColor, Style.Normal);
            y++;
        }
    }

    bool handleInput(KeyEvent key) {
        switch (key.special) {
            case "up":
                selectPrevious();
                return true;
            case "down":
                selectNext();
                return true;
            case "pageup":
                pageUp();
                return true;
            case "pagedown":
                pageDown();
                return true;
            case "home":
                selectFirst();
                return true;
            case "end":
                selectLast();
                return true;
            case "enter":
                enterSelected();
                return true;
            default:
                break;
        }
        return false;
    }

    void refresh() {
        directories.length = 0;
        files.length = 0;

        try {
            foreach(DirEntry entry; dirEntries(currentPath, SpanMode.shallow)) {
                if (entry.isDir) {
                    directories ~= entry.name;
                } else {
                    files ~= entry.name;
                }
            }
        } catch (Exception e) {
            // Could not read directory
        }

        directories.sort();
        files.sort();

        selectedIndex = 0;
        scrollPosition = 0;
    }

    private void selectPrevious() {
        if (selectedIndex > 0) {
            selectedIndex--;
            updateScroll();
        }
    }

    private void selectNext() {
        int totalItems = cast(int)directories.length + cast(int)files.length;
        if (currentPath != "/") totalItems++; // Add parent directory

        if (selectedIndex < totalItems - 1) {
            selectedIndex++;
            updateScroll();
        }
    }

    private void selectFirst() {
        selectedIndex = 0;
        scrollPosition = 0;
    }

    private void selectLast() {
        int totalItems = cast(int)directories.length + cast(int)files.length;
        if (currentPath != "/") totalItems++;
        selectedIndex = totalItems - 1;
        updateScroll();
    }

    private void pageUp() {
        selectedIndex = max(0, selectedIndex - 10);
        updateScroll();
    }

    private void pageDown() {
        int totalItems = cast(int)directories.length + cast(int)files.length;
        if (currentPath != "/") totalItems++;
        selectedIndex = min(totalItems - 1, selectedIndex + 10);
        updateScroll();
    }

    private void updateScroll() {
        TerminalScreen scr = screen();
        int visibleItems = scr.getHeight() - 4; // Account for border and title
        int totalItems = cast(int)directories.length + cast(int)files.length;
        if (currentPath != "/") totalItems++;

        if (selectedIndex < scrollPosition) {
            scrollPosition = selectedIndex;
        } else if (selectedIndex >= scrollPosition + visibleItems) {
            scrollPosition = selectedIndex - visibleItems + 1;
        }
    }

    private void enterSelected() {
        if (selectedIndex == 0 && currentPath != "/") {
            // Parent directory
            currentPath = dirName(currentPath);
        } else {
            int index = selectedIndex;
            if (currentPath != "/") index--;

            if (index < directories.length) {
                // Enter directory
                string newPath = buildPath(currentPath, directories[index]);
                currentPath = newPath;
            } else {
                // File selected - could open in editor or viewer
                // TODO: Implement file handling
            }
        }

        refresh();
    }
}

/// Process manager pane
class ProcessManagerPane : Panel {
    private ProcessInfo[] processes;
    private int selectedIndex = 0;
    private int scrollPosition = 0;

    this(TUIManager tuiManager, ConfigManager configManager) {
        super(tuiManager, configManager);
        refresh();
    }

    void render(Rect area) {
        // Draw border
        screen().drawBox(area, Color.Gray, Color.Black);

        // Title
        screen().writeString(area.x + 2, area.y, "Process Manager", Color.White, Color.Gray, Style.Bold);

        // Content area
        Rect contentArea = Rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2);

        // Header
        screen().writeLine(contentArea.x, contentArea.y, "PID    NAME                    CPU   MEM", Color.White, Color.Black, Style.Bold);
        screen().drawHLine(contentArea.x, contentArea.y + 1, contentArea.width, '─', Color.Gray);

        // List processes
        int y = contentArea.y + 2;
        int visibleItems = contentArea.height - 3;
        int startIndex = scrollPosition;

        for (int i = startIndex; i < processes.length && i < startIndex + visibleItems; i++) {
            Color bgColor = (i == selectedIndex) ? Color.Blue : Color.Black;
            Color fgColor = (i == selectedIndex) ? Color.White : Color.White;

            string line = formatProcessLine(processes[i]);
            screen().writeLine(contentArea.x + 1, y, line, fgColor, bgColor);
            y++;
        }
    }

    bool handleInput(KeyEvent key) {
        switch (key.special) {
            case "up":
                selectPrevious();
                return true;
            case "down":
                selectNext();
                return true;
            case "refresh":
                refresh();
                return true;
            default:
                break;
        }
        return false;
    }

    void refresh() {
        processes.length = 0;

        try {
            // Get process list using ps command
            auto ps = execute(["ps", "aux"]);
            if (ps.status == 0) {
                string[] lines = ps.output.splitLines();

                // Skip header
                for (int i = 1; i < lines.length; i++) {
                    ProcessInfo info = parseProcessLine(lines[i]);
                    if (info.pid > 0) {
                        processes ~= info;
                    }
                }
            }
        } catch (Exception e) {
            // Could not get process list
        }

        // Sort by CPU usage
        processes.sort!((a, b) => a.cpuUsage > b.cpuUsage);

        selectedIndex = 0;
        scrollPosition = 0;
    }

    private void selectPrevious() {
        if (selectedIndex > 0) {
            selectedIndex--;
            updateScroll();
        }
    }

    private void selectNext() {
        if (selectedIndex < processes.length - 1) {
            selectedIndex++;
            updateScroll();
        }
    }

    private void updateScroll() {
        TerminalScreen scr = screen();
        int visibleItems = scr.getHeight() - 6; // Account for border, title, header

        if (selectedIndex < scrollPosition) {
            scrollPosition = selectedIndex;
        } else if (selectedIndex >= scrollPosition + visibleItems) {
            scrollPosition = selectedIndex - visibleItems + 1;
        }
    }

    private ProcessInfo parseProcessLine(string line) {
        ProcessInfo info;
        // Simplified parsing - in real implementation, this would be more robust
        auto parts = line.split();
        if (parts.length >= 11) {
            info.pid = parse!int(parts[1]);
            info.cpuUsage = parse!double(parts[2]);
            info.memoryUsage = parse!double(parts[3]);
            info.command = parts[10..$].join(" ");
        }
        return info;
    }

    private string formatProcessLine(ProcessInfo info) {
        return format("%-6d %-20s %-5.1f %-5.1f",
                     info.pid,
                     info.command.length > 20 ? info.command[0..20] : info.command,
                     info.cpuUsage,
                     info.memoryUsage);
    }
}

/// Process information structure
struct ProcessInfo {
    int pid;
    string command;
    double cpuUsage;
    double memoryUsage;
}

/// Help pane
class HelpPane : Panel {
    private string currentTopic = "general";
    private int scrollPosition = 0;

    this(TUIManager tuiManager, ConfigManager configManager) {
        super(tuiManager, configManager);
    }

    void render(Rect area) {
        // Draw border
        screen().drawBox(area, Color.Gray, Color.Black);

        // Title
        screen().writeString(area.x + 2, area.y, "Help - " ~ currentTopic, Color.White, Color.Gray, Style.Bold);

        // Content area
        Rect contentArea = Rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2);

        string helpText = getHelpText(currentTopic);
        string[] lines = helpText.splitLines();

        int visibleLines = contentArea.height;
        int startIndex = scrollPosition;

        for (int i = startIndex; i < lines.length && i < startIndex + visibleLines; i++) {
            screen().writeLine(contentArea.x + 1, contentArea.y + (i - startIndex), lines[i], Color.White, Color.Black);
        }
    }

    bool handleInput(KeyEvent key) {
        switch (key.special) {
            case "up":
            case "pageup":
                scrollPosition = max(0, scrollPosition - 5);
                return true;
            case "down":
            case "pagedown":
                scrollPosition = max(0, scrollPosition + 5);
                return true;
            default:
                break;
        }
        return false;
    }

    void showTopic(string topic) {
        currentTopic = topic;
        scrollPosition = 0;
    }

    private string getHelpText(string topic) {
        switch (topic) {
            case "general":
                return "LFE-SH TUI Mode Help

Navigation:
  F1       - Show this help
  F2       - Toggle split screen mode
  F3       - Open file explorer
  F4       - Open process manager
  F5       - Refresh current panel
  F10      - Toggle menu
  F12      - Open settings
  Tab      - Cycle through panels
  Ctrl+Q   - Exit TUI mode
  Ctrl+O   - Toggle split view

Command Input:
  Enter    - Execute command
  Tab      - Complete command/file
  Up/Down  - Navigate history
  Ctrl+C   - Cancel current input

Panels:
  Output   - Command output and history
  Files    - File browser and navigation
  Processes- System process manager
  Settings - Configuration options";

            case "navigation":
                return "Navigation Help

Keyboard Shortcuts:
  ↑/↓      - Navigate up/down
  PageUp/PageDown - Scroll faster
  Home/End - Jump to top/bottom
  Tab      - Switch between panels
  F1-F12   - Function keys for specific actions
  Ctrl+X   - Exit current mode

Mouse Support:
  Click    - Select items
  Scroll   - Navigate lists";

            default:
                return "No help available for topic: " ~ topic;
        }
    }
}

/// Settings pane
class SettingsPane : Panel {
    private int selectedIndex = 0;

    this(TUIManager tuiManager, ConfigManager configManager) {
        super(tuiManager, configManager);
    }

    void render(Rect area) {
        // Draw border
        screen().drawBox(area, Color.Gray, Color.Black);

        // Title
        screen().writeString(area.x + 2, area.y, "Settings", Color.White, Color.Gray, Style.Bold);

        // Content area
        Rect contentArea = Rect(area.x + 1, area.y + 1, area.width - 2, area.height - 2);

        string[] settings = [
            "Theme: " ~ configManager.getConfig("TUI_THEME", "default"),
            "Mouse: " ~ (configManager.getConfigBool("TUI_MOUSE", true) ? "Enabled" : "Disabled"),
            "History size: " ~ configManager.getConfig("HISTSIZE", "1000"),
            "Show startup: " ~ (configManager.getConfigBool("SHOW_STARTUP_MESSAGE", true) ? "Yes" : "No"),
            "",
            "F1-F4 - Toggle settings",
            "Enter - Apply changes",
            "Esc - Cancel"
        ];

        for (int i = 0; i < settings.length && i < contentArea.height - 1; i++) {
            Color bgColor = (i == selectedIndex) ? Color.Blue : Color.Black;
            Color fgColor = (i == selectedIndex) ? Color.White : Color.White;

            screen().writeLine(contentArea.x + 1, contentArea.y + i, settings[i], fgColor, bgColor);
        }
    }

    bool handleInput(KeyEvent key) {
        switch (key.special) {
            case "up":
                selectedIndex = max(0, selectedIndex - 1);
                return true;
            case "down":
                selectedIndex = min(4, selectedIndex + 1);
                return true;
            case "enter":
                applySetting();
                return true;
            case "escape":
                selectedIndex = 0;
                return true;
            default:
                break;
        }
        return false;
    }

    private void applySetting() {
        switch (selectedIndex) {
            case 0: // Theme
                string[] themes = ["default", "dark", "solarized"];
                string currentTheme = configManager.getConfig("TUI_THEME", "default");
                int currentIndex = themes.countUntil(currentTheme);
                string newTheme = themes[(currentIndex + 1) % themes.length];
                configManager.setConfig("TUI_THEME", newTheme);
                break;
            case 1: // Mouse
                bool currentMouse = configManager.getConfigBool("TUI_MOUSE", true);
                configManager.setConfig("TUI_MOUSE", currentMouse ? "false" : "true");
                break;
            case 2: // History size
                // TODO: Implement history size editing
                break;
            case 3: // Startup message
                bool currentStartup = configManager.getConfigBool("SHOW_STARTUP_MESSAGE", true);
                configManager.setConfig("SHOW_STARTUP_MESSAGE", currentStartup ? "false" : "true");
                break;
            default:
                break;
        }
    }
}

/// Status bar
class StatusBar : Panel {
    private string statusMessage = "Ready";
    private Clock.TimePoint lastUpdate;

    this(TUIManager tuiManager, ConfigManager configManager) {
        super(tuiManager, configManager);
        lastUpdate = Clock.currTime();
    }

    void render(Rect area) {
        // Draw background
        screen().fillRect(area, ' ', Color.Black, Color.Gray);

        // Left side - status message
        screen().writeString(area.x + 2, area.y, statusMessage, Color.Black, Color.Gray);

        // Right side - time and shortcuts
        auto now = Clock.currTime();
        string timeStr = now.toISOExtString().split("T")[1][0..8]; // HH:MM:SS
        string shortcuts = "Ctrl+Q=Exit F1=Help";

        string rightText = timeStr ~ " | " ~ shortcuts;
        int rightX = area.x + area.width - rightText.length - 2;
        screen().writeString(rightX, area.y, rightText, Color.Black, Color.Gray);

        // Update status periodically
        if (now - lastUpdate > 5.seconds) {
            updateStatus();
            lastUpdate = now;
        }
    }

    bool handleInput(KeyEvent key) {
        // Status bar doesn't handle input
        return false;
    }

    void setStatus(string message) {
        statusMessage = message;
    }

    private void updateStatus() {
        // Update status with system information
        statusMessage = "Ready";

        // Could add memory usage, CPU, etc.
    }
}
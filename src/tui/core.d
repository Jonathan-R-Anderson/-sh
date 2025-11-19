module tui.core;

import std.stdio;
import std.string;
import core.stdc.stdlib;
import core.stdc.stdio;
import core.sys.posix.unistd;
import core.sys.posix.termios;
import core.sys.posix.sys.ioctl;
import core.sys.posix.fcntl;
import std.conv : to;
import std.array;
import std.algorithm;
import shell.config;
import shell.themes;

/// Terminal capabilities and control
enum Color {
    Default = -1,
    Black = 0,
    Red = 1,
    Green = 2,
    Yellow = 3,
    Blue = 4,
    Magenta = 5,
    Cyan = 6,
    White = 7
}

/// Character style
enum Style {
    Normal = 0,
    Bold = 1,
    Dim = 2,
    Italic = 3,
    Underline = 4,
    Blink = 5,
    Reverse = 7,
    Hidden = 8
}

/// Box drawing characters
struct BoxChars {
    static immutable string[8] horizontal = ["─", "━", "═", "║", "│", "┃", "┌", "┐"];
    static immutable string[8] vertical = ["│", "┃", "║", "─", "━", "═", "└", "┘"];

    static immutable string UL_CORNER = "┌";
    static immutable string UR_CORNER = "┐";
    static immutable string LL_CORNER = "└";
    static immutable string LR_CORNER = "┘";
    static immutable string H_LINE = "─";
    static immutable string V_LINE = "│";
    static immutable string CROSS = "┼";
    static immutable string T_DOWN = "┬";
    static immutable string T_UP = "┴";
    static immutable string T_RIGHT = "├";
    static immutable string T_LEFT = "┤";
}

/// Character information for terminal buffer
struct CharInfo {
    dchar ch;
    Color fg;
    Color bg;
    Style style;

    this(dchar ch, Color fg = Color.Default, Color bg = Color.Default, Style style = Style.Normal) {
        this.ch = ch;
        this.fg = fg;
        this.bg = bg;
        this.style = style;
    }

    string toAnsi() const {
        if (fg == Color.Default && bg == Color.Default && style == Style.Normal) {
            return to!string(ch);
        }

        string result = "\033[";

        // Add style codes
        if (style != Style.Normal) {
            result ~= to!string(style);
        }

        // Add foreground color
        if (fg != Color.Default) {
            if (result.length > 2) result ~= ";";
            result ~= to!string(30 + fg);
        }

        // Add background color
        if (bg != Color.Default) {
            if (result.length > 2) result ~= ";";
            result ~= to!string(40 + bg);
        }

        result ~= "m" ~ to!string(ch) ~ "\033[0m";
        return result;
    }
}

/// Rectangle for screen operations
struct Rect {
    int x, y;
    int width, height;

    this(int x, int y, int width, int height) {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
    }

    bool contains(int px, int py) const {
        return px >= x && px < x + width && py >= y && py < y + height;
    }

    Rect intersect(Rect other) const {
        int newX = max(x, other.x);
        int newY = max(y, other.y);
        int newWidth = max(0, min(x + width, other.x + other.width) - newX);
        int newHeight = max(0, min(y + height, other.y + other.height) - newY);
        return Rect(newX, newY, newWidth, newHeight);
    }
}

/// Key event types
enum KeyType {
    Character,
    Special,
    Mouse,
    Resize,
    Unknown
}

/// Key event
struct KeyEvent {
    KeyType type;
    dchar ch;
    bool ctrl;
    bool alt;
    bool shift;
    string special; // Special key names like "up", "down", "f1", etc.
    int mouseX, mouseY; // For mouse events

    string toString() const {
        string result;
        if (ctrl) result ~= "ctrl-";
        if (alt) result ~= "alt-";
        if (shift) result ~= "shift-";

        if (type == KeyType.Character) {
            result ~= to!string(ch);
        } else if (type == KeyType.Special) {
            result ~= special;
        } else if (type == KeyType.Mouse) {
            result ~= "mouse(" ~ to!string(mouseX) ~ "," ~ to!string(mouseY) ~ ")";
        } else {
            result ~= "unknown";
        }

        return result;
    }
}

/// Terminal screen buffer
class TerminalScreen {
    private CharInfo[] buffer;
    private int width, height;
    private bool cursorVisible = true;
    private int cursorX = 0, cursorY = 0;
    private bool dirty = true;

    this(int width, int height) {
        resize(width, height);
    }

    void resize(int newWidth, int newHeight) {
        width = newWidth;
        height = newHeight;
        buffer.length = width * height;
        clear();
    }

    void clear() {
        foreach(ref cell; buffer) {
            cell = CharInfo(' ');
        }
        dirty = true;
    }

    void clearRect(Rect rect) {
        for (int y = rect.y; y < rect.y + rect.height && y < height; y++) {
            for (int x = rect.x; x < rect.x + rect.width && x < width; x++) {
                buffer[y * width + x] = CharInfo(' ');
            }
        }
        dirty = true;
    }

    void writeChar(int x, int y, dchar ch, Color fg = Color.Default, Color bg = Color.Default, Style style = Style.Normal) {
        if (x >= 0 && x < width && y >= 0 && y < height) {
            buffer[y * width + x] = CharInfo(ch, fg, bg, style);
            dirty = true;
        }
    }

    void writeString(int x, int y, string text, Color fg = Color.Default, Color bg = Color.Default, Style style = Style.Normal) {
        int currentX = x;
        foreach(dchar ch; text) {
            writeChar(currentX, y, ch, fg, bg, style);
            currentX++;
            if (currentX >= width) break;
        }
    }

    void writeLine(int x, int y, string text, Color fg = Color.Default, Color bg = Color.Default, Style style = Style.Normal) {
        writeString(x, y, text, fg, bg, style);
        // Clear rest of line
        for (int textX = x + cast(int)text.length; textX < width; textX++) {
            writeChar(textX, y, ' ', fg, bg, style);
        }
    }

    void drawBox(Rect rect, Color fg = Color.Default, Color bg = Color.Default, Style style = Style.Normal) {
        if (rect.width < 2 || rect.height < 2) return;

        // Draw corners
        writeChar(rect.x, rect.y, BoxChars.UL_CORNER[0], fg, bg, style);
        writeChar(rect.x + rect.width - 1, rect.y, BoxChars.UR_CORNER[0], fg, bg, style);
        writeChar(rect.x, rect.y + rect.height - 1, BoxChars.LL_CORNER[0], fg, bg, style);
        writeChar(rect.x + rect.width - 1, rect.y + rect.height - 1, BoxChars.LR_CORNER[0], fg, bg, style);

        // Draw horizontal lines
        for (int x = rect.x + 1; x < rect.x + rect.width - 1; x++) {
            writeChar(x, rect.y, BoxChars.H_LINE[0], fg, bg, style);
            writeChar(x, rect.y + rect.height - 1, BoxChars.H_LINE[0], fg, bg, style);
        }

        // Draw vertical lines
        for (int y = rect.y + 1; y < rect.y + rect.height - 1; y++) {
            writeChar(rect.x, y, BoxChars.V_LINE[0], fg, bg, style);
            writeChar(rect.x + rect.width - 1, y, BoxChars.V_LINE[0], fg, bg, style);
        }
    }

    void drawHLine(int x, int y, int length, dchar ch = '─', Color fg = Color.Default, Color bg = Color.Default) {
        for (int i = 0; i < length && x + i < width; i++) {
            writeChar(x + i, y, ch, fg, bg);
        }
    }

    void drawVLine(int x, int y, int length, dchar ch = '│', Color fg = Color.Default, Color bg = Color.Default) {
        for (int i = 0; i < length && y + i < height; i++) {
            writeChar(x, y + i, ch, fg, bg);
        }
    }

    void fillRect(Rect rect, dchar ch = ' ', Color fg = Color.Default, Color bg = Color.Default) {
        for (int y = rect.y; y < rect.y + rect.height && y < height; y++) {
            for (int x = rect.x; x < rect.x + rect.width && x < width; x++) {
                writeChar(x, y, ch, fg, bg);
            }
        }
    }

    void setCursor(int x, int y) {
        cursorX = max(0, min(width - 1, x));
        cursorY = max(0, min(height - 1, y));
    }

    void setCursorVisible(bool visible) {
        cursorVisible = visible;
    }

    void render() {
        if (!dirty) return;

        string output = "\033[H"; // Move cursor to home position

        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                output ~= buffer[y * width + x].toAnsi();
            }
            if (y < height - 1) {
                output ~= "\033[K\n"; // Clear to end of line
            }
        }

        // Set cursor position
        if (cursorVisible) {
            output ~= "\033[" ~ to!string(cursorY + 1) ~ ";" ~ to!string(cursorX + 1) ~ "H";
            output ~= "\033[?25h"; // Show cursor
        } else {
            output ~= "\033[?25l"; // Hide cursor
        }

        write(output);
        fflush(stdout);
        dirty = false;
    }

    int getWidth() const { return width; }
    int getHeight() const { return height; }

    bool isDirty() const { return dirty; }

    void markDirty() { dirty = true; }

    CharInfo getChar(int x, int y) {
        if (x >= 0 && x < width && y >= 0 && y < height) {
            return buffer[y * width + x];
        }
        return CharInfo(' ');
    }
}

/// Input handler
class InputHandler {
    private termios originalTermios;
    private bool rawMode = false;
    private bool mouseEnabled = false;

    this() {
        saveTerminalState();
    }

    ~this() {
        restoreTerminalState();
    }

    void enterRawMode() {
        if (rawMode) return;

        termios term;
        tcgetattr(STDIN_FILENO, &term);

        // Disable canonical mode, echo, and signals
        term.c_lflag &= ~(ICANON | ECHO | ISIG);

        // Minimum characters for non-canonical read
        term.c_cc[VMIN] = 1;
        term.c_cc[VTIME] = 0;

        tcsetattr(STDIN_FILENO, TCSANOW, &term);
        rawMode = true;

        // Enable mouse if needed
        if (mouseEnabled) {
            write("\033[?1000h"); // Enable mouse tracking
            write("\033[?1002h"); // Enable button event tracking
            write("\033[?1003h"); // Enable any event tracking
        }
    }

    void exitRawMode() {
        if (!rawMode) return;

        // Disable mouse
        if (mouseEnabled) {
            write("\033[?1000l"); // Disable mouse tracking
            write("\033[?1002l");
            write("\033[?1003l");
        }

        restoreTerminalState();
        rawMode = false;
    }

    void enableMouse(bool enable = true) {
        mouseEnabled = enable;
        if (rawMode) {
            if (enable) {
                write("\033[?1000h\033[?1002h\033[?1003h");
            } else {
                write("\033[?1000l\033[?1002l\033[?1003l");
            }
        }
    }

    KeyEvent readKey() {
        if (!rawMode) {
            return KeyEvent(KeyType.Unknown, '\0');
        }

        dchar[8] buffer;
        size_t bytesRead = read(STDIN_FILENO, buffer.ptr, buffer.sizeof);

        if (bytesRead == 0) {
            return KeyEvent(KeyType.Unknown, '\0');
        }

        string input = to!string(buffer[0..bytesRead]);

        // Handle escape sequences
        if (input[0] == '\033') {
            return parseEscapeSequence(input);
        }

        // Handle regular characters
        if (bytesRead == 1) {
            dchar ch = buffer[0];
            if (ch >= 32 && ch <= 126) { // Printable ASCII
                return KeyEvent(KeyType.Character, ch, false, false, false);
            } else if (ch == 127) { // Backspace
                KeyEvent key;
                key.type = KeyType.Special;
                key.special = "backspace";
                return key;
            }
        }

        return KeyEvent(KeyType.Unknown, '\0');
    }

    private KeyEvent parseEscapeSequence(string input) {
        if (input.length < 2) {
            return KeyEvent(KeyType.Unknown, '\0');
        }

        if (input[1] == '[') {
            // CSI sequences
            if (input.length >= 3) {
                char finalChar = input[$-1];
                string params = input[2..$-1];

                switch (finalChar) {
                    case 'A': return KeyEvent(KeyType.Special, '\0', false, false, false, "up");
                    case 'B': return KeyEvent(KeyType.Special, '\0', false, false, false, "down");
                    case 'C': return KeyEvent(KeyType.Special, '\0', false, false, false, "right");
                    case 'D': return KeyEvent(KeyType.Special, '\0', false, false, false, "left");
                    case 'H': return KeyEvent(KeyType.Special, '\0', false, false, false, "home");
                    case 'F': return KeyEvent(KeyType.Special, '\0', false, false, false, "end");
                    case '~':
                        if (params == "1") return KeyEvent(KeyType.Special, '\0', false, false, false, "home");
                        if (params == "2") return KeyEvent(KeyType.Special, '\0', false, false, false, "insert");
                        if (params == "3") return KeyEvent(KeyType.Special, '\0', false, false, false, "delete");
                        if (params == "4") return KeyEvent(KeyType.Special, '\0', false, false, false, "end");
                        if (params == "5") return KeyEvent(KeyType.Special, '\0', false, false, false, "pageup");
                        if (params == "6") return KeyEvent(KeyType.Special, '\0', false, false, false, "pagedown");
                        break;
                    case 'M':
                        // Mouse event
                        return parseMouseEvent(params);
                    default:
                        break;
                }
            }
        } else if (input[1] == 'O') {
            // SS3 sequences
            if (input.length >= 3) {
                switch (input[2]) {
                    case 'H': return KeyEvent(KeyType.Special, '\0', false, false, false, "home");
                    case 'F': return KeyEvent(KeyType.Special, '\0', false, false, false, "end");
                    default: break;
                }
            }
        }

        return KeyEvent(KeyType.Unknown, '\0');
    }

    private KeyEvent parseMouseEvent(string params) {
        // Simplified mouse parsing
        // Format: Cb ; Cx ; Cy
        auto parts = params.split(';');
        if (parts.length >= 3) {
            try {
                int button = to!int(parts[0]);
                int x = to!int(parts[1]) - 1;
                int y = to!int(parts[2]) - 1;

                KeyEvent key;
                key.type = KeyType.Mouse;
                key.mouseX = x;
                key.mouseY = y;

                if (button == 0 || button == 1 || button == 2) {
                    key.special = "mouse-press-" ~ to!string(button);
                } else if (button >= 64) {
                    key.special = "mouse-release";
                } else if (button >= 32) {
                    key.special = "mouse-drag";
                }

                return key;
            } catch (Exception) {
                // Fall through
            }
        }

        return KeyEvent(KeyType.Unknown, '\0');
    }

    private void saveTerminalState() {
        tcgetattr(STDIN_FILENO, &originalTermios);
    }

    private void restoreTerminalState() {
        tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios);
    }
}

/// Main TUI manager
class TUIManager {
    private TerminalScreen screen;
    private InputHandler inputHandler;
    private ConfigManager configManager;
    private Theme currentTheme;
    private bool initialized = false;
    private bool running = false;

    this(ConfigManager configManager) {
        this.configManager = configManager;
    }

    void initializeTUI() {
        if (initialized) return;

        // Get terminal size
        int width, height;
        getTerminalSize(width, height);

        // Initialize components
        screen = new TerminalScreen(width, height);
        inputHandler = new InputHandler();

        // Load theme
        string themeName = configManager.getConfig("TUI_THEME", "default");
        loadTheme(themeName);

        // Enter raw mode
        inputHandler.enterRawMode();

        // Enable mouse if configured
        if (configManager.getConfigBool("TUI_MOUSE", true)) {
            inputHandler.enableMouse(true);
        }

        // Clear screen and hide cursor
        write("\033[2J\033[?25l");
        fflush(stdout);

        initialized = true;
    }

    void exitTUI() {
        if (!initialized) return;

        running = false;

        // Restore terminal state
        inputHandler.exitRawMode();

        // Show cursor and clear screen
        write("\033[?25h\033[2J\033[H");
        fflush(stdout);

        initialized = false;
    }

    void enterTUIMode() {
        if (running) return;

        initializeTUI();
        running = true;

        // Initial render
        render();
    }

    void exitTUIMode() {
        if (!running) return;

        running = false;
        exitTUI();
    }

    void handleResize() {
        if (!initialized) return;

        int newWidth, newHeight;
        getTerminalSize(newWidth, newHeight);

        if (newWidth != screen.getWidth() || newHeight != screen.getHeight()) {
            screen.resize(newWidth, newHeight);
            render();
        }
    }

    void refresh() {
        if (!initialized || !running) return;

        render();
    }

    void render() {
        if (!initialized) return;

        // Clear screen
        write("\033[H");
        screen.clear();

        // Draw main UI layout
        drawMainLayout();

        // Render buffer
        screen.render();
    }

    private void drawMainLayout() {
        int width = screen.getWidth();
        int height = screen.getHeight();

        // Draw title bar
        screen.fillRect(Rect(0, 0, width, 1), ' ', Color.White, Color.Blue);
        screen.writeString(2, 0, "LFE-SH TUI Mode", Color.White, Color.Blue, Style.Bold);
        screen.writeString(width - 10, 0, "F1=Help", Color.White, Color.Blue);

        // Draw status bar
        screen.fillRect(Rect(0, height - 2, width, 1), ' ', Color.Black, Color.Gray);
        screen.writeString(2, height - 2, "Ready", Color.Black, Color.Gray);
        screen.writeString(width - 20, height - 2, "Ctrl+Q=Exit", Color.Black, Color.Gray);

        // Draw command input area
        screen.fillRect(Rect(0, height - 1, width, 1), ' ', Color.White, Color.Black);
        screen.writeString(1, height - 1, ">", Color.Green, Color.Black);

        // Main content area
        Rect contentArea = Rect(0, 1, width, height - 3);
        drawContentArea(contentArea);
    }

    private void drawContentArea(Rect area) {
        // Draw border
        screen.drawBox(area, Color.Gray, Color.Black);

        // Sample content
        screen.writeString(area.x + 2, area.y + 1, "Welcome to LFE-SH TUI Mode!", Color.Green, Color.Black, Style.Bold);
        screen.writeString(area.x + 2, area.y + 3, "Press F1 for help or Ctrl+Q to exit", Color.White, Color.Black);
    }

    private void getTerminalSize(out int width, out int height) {
        winsize ws;
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
            width = ws.ws_col;
            height = ws.ws_row;
        } else {
            // Fallback values
            width = 80;
            height = 24;
        }
    }

    private void loadTheme(string themeName) {
        // TODO: Load theme from theme manager
        currentTheme = Theme();
    }

    // Getters
    TerminalScreen getScreen() { return screen; }
    InputHandler getInputHandler() { return inputHandler; }
    bool isRunning() { return running; }
    bool isInitialized() { return initialized; }
}
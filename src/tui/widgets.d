module tui.widgets;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.datetime;
import core.thread;
import core.time;
import tui.core;
import shell.config;
import shell.themes;

/// Base widget interface
abstract class Widget {
    protected Rect bounds;
    protected bool focused = false;
    protected bool visible = true;
    protected bool enabled = true;
    protected Theme theme;

    this(Rect bounds, Theme theme = null) {
        this.bounds = bounds;
        this.theme = theme;
    }

    // Pure virtual methods
    abstract void draw(TerminalScreen screen);
    abstract bool handleInput(KeyEvent key);
    abstract void resize(int width, int height);

    // Common methods
    void setBounds(Rect newBounds) { bounds = newBounds; }
    Rect getBounds() { return bounds; }

    void setFocused(bool focused) { this.focused = focused; }
    bool isFocused() { return focused; }

    void setVisible(bool visible) { this.visible = visible; }
    bool isVisible() { return visible; }

    void setEnabled(bool enabled) { this.enabled = enabled; }
    bool isEnabled() { return enabled; }

    void setTheme(Theme theme) { this.theme = theme; }

    virtual bool canFocus() { return enabled && visible; }
}

/// Text input widget
class TextBox : Widget {
    private string text = "";
    private int cursorPosition = 0;
    private int scrollOffset = 0;
    private int maxLength = -1; // -1 = unlimited
    private bool passwordMode = false;
    private string placeholder = "";

    this(Rect bounds, string placeholder = "", bool passwordMode = false) {
        super(bounds);
        this.placeholder = placeholder;
        this.passwordMode = passwordMode;
    }

    void draw(TerminalScreen screen) {
        if (!visible) return;

        Color bgColor = focused ? Color.Blue : (enabled ? Color.White : Color.Gray);
        Color fgColor = enabled ? Color.Black : Color.Gray;
        Style textStyle = Style.Normal;

        // Draw border if focused
        if (focused) {
            screen.drawBox(bounds, Color.White, Color.Black);
            screen.fillRect(Rect(bounds.x + 1, bounds.y + 1, bounds.width - 2, bounds.height - 2), ' ', fgColor, bgColor);
        } else {
            screen.fillRect(bounds, ' ', fgColor, bgColor);
        }

        // Calculate visible text range
        string displayText = getDisplayText();
        int availableWidth = bounds.width - (focused ? 4 : 2); // Account for border
        if (displayText.length > availableWidth) {
            if (cursorPosition - scrollOffset > availableWidth - 1) {
                scrollOffset = cursorPosition - availableWidth + 1;
            }
            if (cursorPosition < scrollOffset) {
                scrollOffset = cursorPosition;
            }
            displayText = displayText[scrollOffset..$];
        }

        // Ensure displayText fits
        if (displayText.length > availableWidth) {
            displayText = displayText[0..availableWidth];
        }

        // Draw text
        int textX = bounds.x + (focused ? 2 : 1);
        int textY = bounds.y + bounds.height / 2;

        if (displayText.length == 0 && placeholder.length > 0 && !focused) {
            screen.writeString(textX, textY, placeholder, Color.Gray, bgColor);
        } else {
            screen.writeString(textX, textY, displayText, fgColor, bgColor);
        }

        // Draw cursor
        if (focused && enabled) {
            int cursorX = textX + (cursorPosition - scrollOffset);
            screen.setCursor(cursorX, textY);
            screen.setCursorVisible(true);
        }
    }

    bool handleInput(KeyEvent key) {
        if (!enabled || !focused) return false;

        if (key.type == KeyType.Character) {
            insertChar(key.ch);
            return true;
        } else if (key.type == KeyType.Special) {
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
                    cursorPosition = cast(int)text.length;
                    return true;
                default:
                    break;
            }
        }

        return false;
    }

    void resize(int width, int height) {
        bounds.width = width;
        bounds.height = height;
    }

    // Text manipulation methods
    void insertChar(dchar ch) {
        if (maxLength >= 0 && cast(int)text.length >= maxLength) return;

        text = text[0..cursorPosition] ~ ch ~ text[cursorPosition..$];
        cursorPosition++;
    }

    void deleteChar() {
        if (cursorPosition > 0) {
            text = text[0..cursorPosition-1] ~ text[cursorPosition..$];
            cursorPosition--;
        }
    }

    void deleteCharForward() {
        if (cursorPosition < cast(int)text.length) {
            text = text[0..cursorPosition] ~ text[cursorPosition+1..$];
        }
    }

    void moveCursor(int delta) {
        cursorPosition += delta;
        cursorPosition = max(0, min(cursorPosition, cast(int)text.length));
    }

    void setText(string newText) {
        text = newText;
        cursorPosition = cast(int)text.length;
        scrollOffset = 0;
    }

    string getText() { return text; }

    void setPlaceholder(string newPlaceholder) { placeholder = newPlaceholder; }
    void setMaxLength(int maxLen) { maxLength = maxLen; }
    void setPasswordMode(bool enabled) { passwordMode = enabled; }

    private string getDisplayText() {
        if (passwordMode) {
            string result;
            foreach(i; 0..text.length) {
                result ~= "•";
            }
            return result;
        }
        return text;
    }

    override bool canFocus() { return enabled && visible; }
}

/// Button widget
class Button : Widget {
    private string label = "";
    private bool pressed = false;
    void delegate() onClick;

    this(Rect bounds, string label, void delegate() onClick = null) {
        super(bounds);
        this.label = label;
        this.onClick = onClick;
    }

    void draw(TerminalScreen screen) {
        if (!visible) return;

        Color bgColor = pressed ? Color.Yellow : (focused ? Color.Blue : (enabled ? Color.Gray : Color.DarkGray));
        Color fgColor = enabled ? Color.Black : Color.Gray;
        Style textStyle = pressed ? Style.Bold : Style.Normal;

        // Draw button background
        screen.fillRect(bounds, ' ', fgColor, bgColor);

        // Draw border if focused
        if (focused) {
            screen.drawBox(bounds, Color.White, Color.Black);
        }

        // Draw label
        writeCenteredText(screen, bounds, label, fgColor, bgColor, textStyle);
    }

    bool handleInput(KeyEvent key) {
        if (!enabled || !focused) return false;

        if (key.type == KeyType.Special && key.special == "enter") {
            pressed = true;
            if (onClick) {
                onClick();
            }
            pressed = false;
            return true;
        }

        return false;
    }

    void resize(int width, int height) {
        bounds.width = width;
        bounds.height = height;
    }

    void setLabel(string newLabel) { label = newLabel; }
    string getLabel() { return label; }

    private void writeCenteredText(TerminalScreen screen, Rect area, string text, Color fg, Color bg, Style style) {
        if (text.length > area.width) {
            text = text[0..area.width-3] ~ "...";
        }

        int textX = area.x + (area.width - cast(int)text.length) / 2;
        int textY = area.y + area.height / 2;

        screen.writeString(textX, textY, text, fg, bg, style);
    }

    override bool canFocus() { return enabled && visible; }
}

/// List box widget
class ListBox : Widget {
    private string[] items;
    private int selectedIndex = -1;
    private int scrollPosition = 0;
    private bool multiSelect = false;
    private bool[] selectedFlags;

    this(Rect bounds, string[] items = []) {
        super(bounds);
        setItems(items);
    }

    void draw(TerminalScreen screen) {
        if (!visible) return;

        // Draw background
        Color bgColor = enabled ? Color.White : Color.Gray;
        screen.fillRect(bounds, ' ', Color.Black, bgColor);

        // Draw border if focused
        if (focused) {
            screen.drawBox(bounds, Color.White, Color.Black);
        }

        // Calculate visible range
        int visibleItems = bounds.height - (focused ? 2 : 0);
        int startIndex = scrollPosition;
        int endIndex = min(startIndex + visibleItems, cast(int)items.length);

        // Draw items
        for (int i = startIndex; i < endIndex; i++) {
            int displayIndex = i - startIndex;
            int y = bounds.y + (focused ? 1 : 0) + displayIndex;

            Color itemBgColor = (i == selectedIndex) ? Color.Blue : bgColor;
            Color itemFgColor = (i == selectedIndex) ? Color.White : Color.Black;
            Style itemStyle = (i == selectedIndex) ? Style.Bold : Style.Normal;

            // Add selection marker if multi-select
            string prefix = "";
            if (multiSelect && i < selectedFlags.length && selectedFlags[i]) {
                prefix = "✓ ";
            }

            string displayText = prefix ~ items[i];
            if (displayText.length > bounds.width - (focused ? 4 : 2)) {
                displayText = displayText[0..bounds.width - (focused ? 7 : 5)] ~ "...";
            }

            screen.writeString(bounds.x + (focused ? 2 : 1), y, displayText, itemFgColor, itemBgColor, itemStyle);
        }

        // Draw scroll indicator if needed
        if (items.length > visibleItems) {
            float scrollRatio = cast(float)visibleItems / items.length;
            int thumbHeight = max(1, cast(int)(scrollRatio * visibleItems));
            int thumbPosition = cast(int)((cast(float)scrollPosition / (items.length - visibleItems)) * (visibleItems - thumbHeight));

            for (int i = 0; i < thumbHeight; i++) {
                int scrollY = bounds.y + (focused ? 1 : 0) + thumbPosition + i;
                screen.writeChar(bounds.x + bounds.width - 1, scrollY, '█', Color.White);
            }
        }
    }

    bool handleInput(KeyEvent key) {
        if (!enabled || !focused || items.length == 0) return false;

        switch (key.special) {
            case "up":
                selectPrevious();
                return true;
            case "down":
                selectNext();
                return true;
            case "pageup":
                selectPreviousPage();
                return true;
            case "pagedown":
                selectNextPage();
                return true;
            case "home":
                selectFirst();
                return true;
            case "end":
                selectLast();
                return true;
            case "enter":
                if (multiSelect) {
                    toggleSelection();
                } else {
                    // Could trigger onSelected event
                }
                return true;
            case " ":
                if (multiSelect) {
                    toggleSelection();
                    return true;
                }
                break;
            default:
                break;
        }

        return false;
    }

    void resize(int width, int height) {
        bounds.width = width;
        bounds.height = height;
    }

    // List management
    void setItems(string[] newItems) {
        items = newItems;
        selectedIndex = (items.length > 0) ? 0 : -1;
        scrollPosition = 0;
        selectedFlags.length = items.length;
        selectedFlags[] = false;
    }

    void addItem(string item) {
        items ~= item;
        selectedFlags ~= false;
        if (selectedIndex == -1) selectedIndex = 0;
    }

    void removeItem(int index) {
        if (index >= 0 && index < items.length) {
            items = items[0..index] ~ items[index+1..$];
            selectedFlags = selectedFlags[0..index] ~ selectedFlags[index+1..$];
            if (selectedIndex >= items.length) {
                selectedIndex = items.length - 1;
            }
        }
    }

    void clear() {
        items.length = 0;
        selectedFlags.length = 0;
        selectedIndex = -1;
        scrollPosition = 0;
    }

    // Selection methods
    void selectPrevious() {
        if (selectedIndex > 0) {
            selectedIndex--;
            updateScroll();
        }
    }

    void selectNext() {
        if (selectedIndex < items.length - 1) {
            selectedIndex++;
            updateScroll();
        }
    }

    void selectPreviousPage() {
        int visibleItems = bounds.height - (focused ? 2 : 0);
        selectedIndex = max(0, selectedIndex - visibleItems);
        updateScroll();
    }

    void selectNextPage() {
        int visibleItems = bounds.height - (focused ? 2 : 0);
        selectedIndex = min(items.length - 1, selectedIndex + visibleItems);
        updateScroll();
    }

    void selectFirst() {
        selectedIndex = 0;
        scrollPosition = 0;
    }

    void selectLast() {
        selectedIndex = items.length - 1;
        updateScroll();
    }

    private void updateScroll() {
        int visibleItems = bounds.height - (focused ? 2 : 0);
        if (selectedIndex < scrollPosition) {
            scrollPosition = selectedIndex;
        } else if (selectedIndex >= scrollPosition + visibleItems) {
            scrollPosition = selectedIndex - visibleItems + 1;
        }
    }

    private void toggleSelection() {
        if (selectedIndex >= 0 && selectedIndex < selectedFlags.length) {
            selectedFlags[selectedIndex] = !selectedFlags[selectedIndex];
        }
    }

    // Getters
    string[] getItems() { return items; }
    int getSelectedIndex() { return selectedIndex; }
    string getSelectedItem() {
        return (selectedIndex >= 0 && selectedIndex < items.length) ? items[selectedIndex] : "";
    }

    int[] getSelectedIndices() {
        int[] selected;
        for (int i = 0; i < selectedFlags.length; i++) {
            if (selectedFlags[i]) {
                selected ~= i;
            }
        }
        return selected;
    }

    string[] getSelectedItems() {
        string[] selected;
        for (int i = 0; i < selectedFlags.length; i++) {
            if (selectedFlags[i] && i < items.length) {
                selected ~= items[i];
            }
        }
        return selected;
    }

    void setMultiSelect(bool enabled) { multiSelect = enabled; }
    bool isMultiSelect() { return multiSelect; }

    override bool canFocus() { return enabled && visible && items.length > 0; }
}

/// Dialog widget
class Dialog : Widget {
    private string title = "";
    private Widget content;
    private Button[] buttons;
    private int selectedButton = 0;
    bool delegate(int buttonIndex) onButtonPressed;
    bool delegate() onClose;

    this(Rect bounds, string title, Widget content = null) {
        super(bounds);
        this.title = title;
        this.content = content;
    }

    void draw(TerminalScreen screen) {
        if (!visible) return;

        // Draw dialog background
        screen.fillRect(bounds, ' ', Color.White, Color.Gray);
        screen.drawBox(bounds, Color.White, Color.Black);

        // Draw title
        if (title.length > 0) {
            string displayTitle = title;
            if (displayTitle.length > bounds.width - 4) {
                displayTitle = displayTitle[0..bounds.width-7] ~ "...";
            }
            screen.writeString(bounds.x + 2, bounds.y, displayTitle, Color.White, Color.Gray, Style.Bold);
        }

        // Draw content area
        if (content) {
            Rect contentArea = Rect(bounds.x + 1, bounds.y + 2, bounds.width - 2, bounds.height - 4);
            content.setBounds(contentArea);
            content.draw(screen);
        }

        // Draw buttons
        drawButtons(screen);
    }

    bool handleInput(KeyEvent key) {
        if (!enabled || !focused) return false;

        // Handle button navigation
        if (key.type == KeyType.Special) {
            switch (key.special) {
                case "left":
                    selectPreviousButton();
                    return true;
                case "right":
                    selectNextButton();
                    return true;
                case "tab":
                    // Cycle between content and buttons
                    if (content && content.isFocused()) {
                        content.setFocused(false);
                        focusButton(0);
                    } else {
                        unfocusAllButtons();
                        if (content) {
                            content.setFocused(true);
                        }
                    }
                    return true;
                case "enter":
                    activateCurrentButton();
                    return true;
                case "escape":
                    if (onClose) {
                        onClose();
                    }
                    return true;
                default:
                    break;
            }
        }

        // Pass input to content if it's focused
        if (content && content.isFocused()) {
            return content.handleInput(key);
        }

        // Pass input to focused button
        for (int i = 0; i < buttons.length; i++) {
            if (buttons[i].isFocused()) {
                return buttons[i].handleInput(key);
            }
        }

        return false;
    }

    void resize(int width, int height) {
        bounds.width = width;
        bounds.height = height;
    }

    // Button management
    void addButton(string label, void delegate() onClick = null) {
        Rect buttonRect = Rect(0, 0, label.length + 4, 3);
        Button button = new Button(buttonRect, label, onClick);
        buttons ~= button;
    }

    void clearButtons() {
        buttons.length = 0;
        selectedButton = 0;
    }

    private void drawButtons(TerminalScreen screen) {
        if (buttons.length == 0) return;

        // Calculate button positions
        int totalWidth = 0;
        foreach(button; buttons) {
            totalWidth += button.getBounds().width + 2;
        }
        totalWidth -= 2; // Remove extra spacing

        int startX = bounds.x + (bounds.width - totalWidth) / 2;
        int buttonY = bounds.y + bounds.height - 4;

        for (int i = 0; i < buttons.length; i++) {
            int buttonX = startX;
            for (int j = 0; j < i; j++) {
                buttonX += buttons[j].getBounds().width + 2;
            }

            Rect buttonRect = Rect(buttonX, buttonY, buttons[i].getBounds().width, buttons[i].getBounds().height);
            buttons[i].setBounds(buttonRect);
            buttons[i].setFocused(i == selectedButton && !content.isFocused());
            buttons[i].draw(screen);
        }
    }

    private void selectPreviousButton() {
        if (buttons.length > 0) {
            selectedButton = (selectedButton - 1 + buttons.length) % buttons.length;
            unfocusAllButtons();
            buttons[selectedButton].setFocused(true);
        }
    }

    private void selectNextButton() {
        if (buttons.length > 0) {
            selectedButton = (selectedButton + 1) % buttons.length;
            unfocusAllButtons();
            buttons[selectedButton].setFocused(true);
        }
    }

    private void focusButton(int index) {
        if (index >= 0 && index < buttons.length) {
            selectedButton = index;
            unfocusAllButtons();
            buttons[selectedButton].setFocused(true);
        }
    }

    private void unfocusAllButtons() {
        foreach(button; buttons) {
            button.setFocused(false);
        }
    }

    private void activateCurrentButton() {
        if (onButtonPressed) {
            onButtonPressed(selectedButton);
        }

        if (selectedButton >= 0 && selectedButton < buttons.length) {
            // Simulate button click
            buttons[selectedButton].handleInput(KeyEvent(KeyType.Special, '\0', false, false, false, "enter"));
        }
    }

    void setTitle(string newTitle) { title = newTitle; }
    string getTitle() { return title; }

    void setContent(Widget newContent) { content = newContent; }
    Widget getContent() { return content; }

    override bool canFocus() { return enabled && visible; }
}

/// Table widget
class Table : Widget {
    private string[] headers;
    private string[][] rows;
    private int[] columnWidths;
    private int selectedIndex = -1;
    private int scrollPosition = 0;
    private bool showHeaders = true;

    this(Rect bounds, string[] headers = []) {
        super(bounds);
        setHeaders(headers);
    }

    void draw(TerminalScreen screen) {
        if (!visible) return;

        // Draw background
        screen.fillRect(bounds, ' ', Color.Black, Color.White);

        // Draw border if focused
        if (focused) {
            screen.drawBox(bounds, Color.White, Color.Black);
        }

        int availableHeight = bounds.height - (focused ? 2 : 0);
        int startY = bounds.y + (focused ? 1 : 0);

        // Draw headers
        if (showHeaders && headers.length > 0) {
            drawRow(screen, startY, headers, Color.White, Color.Gray, Style.Bold);
            startY++;
            availableHeight--;

            // Draw header separator
            screen.drawHLine(bounds.x + (focused ? 1 : 0), startY, bounds.width - (focused ? 2 : 0), '─', Color.Gray);
            startY++;
            availableHeight--;
        }

        // Draw rows
        int visibleRows = min(availableHeight, cast(int)rows.length - scrollPosition);
        for (int i = 0; i < visibleRows; i++) {
            int rowIndex = scrollPosition + i;
            Color bgColor = (rowIndex == selectedIndex) ? Color.Blue : Color.White;
            Color fgColor = (rowIndex == selectedIndex) ? Color.White : Color.Black;
            Style rowStyle = (rowIndex == selectedIndex) ? Style.Bold : Style.Normal;

            if (rowIndex < rows.length) {
                drawRow(screen, startY + i, rows[rowIndex], fgColor, bgColor, rowStyle);
            }
        }
    }

    bool handleInput(KeyEvent key) {
        if (!enabled || !focused || rows.length == 0) return false;

        switch (key.special) {
            case "up":
                selectPrevious();
                return true;
            case "down":
                selectNext();
                return true;
            case "pageup":
                selectPreviousPage();
                return true;
            case "pagedown":
                selectNextPage();
                return true;
            case "home":
                selectFirst();
                return true;
            case "end":
                selectLast();
                return true;
            default:
                break;
        }

        return false;
    }

    void resize(int width, int height) {
        bounds.width = width;
        bounds.height = height;
        calculateColumnWidths();
    }

    private void drawRow(TerminalScreen screen, int y, string[] row, Color fg, Color bg, Style style) {
        int x = bounds.x + (focused ? 1 : 0);

        for (int col = 0; col < columnWidths.length && col < row.length; col++) {
            string cellText = row[col];
            if (cellText.length > columnWidths[col]) {
                cellText = cellText[0..columnWidths[col]-3] ~ "...";
            }

            screen.writeString(x, y, cellText, fg, bg, style);
            x += columnWidths[col] + 1; // +1 for spacing
        }
    }

    private void calculateColumnWidths() {
        if (headers.length == 0) return;

        int availableWidth = bounds.width - (focused ? 2 : 0) - (headers.length - 1);
        columnWidths.length = headers.length;

        // Start with header widths
        for (int i = 0; i < headers.length; i++) {
            columnWidths[i] = cast(int)headers[i].length + 2;
        }

        // Adjust for row content
        foreach(row; rows) {
            for (int i = 0; i < min(columnWidths.length, row.length); i++) {
                columnWidths[i] = max(columnWidths[i], cast(int)row[i].length + 2);
            }
        }

        // Scale to fit available width
        int totalRequired = columnWidths.sum();
        if (totalRequired > availableWidth) {
            float scale = cast(float)availableWidth / totalRequired;
            foreach(ref width; columnWidths) {
                width = cast(int)(width * scale);
                width = max(width, 4); // Minimum width
            }
        }
    }

    // Table management
    void setHeaders(string[] newHeaders) {
        headers = newHeaders;
        calculateColumnWidths();
    }

    void addRow(string[] row) {
        rows ~= row;
        if (selectedIndex == -1) {
            selectedIndex = 0;
        }
    }

    void setRows(string[][] newRows) {
        rows = newRows;
        selectedIndex = (rows.length > 0) ? 0 : -1;
        scrollPosition = 0;
        calculateColumnWidths();
    }

    void clear() {
        rows.length = 0;
        selectedIndex = -1;
        scrollPosition = 0;
    }

    // Selection methods
    void selectPrevious() {
        if (selectedIndex > 0) {
            selectedIndex--;
            updateScroll();
        }
    }

    void selectNext() {
        if (selectedIndex < rows.length - 1) {
            selectedIndex++;
            updateScroll();
        }
    }

    void selectPreviousPage() {
        int visibleRows = bounds.height - (focused ? 2 : 0) - (showHeaders ? 2 : 0);
        selectedIndex = max(0, selectedIndex - visibleRows);
        updateScroll();
    }

    void selectNextPage() {
        int visibleRows = bounds.height - (focused ? 2 : 0) - (showHeaders ? 2 : 0);
        selectedIndex = min(rows.length - 1, selectedIndex + visibleRows);
        updateScroll();
    }

    void selectFirst() {
        selectedIndex = 0;
        scrollPosition = 0;
    }

    void selectLast() {
        selectedIndex = rows.length - 1;
        updateScroll();
    }

    private void updateScroll() {
        int visibleRows = bounds.height - (focused ? 2 : 0) - (showHeaders ? 2 : 0);
        if (selectedIndex < scrollPosition) {
            scrollPosition = selectedIndex;
        } else if (selectedIndex >= scrollPosition + visibleRows) {
            scrollPosition = selectedIndex - visibleRows + 1;
        }
    }

    // Getters
    string[] getHeaders() { return headers; }
    string[][] getRows() { return rows; }
    int getSelectedIndex() { return selectedIndex; }
    string[] getSelectedRow() {
        return (selectedIndex >= 0 && selectedIndex < rows.length) ? rows[selectedIndex] : [];
    }

    void setShowHeaders(bool show) { showHeaders = show; }
    bool getShowHeaders() { return showHeaders; }

    override bool canFocus() { return enabled && visible && rows.length > 0; }
}
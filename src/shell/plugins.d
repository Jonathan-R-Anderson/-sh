module shell.plugins;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.file;
import std.path;
import std.json;
import std.dynamic;
import core.runtime;
import shell.config;

/// Plugin metadata
struct PluginMetadata {
    string name;
    string version;
    string description;
    string author;
    string[] dependencies;
    string[] permissions;
    string entryPoint;
    bool enabled;
}

/// Plugin information
struct CommandInfo {
    string name;
    string description;
    string usage;
    string[] examples;
}

/// Plugin interface
interface Plugin {
    string name();
    string version();
    string description();
    string[] dependencies();
    void initialize(ShellContext context);
    void cleanup();
    CommandInfo[] registerCommands();
    void onCommandExecuted(string command, string[] args);
    void onShellStartup();
    void onShellShutdown();
}

/// Shell context for plugins
class ShellContext {
    private ConfigManager configManager;
    private void[string] userData;

    this(ConfigManager configManager) {
        this.configManager = configManager;
    }

    ConfigManager getConfigManager() {
        return configManager;
    }

    void setUserData(string key, void* data) {
        userData[key] = data;
    }

    void* getUserData(string key) {
        return userData.get(key, null);
    }

    void removeUserData(string key) {
        userData.remove(key);
    }

    void log(string message) {
        writeln("[Plugin] ", message);
    }

    void error(string message) {
        writeln("[Plugin Error] ", message);
    }
}

/// Plugin manager
class PluginManager {
    private Plugin[string] loadedPlugins;
    private PluginMetadata[string] pluginMetadata;
    private string[] pluginPaths;
    private ShellContext shellContext;
    private ConfigManager configManager;

    this(ConfigManager configManager) {
        this.configManager = configManager;
        this.shellContext = new ShellContext(configManager);
        initializePluginPaths();
        loadPluginRegistry();
    }

    /// Initialize plugin search paths
    private void initializePluginPaths() {
        pluginPaths = [
            "~/.config/lfe-sh/plugins/",
            "/usr/local/lib/lfe-sh/plugins/",
            "/usr/lib/lfe-sh/plugins/",
            "./plugins/",
            "plugins/"
        ];
    }

    /// Load plugin registry
    private void loadPluginRegistry() {
        string registryFile = configManager.getConfig("PLUGIN_REGISTRY", "~/.config/lfe-sh/plugins.json");
        string expandedPath = expandTilde(registryFile);

        if (exists(expandedPath)) {
            try {
                string content = readText(expandedPath);
                JSONValue json = parseJSON(content);

                foreach(string pluginName, JSONValue pluginData; json.object) {
                    PluginMetadata metadata;
                    metadata.name = pluginName;
                    metadata.version = pluginData.object.get("version", JSONValue("1.0.0")).str;
                    metadata.description = pluginData.object.get("description", JSONValue("")).str;
                    metadata.author = pluginData.object.get("author", JSONValue("")).str;
                    metadata.enabled = pluginData.object.get("enabled", JSONValue(false)).bool_;

                    // Parse dependencies
                    if ("dependencies" in pluginData.object) {
                        foreach(JSONValue dep; pluginData["dependencies"].array) {
                            metadata.dependencies ~= dep.str;
                        }
                    }

                    // Parse permissions
                    if ("permissions" in pluginData.object) {
                        foreach(JSONValue perm; pluginData["permissions"].array) {
                            metadata.permissions ~= perm.str;
                        }
                    }

                    metadata.entryPoint = pluginData.object.get("entryPoint", JSONValue("")).str;

                    pluginMetadata[pluginName] = metadata;
                }
            } catch (Exception e) {
                writeln("Warning: Failed to load plugin registry: ", e.msg);
            }
        }
    }

    /// Save plugin registry
    private void savePluginRegistry() {
        string registryFile = configManager.getConfig("PLUGIN_REGISTRY", "~/.config/lfe-sh/plugins.json");
        string expandedPath = expandTilde(registryFile);

        JSONValue json = JSONValue();

        foreach(name, metadata; pluginMetadata) {
            JSONValue pluginData = JSONValue();
            pluginData.object["version"] = JSONValue(metadata.version);
            pluginData.object["description"] = JSONValue(metadata.description);
            pluginData.object["author"] = JSONValue(metadata.author);
            pluginData.object["enabled"] = JSONValue(metadata.enabled);
            pluginData.object["entryPoint"] = JSONValue(metadata.entryPoint);

            JSONValue deps = JSONValue();
            foreach(dep; metadata.dependencies) {
                deps.array ~= JSONValue(dep);
            }
            if (deps.array.length > 0) {
                pluginData.object["dependencies"] = deps;
            }

            JSONValue perms = JSONValue();
            foreach(perm; metadata.permissions) {
                perms.array ~= JSONValue(perm);
            }
            if (perms.array.length > 0) {
                pluginData.object["permissions"] = perms;
            }

            json.object[name] = pluginData;
        }

        try {
            ensurePathExists(dirName(expandedPath));
            std.file.write(expandedPath, json.toPrettyString());
        } catch (Exception e) {
            writeln("Error: Failed to save plugin registry: ", e.msg);
        }
    }

    /// Discover plugins in search paths
    string[] discoverPlugins() {
        string[] discovered;

        foreach(path; pluginPaths) {
            string expandedPath = expandTilde(path);
            if (exists(expandedPath) && isDir(expandedPath)) {
                try {
                    foreach(string pluginDir; dirEntries(expandedPath, SpanMode.shallow)) {
                        if (isDir(pluginDir)) {
                            string pluginName = baseName(pluginDir);
                            string manifestFile = buildPath(pluginDir, "plugin.json");

                            if (exists(manifestFile)) {
                                discovered ~= pluginDir;
                            }
                        }
                    }
                } catch (Exception e) {
                    writeln("Warning: Cannot scan plugin directory ", expandedPath, ": ", e.msg);
                }
            }
        }

        return discovered;
    }

    /// Load plugin from directory
    bool loadPlugin(string pluginPath) {
        string pluginDir = pluginPath.endsWith("/") ? pluginPath[0..$-1] : pluginPath;
        string pluginName = baseName(pluginDir);
        string manifestFile = buildPath(pluginDir, "plugin.json");

        if (!exists(manifestFile)) {
            writeln("Error: Plugin manifest not found: ", manifestFile);
            return false;
        }

        try {
            // Load manifest
            string manifestContent = readText(manifestFile);
            JSONValue manifest = parseJSON(manifestContent);

            PluginMetadata metadata;
            metadata.name = pluginName;
            metadata.version = manifest.object.get("version", JSONValue("1.0.0")).str;
            metadata.description = manifest.object.get("description", JSONValue("")).str;
            metadata.author = manifest.object.get("author", JSONValue("")).str;
            metadata.entryPoint = manifest.object.get("entryPoint", JSONValue("plugin.so")).str;

            // Parse dependencies
            if ("dependencies" in manifest.object) {
                foreach(JSONValue dep; manifest["dependencies"].array) {
                    metadata.dependencies ~= dep.str;
                }
            }

            // Parse permissions
            if ("permissions" in manifest.object) {
                foreach(JSONValue perm; manifest["permissions"].array) {
                    metadata.permissions ~= perm.str;
                }
            }

            // Check dependencies
            if (!checkDependencies(metadata.dependencies)) {
                writeln("Error: Plugin '", pluginName, "' has unmet dependencies");
                return false;
            }

            // Check permissions
            if (!checkPermissions(metadata.permissions)) {
                writeln("Error: Plugin '", pluginName, "' requires unavailable permissions");
                return false;
            }

            // Load the plugin library
            string libraryPath = buildPath(pluginDir, metadata.entryPoint);
            if (!exists(libraryPath)) {
                writeln("Error: Plugin library not found: ", libraryPath);
                return false;
            }

            Plugin plugin = loadPluginLibrary(libraryPath);
            if (plugin is null) {
                writeln("Error: Failed to load plugin library: ", libraryPath);
                return false;
            }

            // Initialize plugin
            plugin.initialize(shellContext);

            // Register plugin
            loadedPlugins[pluginName] = plugin;
            metadata.enabled = true;
            pluginMetadata[pluginName] = metadata;

            // Register commands
            auto commands = plugin.registerCommands();
            foreach(commandInfo; commands) {
                configManager.registerCompletion(commandInfo.name, null); // TODO: Add completion function
            }

            shellContext.log("Loaded plugin: " ~ pluginName ~ " v" ~ metadata.version);
            return true;

        } catch (Exception e) {
            writeln("Error: Failed to load plugin ", pluginName, ": ", e.msg);
            return false;
        }
    }

    /// Load plugin library (simplified implementation)
    private Plugin loadPluginLibrary(string libraryPath) {
        // This is a simplified version - in a real implementation,
        // you'd use dynamic library loading
        return null; // TODO: Implement dynamic library loading
    }

    /// Unload plugin
    bool unloadPlugin(string pluginName) {
        if (pluginName !in loadedPlugins) {
            writeln("Error: Plugin '", pluginName, "' is not loaded");
            return false;
        }

        try {
            Plugin plugin = loadedPlugins[pluginName];
            plugin.cleanup();

            loadedPlugins.remove(pluginName);

            if (pluginName in pluginMetadata) {
                pluginMetadata[pluginName].enabled = false;
            }

            shellContext.log("Unloaded plugin: " ~ pluginName);
            return true;

        } catch (Exception e) {
            writeln("Error: Failed to unload plugin ", pluginName, ": ", e.msg);
            return false;
        }
    }

    /// Check plugin dependencies
    private bool checkDependencies(string[] dependencies) {
        foreach(dependency; dependencies) {
            if (!isDependencySatisfied(dependency)) {
                return false;
            }
        }
        return true;
    }

    /// Check if dependency is satisfied
    private bool isDependencySatisfied(string dependency) {
        // Parse dependency version requirement (e.g., "lfe-sh>=1.0.0")
        auto parts = dependency.split(">=");
        if (parts.length == 2) {
            string depName = parts[0].strip();
            string requiredVersion = parts[1].strip();

            if (depName == "lfe-sh") {
                // TODO: Check shell version
                return true;
            }

            // Check if required plugin is loaded
            if (depName in loadedPlugins) {
                // TODO: Version comparison
                return true;
            }

            return false;
        }

        // Simple dependency name without version
        return (dependency in loadedPlugins);
    }

    /// Check plugin permissions
    private bool checkPermissions(string[] permissions) {
        foreach(permission; permissions) {
            if (!hasPermission(permission)) {
                return false;
            }
        }
        return true;
    }

    /// Check if permission is available
    private bool hasPermission(string permission) {
        // For now, allow all permissions
        // In a real implementation, you'd check against a permission system
        return true;
    }

    /// Get list of loaded plugins
    string[] listLoadedPlugins() {
        return loadedPlugins.keys.array;
    }

    /// Get plugin metadata
    PluginMetadata getPluginMetadata(string pluginName) {
        return pluginMetadata.get(pluginName, PluginMetadata());
    }

    /// Get plugin by name
    Plugin getPlugin(string pluginName) {
        return loadedPlugins.get(pluginName, null);
    }

    /// Enable plugin
    bool enablePlugin(string pluginName) {
        if (pluginName in pluginMetadata) {
            pluginMetadata[pluginName].enabled = true;
            savePluginRegistry();
            return true;
        }
        return false;
    }

    /// Disable plugin
    bool disablePlugin(string pluginName) {
        if (pluginName in pluginMetadata) {
            pluginMetadata[pluginName].enabled = false;
            savePluginRegistry();
            return true;
        }
        return false;
    }

    /// Reload plugin
    bool reloadPlugin(string pluginName) {
        if (pluginName in loadedPlugins) {
            string pluginPath = ""; // TODO: Get plugin path
            if (unloadPlugin(pluginName)) {
                return loadPlugin(pluginPath);
            }
        }
        return false;
    }

    /// Install plugin from archive
    bool installPlugin(string archivePath) {
        // TODO: Implement plugin installation from archive
        writeln("Plugin installation not yet implemented");
        return false;
    }

    /// Remove plugin
    bool removePlugin(string pluginName) {
        // Unload first
        if (pluginName in loadedPlugins) {
            unloadPlugin(pluginName);
        }

        // Remove from metadata
        if (pluginName in pluginMetadata) {
            pluginMetadata.remove(pluginName);
            savePluginRegistry();
        }

        // TODO: Remove plugin files
        writeln("Plugin file removal not yet implemented");
        return true;
    }

    /// Update all plugins
    void updatePlugins() {
        writeln("Plugin update not yet implemented");
    }

    /// Get plugin system statistics
    void printStatistics() {
        writeln("Plugin System Statistics:");
        writeln("  Loaded plugins: ", loadedPlugins.length);
        writeln("  Registered plugins: ", pluginMetadata.length);
        writeln("  Enabled plugins: ", pluginMetadata.values.count!(m => m.enabled));
        writeln("  Plugin search paths: ", pluginPaths.length);

        if (loadedPlugins.length > 0) {
            writeln("\nLoaded plugins:");
            foreach(name, plugin; loadedPlugins) {
                PluginMetadata metadata = pluginMetadata[name];
                writeln("  ", name, " v", metadata.version, " - ", metadata.description);
            }
        }
    }

    /// Notify plugins of shell startup
    void onShellStartup() {
        foreach(name, plugin; loadedPlugins) {
            try {
                plugin.onShellStartup();
            } catch (Exception e) {
                shellContext.error("Plugin " ~ name ~ " failed during startup: " ~ e.msg);
            }
        }
    }

    /// Notify plugins of shell shutdown
    void onShellShutdown() {
        foreach(name, plugin; loadedPlugins) {
            try {
                plugin.onShellShutdown();
            } catch (Exception e) {
                shellContext.error("Plugin " ~ name ~ " failed during shutdown: " ~ e.msg);
            }
        }
    }

    /// Notify plugins of command execution
    void onCommandExecuted(string command, string[] args) {
        foreach(name, plugin; loadedPlugins) {
            try {
                plugin.onCommandExecuted(command, args);
            } catch (Exception e) {
                shellContext.error("Plugin " ~ name ~ " failed during command execution: " ~ e.msg);
            }
        }
    }
}

/// Example plugin implementation
class ExamplePlugin : Plugin {
    private ShellContext context;

    string name() {
        return "example";
    }

    string version() {
        return "1.0.0";
    }

    string description() {
        return "Example plugin demonstrating the plugin system";
    }

    string[] dependencies() {
        return [];
    }

    void initialize(ShellContext context) {
        this.context = context;
        context.log("Example plugin initialized");
    }

    void cleanup() {
        context.log("Example plugin cleaned up");
    }

    CommandInfo[] registerCommands() {
        CommandInfo[] commands;

        CommandInfo hello;
        hello.name = "hello";
        hello.description = "Say hello from plugin";
        hello.usage = "hello [name]";
        hello.examples = ["hello", "hello World"];
        commands ~= hello;

        CommandInfo pluginInfo;
        pluginInfo.name = "plugin-info";
        pluginInfo.description = "Show plugin information";
        pluginInfo.usage = "plugin-info";
        pluginInfo.examples = ["plugin-info"];
        commands ~= pluginInfo;

        return commands;
    }

    void onCommandExecuted(string command, string[] args) {
        if (command == "hello") {
            context.log("Hello command executed with args: " ~ args.join(" "));
        }
    }

    void onShellStartup() {
        context.log("Example plugin: Shell started");
    }

    void onShellShutdown() {
        context.log("Example plugin: Shell shutting down");
    }
}
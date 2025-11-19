module commands.network;

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
import network.core;
import shell.executor;
import shell.config;
import shell.ast;

/// Base network command class
abstract class NetworkCommand {
    protected NetworkManager networkManager;
    protected ConfigManager configManager;

    this(NetworkManager networkManager, ConfigManager configManager) {
        this.networkManager = networkManager;
        this.configManager = configManager;
    }

    abstract void execute(CommandContext ctx, string[] args);
}

/// Curl-like HTTP client command
class CurlCommand : NetworkCommand {
    this(NetworkManager networkManager, ConfigManager configManager) {
        super(networkManager, configManager);
    }

    void execute(CommandContext ctx, string[] args) {
        if (args.length < 2) {
            writeln("Usage: curl [options] <url>");
            writeln("Options:");
            writeln("  -X METHOD  HTTP method (GET, POST, PUT, DELETE, HEAD)");
            writeln("  -d DATA    Data to send (POST/PUT)");
            writeln("  -H HEADER  Add header (format: 'Name: Value')");
            writeln("  -o FILE    Output to file");
            writeln("  -v         Verbose output");
            writeln("  -t TIMEOUT Request timeout in seconds");
            return;
        }

        // Parse arguments
        HTTPRequest request;
        string outputFile;
        bool verbose = false;
        int timeoutMs = 30000;

        string[] argList = args[1..$];
        int i = 0;
        while (i < argList.length) {
            string arg = argList[i];

            if (arg == "-X" && i + 1 < argList.length) {
                string method = argList[i + 1].toUpper();
                switch (method) {
                    case "GET": request.method = HTTPMethod.GET; break;
                    case "POST": request.method = HTTPMethod.POST; break;
                    case "PUT": request.method = HTTPMethod.PUT; break;
                    case "DELETE": request.method = HTTPMethod.DELETE; break;
                    case "HEAD": request.method = HTTPMethod.HEAD; break;
                    case "OPTIONS": request.method = HTTPMethod.OPTIONS; break;
                    case "PATCH": request.method = HTTPMethod.PATCH; break;
                    default:
                        writeln("Unknown HTTP method: " ~ method);
                        return;
                }
                i += 2;
            } else if (arg == "-d" && i + 1 < argList.length) {
                request.body = argList[i + 1];
                i += 2;
            } else if (arg == "-H" && i + 1 < argList.length) {
                string headerLine = argList[i + 1];
                auto colonPos = headerLine.indexOf(':');
                if (colonPos > 0) {
                    string name = headerLine[0..colonPos].strip();
                    string value = headerLine[colonPos + 1..$].strip();
                    request.headers[name] = value;
                }
                i += 2;
            } else if (arg == "-o" && i + 1 < argList.length) {
                outputFile = argList[i + 1];
                i += 2;
            } else if (arg == "-v") {
                verbose = true;
                i++;
            } else if (arg == "-t" && i + 1 < argList.length) {
                try {
                    timeoutMs = to!int(argList[i + 1]) * 1000;
                } catch (Exception) {
                    writeln("Invalid timeout value: " ~ argList[i + 1]);
                    return;
                }
                i += 2;
            } else if (!arg.startsWith("-")) {
                request.url = arg;
                i++;
            } else {
                writeln("Unknown option: " ~ arg);
                return;
            }
        }

        if (request.url.length == 0) {
            writeln("Error: No URL specified");
            return;
        }

        // Set timeout
        request.timeoutMs = timeoutMs;

        // Create HTTP client and execute request
        HTTPClient client = networkManager.createHTTPClient();
        HTTPResponse response = client.request(request);

        // Verbose output
        if (verbose) {
            auto parsedURL = URL.parse(request.url);
            writeln("*   Trying " ~ parsedURL.host ~ ":" ~ to!string(parsedURL.getEffectivePort()));
            writeln("* Connected to " ~ parsedURL.host ~ " (" ~ parsedURL.host ~ ")");
            writeln("> " ~ request.getMethodString() ~ " " ~ request.url ~ " HTTP/1.1");
            foreach(key, value; request.headers) {
                writeln("> " ~ key ~ ": " ~ value);
            }
            writeln(">");
        }

        // Handle response
        if (response.error != NetworkError.None) {
            writeln("Error: " ~ response.errorString);
            ctx.exitCode = 1;
            return;
        }

        // Status line
        if (verbose) {
            writeln("< HTTP/1.1 " ~ to!string(response.statusCode) ~ " " ~ response.statusMessage);
            foreach(key, value; response.headers) {
                writeln("< " ~ key ~ ": " ~ value);
            }
            writeln("<");
        }

        // Output
        if (outputFile.length > 0) {
            try {
                std.file.write(outputFile, response.body);
                if (verbose) {
                    writeln("* Response saved to " ~ outputFile);
                }
            } catch (Exception e) {
                writeln("Error writing to file: " ~ e.msg);
                ctx.exitCode = 1;
                return;
            }
        } else {
            write(response.body);
        }

        // Final verbose output
        if (verbose) {
            writeln("* Connection #0 to host " ~ URL.parse(request.url).host ~ " left intact");
        }

        ctx.exitCode = (response.statusCode >= 200 && response.statusCode < 300) ? 0 : 1;
    }
}

/// Wget-like downloader command
class WgetCommand : NetworkCommand {
    this(NetworkManager networkManager, ConfigManager configManager) {
        super(networkManager, configManager);
    }

    void execute(CommandContext ctx, string[] args) {
        if (args.length < 2) {
            writeln("Usage: wget [options] <url>");
            writeln("Options:");
            writeln("  -O FILE    Output file name");
            writeln("  -q         Quiet mode");
            writeln("  -v         Verbose mode");
            writeln("  -t NUMBER  Number of retries (default: 3)");
            writeln("  -T SECONDS Timeout in seconds (default: 30)");
            writeln("  --no-check-certificate  Don't check SSL certificates");
            return;
        }

        // Parse arguments
        string url;
        string outputFile;
        bool quiet = false;
        bool verbose = false;
        int maxRetries = 3;
        int timeoutSec = 30;
        bool checkCertificate = true;

        string[] argList = args[1..$];
        for (int i = 0; i < argList.length; i++) {
            string arg = argList[i];

            if (arg == "-O" && i + 1 < argList.length) {
                outputFile = argList[i + 1];
                i++;
            } else if (arg == "-q") {
                quiet = true;
            } else if (arg == "-v") {
                verbose = true;
            } else if (arg == "-t" && i + 1 < argList.length) {
                try {
                    maxRetries = to!int(argList[i + 1]);
                } catch (Exception) {
                    writeln("Invalid retry count: " ~ argList[i + 1]);
                    return;
                }
                i++;
            } else if (arg == "-T" && i + 1 < argList.length) {
                try {
                    timeoutSec = to!int(argList[i + 1]);
                } catch (Exception) {
                    writeln("Invalid timeout: " ~ argList[i + 1]);
                    return;
                }
                i++;
            } else if (arg == "--no-check-certificate") {
                checkCertificate = false;
            } else if (!arg.startsWith("-")) {
                url = arg;
            } else {
                writeln("Unknown option: " ~ arg);
                return;
            }
        }

        if (url.length == 0) {
            writeln("Error: No URL specified");
            return;
        }

        // Generate output filename if not specified
        if (outputFile.length == 0) {
            URL parsedURL = URL.parse(url);
            outputFile = baseName(parsedURL.path);
            if (outputFile.length == 0 || outputFile == "/") {
                outputFile = "index.html";
            }
        }

        // Download with retries
        HTTPClient client = networkManager.createHTTPClient();
        HTTPResponse response;

        for (int attempt = 0; attempt <= maxRetries; attempt++) {
            if (!quiet && attempt > 0) {
                writeln("Retrying (" ~ to!string(attempt) ~ "/" ~ to!string(maxRetries) ~ ")...");
            }

            HTTPRequest request;
            request.method = HTTPMethod.GET;
            request.url = url;
            request.timeoutMs = timeoutSec * 1000;

            response = client.get(request);

            if (response.error == NetworkError.None) {
                break;
            }

            if (attempt < maxRetries) {
                Thread.sleep(dur!"seconds"(1));
            }
        }

        // Handle response
        if (response.error != NetworkError.None) {
            writeln("Download failed: " ~ response.errorString);
            ctx.exitCode = 1;
            return;
        }

        if (!response.isSuccess) {
            writeln("HTTP error " ~ to!string(response.statusCode) ~ ": " ~ response.statusMessage);
            ctx.exitCode = 1;
            return;
        }

        // Save file
        try {
            std.file.write(outputFile, response.body);
            if (!quiet) {
                writeln("Saved '" ~ outputFile ~ "' [" ~ to!string(response.body.length) ~ "/" ~ to!string(response.body.length) ~ "]");
            }

            if (verbose) {
                writeln("HTTP response: " ~ to!string(response.statusCode) ~ " " ~ response.statusMessage);
                string contentType = response.header("Content-Type");
                if (contentType.length > 0) {
                    writeln("Content-Type: " ~ contentType);
                }
                writeln("File saved: " ~ outputFile);
            }

        } catch (Exception e) {
            writeln("Error writing file: " ~ e.msg);
            ctx.exitCode = 1;
            return;
        }

        ctx.exitCode = 0;
    }
}

/// Netcat-like network utility
class NetcatCommand : NetworkCommand {
    this(NetworkManager networkManager, ConfigManager configManager) {
        super(networkManager, configManager);
    }

    void execute(CommandContext ctx, string[] args) {
        if (args.length < 3) {
            writeln("Usage: netcat [options] <host> <port>");
            writeln("       netcat [options] -l <port>");
            writeln("Options:");
            writeln("  -l         Listen mode");
            writeln("  -v         Verbose output");
            writeln("  -w SECONDS Timeout for connections");
            writeln("  -p PORT    Local port for connections");
            return;
        }

        // Parse arguments
        bool listenMode = false;
        bool verbose = false;
        int timeoutSec = 0;
        string host;
        ushort port;
        ushort localPort = 0;

        string[] argList = args[1..$];
        for (int i = 0; i < argList.length; i++) {
            string arg = argList[i];

            if (arg == "-l") {
                listenMode = true;
            } else if (arg == "-v") {
                verbose = true;
            } else if (arg == "-w" && i + 1 < argList.length) {
                try {
                    timeoutSec = to!int(argList[i + 1]);
                } catch (Exception) {
                    writeln("Invalid timeout: " ~ argList[i + 1]);
                    return;
                }
                i++;
            } else if (arg == "-p" && i + 1 < argList.length) {
                try {
                    localPort = to!ushort(argList[i + 1]);
                } catch (Exception) {
                    writeln("Invalid local port: " ~ argList[i + 1]);
                    return;
                }
                i++;
            } else if (!arg.startsWith("-")) {
                if (host.length == 0) {
                    host = arg;
                } else {
                    try {
                        port = to!ushort(arg);
                    } catch (Exception) {
                        writeln("Invalid port: " ~ arg);
                        return;
                    }
                }
            } else {
                writeln("Unknown option: " ~ arg);
                return;
            }
        }

        if (listenMode) {
            // Server mode
            if (port == 0) {
                writeln("Error: Port required in listen mode");
                return;
            }

            if (verbose) {
                writeln("Listening on port " ~ to!string(port) ~ "...");
            }

            listenModeServer(port, verbose, timeoutSec);
        } else {
            // Client mode
            if (host.length == 0 || port == 0) {
                writeln("Error: Host and port required");
                return;
            }

            if (verbose) {
                writeln("Connecting to " ~ host ~ ":" ~ to!string(port) ~ "...");
            }

            clientMode(host, port, verbose, timeoutSec);
        }

        ctx.exitCode = 0;
    }

    private void clientMode(string host, ushort port, bool verbose, int timeoutSec) {
        try {
            TCPSocket connection = networkManager.createTCPConnection(host, port);

            if (verbose) {
                writeln("Connected to " ~ host ~ ":" ~ to!string(port));
            }

            // Set timeout if specified
            if (timeoutSec > 0) {
                connection.setTimeout(timeoutSec * 1000);
            }

            // Create threads for bidirectional communication
            bool running = true;

            // Thread to read from socket and write to stdout
            void socketToStdout() {
                while (running) {
                    try {
                        string data = connection.read(1024);
                        if (data.length == 0) break;
                        write(data);
                        fflush(stdout);
                    } catch (Exception) {
                        break;
                    }
                }
                running = false;
            }

            // Thread to read from stdin and write to socket
            void stdinToSocket() {
                while (running) {
                    try {
                        string line = readln();
                        if (line is null) break;
                        connection.write(line);
                    } catch (Exception) {
                        break;
                    }
                }
                running = false;
            }

            auto socketThread = new Thread(&socketToStdout);
            auto stdinThread = new Thread(&stdinToSocket);

            socketThread.start();
            stdinThread.start();

            socketThread.join();
            stdinThread.join();

            connection.close();

            if (verbose) {
                writeln("Connection closed");
            }

        } catch (NetworkException e) {
            writeln("Connection failed: " ~ e.msg);
        }
    }

    private void listenModeServer(ushort port, bool verbose, int timeoutSec) {
        try {
            UDPSocket socket = networkManager.createUDPSocket(port);

            if (verbose) {
                writeln("UDP server listening on port " ~ to!string(port));
            }

            ubyte[1024] buffer;

            while (true) {
                try {
                    string data = socket.receiveFrom(1024);
                    write(data);
                    fflush(stdout);
                } catch (Exception e) {
                    writeln("Error receiving data: " ~ e.msg);
                    break;
                }
            }

            socket.close();

        } catch (NetworkException e) {
            writeln("Failed to start server: " ~ e.msg);
        }
    }
}

/// Network interface information command
class InterfaceCommand : NetworkCommand {
    this(NetworkManager networkManager, ConfigManager configManager) {
        super(networkManager, configManager);
    }

    void execute(CommandContext ctx, string[] args) {
        if (args.length > 1 && (args[1] == "--help" || args[1] == "-h")) {
            writeln("Usage: interface [interface_name]");
            writeln("Shows network interface information");
            writeln("  If no interface specified, shows all interfaces");
            return;
        }

        string targetInterface = (args.length > 1) ? args[1] : null;

        try {
            // Get network interfaces
            string[] interfaces = getNetworkInterfaces();

            if (targetInterface !is null) {
                // Show specific interface
                bool found = false;
                foreach(iface; interfaces) {
                    if (iface == targetInterface) {
                        displayInterfaceInfo(iface);
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    writeln("Interface '" ~ targetInterface ~ "' not found");
                    ctx.exitCode = 1;
                }
            } else {
                // Show all interfaces
                if (interfaces.length == 0) {
                    writeln("No network interfaces found");
                    return;
                }

                foreach(iface; interfaces) {
                    displayInterfaceInfo(iface);
                    writeln();
                }
            }

        } catch (Exception e) {
            writeln("Error: " ~ e.msg);
            ctx.exitCode = 1;
        }
    }

    private void displayInterfaceInfo(string interfaceName) {
        writeln("Interface: " ~ interfaceName);
        writeln("  Status: " ~ getInterfaceStatus(interfaceName));
        writeln("  IPv4 Address: " ~ getInterfaceIPv4(interfaceName));
        writeln("  IPv6 Address: " ~ getInterfaceIPv6(interfaceName));
        writeln("  MAC Address: " ~ getInterfaceMAC(interfaceName));
        writeln("  MTU: " ~ getInterfaceMTU(interfaceName));
        writeln("  RX Packets: " ~ getInterfaceRxPackets(interfaceName));
        writeln("  TX Packets: " ~ getInterfaceTxPackets(interfaceName));
    }

    private string[] getNetworkInterfaces() {
        // This would use system calls to get network interfaces
        // For now, return a simple list
        return ["lo", "eth0", "wlan0"];
    }

    private string getInterfaceStatus(string interfaceName) {
        // Simplified implementation
        if (interfaceName == "lo") return "UP";
        return "UP"; // Assume all interfaces are up
    }

    private string getInterfaceIPv4(string interfaceName) {
        // Simplified implementation
        if (interfaceName == "lo") return "127.0.0.1";
        if (interfaceName == "eth0") return "192.168.1.100";
        if (interfaceName == "wlan0") return "192.168.1.101";
        return "N/A";
    }

    private string getInterfaceIPv6(string interfaceName) {
        // Simplified implementation
        if (interfaceName == "lo") return "::1";
        return "N/A";
    }

    private string getInterfaceMAC(string interfaceName) {
        // Simplified implementation
        return "00:00:00:00:00:00";
    }

    private string getInterfaceMTU(string interfaceName) {
        // Simplified implementation
        return "1500";
    }

    private string getInterfaceRxPackets(string interfaceName) {
        // Simplified implementation
        return "0";
    }

    private string getInterfaceTxPackets(string interfaceName) {
        // Simplified implementation
        return "0";
    }
}

/// Port scanner command
class PortScannerCommand : NetworkCommand {
    this(NetworkManager networkManager, ConfigManager configManager) {
        super(networkManager, configManager);
    }

    void execute(CommandContext ctx, string[] args) {
        if (args.length < 2) {
            writeln("Usage: portscan <host> [start_port-end_port]");
            writeln("Examples:");
            writeln("  portscan 192.168.1.1");
            writeln("  portscan 192.168.1.1 80-443");
            writeln("  portscan 192.168.1.1 22,80,443,8080");
            return;
        }

        string host = args[1];
        ushort[] portsToScan;

        if (args.length > 2) {
            string portSpec = args[2];

            if (portSpec.canFind('-')) {
                // Port range
                auto parts = portSpec.split('-');
                if (parts.length == 2) {
                    try {
                        ushort startPort = to!ushort(parts[0]);
                        ushort endPort = to!ushort(parts[1]);

                        for (ushort p = startPort; p <= endPort; p++) {
                            portsToScan ~= p;
                        }
                    } catch (Exception) {
                        writeln("Invalid port range: " ~ portSpec);
                        return;
                    }
                }
            } else if (portSpec.canFind(',')) {
                // Comma-separated list
                auto parts = portSpec.split(',');
                foreach(part; parts) {
                    try {
                        portsToScan ~= to!ushort(part);
                    } catch (Exception) {
                        writeln("Invalid port: " ~ part);
                        return;
                    }
                }
            } else {
                // Single port
                try {
                    portsToScan ~= to!ushort(portSpec);
                } catch (Exception) {
                    writeln("Invalid port: " ~ portSpec);
                    return;
                }
            }
        } else {
            // Default common ports
            ushort[] defaultPorts = [21, 22, 23, 25, 53, 80, 110, 143, 443, 993, 995, 8080, 8443];
            portsToScan = defaultPorts;
        }

        writeln("Scanning " ~ host ~ "...");
        writeln("Ports to scan: " ~ portsToScan.map!(p => to!string(p)).join(", "));
        writeln();

        int openPorts = 0;
        int closedPorts = 0;
        int filteredPorts = 0;

        foreach(port; portsToScan) {
            write("Port " ~ to!string(port).toLeftJust((portsToScan.length > 999) ? 5 : 4) ~ ": ");

            try {
                TCPSocket connection = networkManager.createTCPConnection(host, port);
                connection.close();
                writeln("OPEN");
                openPorts++;
            } catch (NetworkException) {
                writeln("CLOSED");
                closedPorts++;
            } catch (Exception) {
                writeln("FILTERED");
                filteredPorts++;
            }
        }

        writeln();
        writeln("Scan completed:");
        writeln("  Open:     " ~ to!string(openPorts));
        writeln("  Closed:   " ~ to!string(closedPorts));
        writeln("  Filtered: " ~ to!string(filteredPorts));

        ctx.exitCode = 0;
    }
}
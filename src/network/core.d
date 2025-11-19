module network.core;

import std.stdio;
import std.string;
import std.array;
import std.algorithm;
import std.conv : to;
import std.socket : AddressFamily, SocketType, ProtocolType, InternetAddress, Socket;
import std.datetime;
import core.thread;
import core.time;
import core.sys.posix.unistd;
import core.sys.posix.sys.socket;
import core.sys.posix.netinet.in;
import core.sys.posix.arpa.inet;
import core.sys.posix.errno;
import shell.config;

/// Network error types
enum NetworkError {
    None,
    ConnectionFailed,
    Timeout,
    ResolutionFailed,
    InvalidURL,
    SSLNotAvailable,
    ProtocolError
}

/// HTTP methods
enum HTTPMethod {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH
}

/// HTTP version
enum HTTPVersion {
    HTTP_1_0,
    HTTP_1_1,
    HTTP_2_0
}

/// HTTP response
struct HTTPResponse {
    int statusCode;
    string statusMessage;
    string[string] headers;
    string body;
    Duration requestTime;
    NetworkError error;
    string errorString;

    @property bool isSuccess() {
        return statusCode >= 200 && statusCode < 300;
    }

    @property string header(string name) {
        string lowerName = name.toLower();
        foreach(key, value; headers) {
            if (key.toLower() == lowerName) {
                return value;
            }
        }
        return null;
    }
}

/// HTTP request
struct HTTPRequest {
    HTTPMethod method;
    string url;
    HTTPVersion version = HTTPVersion.HTTP_1_1;
    string[string] headers;
    string body;
    int timeoutMs = 30000;

    string getMethodString() {
        switch (method) {
            case HTTPMethod.GET: return "GET";
            case HTTPMethod.POST: return "POST";
            case HTTPMethod.PUT: return "PUT";
            case HTTPMethod.DELETE: return "DELETE";
            case HTTPMethod.HEAD: return "HEAD";
            case HTTPMethod.OPTIONS: return "OPTIONS";
            case HTTPMethod.PATCH: return "PATCH";
            default: return "GET";
        }
    }
}

/// URL parser
struct URL {
    string protocol;
    string host;
    int port = -1; // -1 = default port
    string path;
    string query;
    string fragment;

    static URL parse(string urlString) {
        URL result;

        // Parse protocol
        auto protocolEnd = urlString.indexOf("://");
        if (protocolEnd > 0) {
            result.protocol = urlString[0..protocolEnd];
            urlString = urlString[protocolEnd + 3..$];
        } else {
            result.protocol = "http";
        }

        // Parse host and port
        int pathStart = urlString.indexOf('/');
        if (pathStart < 0) pathStart = urlString.length;

        string hostPort = urlString[0..pathStart];

        // Parse port if present
        auto portStart = hostPort.indexOf(':');
        if (portStart > 0) {
            result.host = hostPort[0..portStart];
            try {
                result.port = to!int(hostPort[portStart + 1..$]);
            } catch (Exception) {
                result.port = -1;
            }
        } else {
            result.host = hostPort;
        }

        // Parse path
        if (pathStart < urlString.length) {
            string pathQuery = urlString[pathStart..$];

            // Parse fragment
            auto fragmentStart = pathQuery.indexOf('#');
            if (fragmentStart >= 0) {
                result.fragment = pathQuery[fragmentStart + 1..$];
                pathQuery = pathQuery[0..fragmentStart];
            }

            // Parse query
            auto queryStart = pathQuery.indexOf('?');
            if (queryStart >= 0) {
                result.query = pathQuery[queryStart + 1..$];
                result.path = pathQuery[0..queryStart];
            } else {
                result.path = pathQuery;
            }
        } else {
            result.path = "/";
        }

        // Set default ports
        if (result.port == -1) {
            if (result.protocol == "https") {
                result.port = 443;
            } else {
                result.port = 80;
            }
        }

        return result;
    }

    int getEffectivePort() {
        if (port > 0) return port;
        return (protocol == "https") ? 443 : 80;
    }
}

/// Network manager
class NetworkManager {
    private ConfigManager configManager;
    private Socket[] activeSockets;
    private int maxConnections = 10;
    private int defaultTimeout = 30000; // 30 seconds
    private bool sslAvailable = false;

    this(ConfigManager configManager) {
        this.configManager = configManager;
        this.maxConnections = configManager.getConfigInt("MAX_CONNECTIONS", 10);
        this.defaultTimeout = configManager.getConfigInt("HTTP_TIMEOUT", 30000);
        this.sslAvailable = checkSSLAvailability();
    }

    /// Create TCP connection
    TCPSocket createTCPConnection(string host, ushort port) {
        try {
            auto socket = new TcpSocket;
            socket.connect(new InternetAddress(host, port));
            activeSockets ~= socket;
            return new TCPSocket(socket);
        } catch (Exception e) {
            throw new NetworkException("Failed to connect to " ~ host ~ ":" ~ to!string(port) ~ ": " ~ e.msg);
        }
    }

    /// Create UDP socket
    UDPSocket createUDPSocket(ushort port = 0) {
        try {
            auto socket = new UdpSocket;
            socket.bind(new InternetAddress("0.0.0.0", port));
            activeSockets ~= socket;
            return new UDPSocket(socket);
        } catch (Exception e) {
            throw new NetworkException("Failed to create UDP socket: " ~ e.msg);
        }
    }

    /// Create HTTP client
    HTTPClient createHTTPClient() {
        return new HTTPClient(this);
    }

    /// DNS resolution
    string[] resolveHostname(string hostname) {
        try {
            InternetAddress[] addresses = getAddress(hostname, 0);
            string[] result;
            foreach(addr; addresses) {
                result ~= addr.toAddrString();
            }
            return result;
        } catch (Exception e) {
            throw new NetworkException("DNS resolution failed for " ~ hostname ~ ": " ~ e.msg);
        }
    }

    /// Poll network events
    void pollEvents(int timeoutMs = 100) {
        // This would be implemented with select/poll/epoll
        // For now, it's a placeholder
    }

    /// Close all connections
    void closeAll() {
        foreach(socket; activeSockets) {
            try {
                socket.close();
            } catch (Exception) {
                // Ignore errors during cleanup
            }
        }
        activeSockets.length = 0;
    }

    /// Get connection count
    int getConnectionCount() {
        return cast(int)activeSockets.length;
    }

    /// Check SSL availability
    private bool checkSSLAvailability() {
        // This would check for OpenSSL/libressl availability
        // For now, return false
        return false;
    }

    /// Get SSL availability
    bool isSSLAvailable() {
        return sslAvailable;
    }

    ConfigManager getConfigManager() {
        return configManager;
    }
}

/// TCP socket wrapper
class TCPSocket {
    private Socket socket;

    this(Socket socket) {
        this.socket = socket;
    }

    ~this() {
        if (socket !is null) {
            try {
                socket.close();
            } catch (Exception) {
                // Ignore cleanup errors
            }
        }
    }

    void write(string data) {
        socket.send(data);
    }

    string read(int maxBytes = 4096) {
        ubyte[] buffer = new ubyte[maxBytes];
        int bytesRead = socket.receive(buffer);
        return cast(string)buffer[0..bytesRead];
    }

    void close() {
        if (socket !is null) {
            socket.close();
            socket = null;
        }
    }

    void setTimeout(int timeoutMs) {
        // Set socket timeout
        // Implementation depends on platform
    }

    bool isConnected() {
        return socket.isAlive();
    }
}

/// UDP socket wrapper
class UDPSocket {
    private Socket socket;

    this(Socket socket) {
        this.socket = socket;
    }

    ~this() {
        if (socket !is null) {
            try {
                socket.close();
            } catch (Exception) {
                // Ignore cleanup errors
            }
        }
    }

    void sendTo(string data, string host, ushort port) {
        try {
            InternetAddress address = new InternetAddress(host, port);
            ubyte[] sendData = cast(ubyte[])data;
            socket.sendTo(address, sendData);
        } catch (Exception e) {
            throw new NetworkException("Failed to send UDP data: " ~ e.msg);
        }
    }

    string receiveFrom(int maxBytes = 4096) {
        ubyte[] buffer = new ubyte[maxBytes];
        try {
            int bytesRead = socket.receiveFrom(buffer);
            return cast(string)buffer[0..bytesRead];
        } catch (Exception e) {
            throw new NetworkException("Failed to receive UDP data: " ~ e.msg);
        }
    }

    void close() {
        if (socket !is null) {
            socket.close();
            socket = null;
        }
    }
}

/// HTTP client
class HTTPClient {
    private NetworkManager networkManager;

    this(NetworkManager networkManager) {
        this.networkManager = networkManager;
    }

    /// Perform GET request
    HTTPResponse get(string url, string[string] headers = null) {
        HTTPRequest request;
        request.method = HTTPMethod.GET;
        request.url = url;
        if (headers !is null) {
            request.headers = headers;
        }
        return request(request);
    }

    /// Perform POST request
    HTTPResponse post(string url, string data, string[string] headers = null) {
        HTTPRequest request;
        request.method = HTTPMethod.POST;
        request.url = url;
        request.body = data;
        if (headers !is null) {
            request.headers = headers;
        }

        // Set content-type header if not provided
        if (!request.headers.any!(h => h.key.toLower() == "content-type")) {
            request.headers["Content-Type"] = "application/x-www-form-urlencoded";
        }

        return request(request);
    }

    /// Perform PUT request
    HTTPResponse put(string url, string data, string[string] headers = null) {
        HTTPRequest request;
        request.method = HTTPMethod.PUT;
        request.url = url;
        request.body = data;
        if (headers !is null) {
            request.headers = headers;
        }
        return request(request);
    }

    /// Perform DELETE request
    HTTPResponse del(string url, string[string] headers = null) {
        HTTPRequest request;
        request.method = HTTPMethod.DELETE;
        request.url = url;
        if (headers !is null) {
            request.headers = headers;
        }
        return request(request);
    }

    /// Perform HEAD request
    HTTPResponse head(string url, string[string] headers = null) {
        HTTPRequest request;
        request.method = HTTPMethod.HEAD;
        request.url = url;
        if (headers !is null) {
            request.headers = headers;
        }
        return request(request);
    }

    /// Perform custom request
    HTTPResponse request(HTTPRequest request) {
        HTTPResponse response;
        auto startTime = Clock.currTime();

        try {
            URL parsedURL = URL.parse(request.url);

            // Check SSL support
            if (parsedURL.protocol == "https" && !networkManager.isSSLAvailable()) {
                response.error = NetworkError.SSLNotAvailable;
                response.errorString = "HTTPS not available - OpenSSL/libressl not found";
                return response;
            }

            // Connect to server
            TCPSocket connection;
            if (parsedURL.protocol == "https") {
                connection = createSSLConnection(parsedURL.host, parsedURL.getEffectivePort());
            } else {
                connection = networkManager.createTCPConnection(parsedURL.host, parsedURL.getEffectivePort());
            }

            scope(exit) connection.close();

            // Build HTTP request
            string httpRequest = buildHTTPRequest(request, parsedURL);

            // Send request
            connection.write(httpRequest);

            // Read response
            string responseData = readHTTPResponse(connection, request);
            response = parseHTTPResponse(responseData);

        } catch (NetworkException e) {
            response.error = NetworkError.ConnectionFailed;
            response.errorString = e.msg;
        } catch (Exception e) {
            response.error = NetworkError.ProtocolError;
            response.errorString = e.msg;
        }

        response.requestTime = Clock.currTime() - startTime;
        return response;
    }

    private string buildHTTPRequest(HTTPRequest request, URL parsedURL) {
        string result;

        // Request line
        result ~= request.getMethodString() ~ " " ~ parsedURL.path;
        if (parsedURL.query.length > 0) {
            result ~= "?" ~ parsedURL.query;
        }
        result ~= " HTTP/1.1\r\n";

        // Host header
        result ~= "Host: " ~ parsedURL.host;
        if (parsedURL.getEffectivePort() != 80 && parsedURL.getEffectivePort() != 443) {
            result ~= ":" ~ to!string(parsedURL.getEffectivePort());
        }
        result ~= "\r\n";

        // User-Agent header
        if (!request.headers.any!(h => h.key.toLower() == "user-agent")) {
            result ~= "User-Agent: lfe-sh/1.0\r\n";
        }

        // Content-Length header for POST/PUT
        if ((request.method == HTTPMethod.POST || request.method == HTTPMethod.PUT) &&
            request.body.length > 0) {
            result ~= "Content-Length: " ~ to!string(request.body.length) ~ "\r\n";
        }

        // Custom headers
        foreach(key, value; request.headers) {
            result ~= key ~ ": " ~ value ~ "\r\n";
        }

        // End of headers
        result ~= "\r\n";

        // Body for POST/PUT
        if (request.body.length > 0) {
            result ~= request.body;
        }

        return result;
    }

    private string readHTTPResponse(TCPSocket connection, HTTPRequest request) {
        string result;
        string buffer;
        int contentLength = -1;
        bool chunked = false;
        bool headersComplete = false;

        connection.setTimeout(request.timeoutMs);

        while (true) {
            buffer = connection.read(4096);
            if (buffer.length == 0) break;

            result ~= buffer;

            // Parse headers if not complete
            if (!headersComplete) {
                auto headerEnd = result.indexOf("\r\n\r\n");
                if (headerEnd >= 0) {
                    headersComplete = true;

                    // Extract headers
                    string headersSection = result[0..headerEnd];
                    string[] headerLines = headersSection.split("\r\n");

                    foreach(line; headerLines[1..$]) { // Skip status line
                        auto colonPos = line.indexOf(':');
                        if (colonPos > 0) {
                            string headerName = line[0..colonPos].strip();
                            string headerValue = line[colonPos+1..$].strip();

                            if (headerName.toLower() == "content-length") {
                                contentLength = to!int(headerValue);
                            } else if (headerName.toLower() == "transfer-encoding" && headerValue.toLower() == "chunked") {
                                chunked = true;
                            }
                        }
                    }
                }
            }

            // Check if we have complete response
            if (headersComplete) {
                if (chunked) {
                    // Check for chunked termination
                    if (result.endsWith("0\r\n\r\n")) {
                        break;
                    }
                } else if (contentLength >= 0) {
                    // Check content length
                    auto headerEnd = result.indexOf("\r\n\r\n");
                    if (headerEnd >= 0) {
                        int bodyLength = result.length - headerEnd - 4;
                        if (bodyLength >= contentLength) {
                            break;
                        }
                    }
                }
            }

            // Check timeout
            if (Clock.currTime() - startTime > dur!"msecs"(request.timeoutMs)) {
                throw new NetworkException("Request timeout");
            }
        }

        return result;
    }

    private HTTPResponse parseHTTPResponse(string responseData) {
        HTTPResponse response;

        // Parse status line
        auto statusEnd = responseData.indexOf("\r\n");
        if (statusEnd < 0) {
            response.error = NetworkError.ProtocolError;
            response.errorString = "Invalid HTTP response";
            return response;
        }

        string statusLine = responseData[0..statusEnd];
        auto parts = statusLine.split(' ');
        if (parts.length >= 2) {
            try {
                response.statusCode = to!int(parts[1]);
                response.statusMessage = (parts.length > 2) ? parts[2..$].join(' ') : "";
            } catch (Exception) {
                response.statusCode = 500;
                response.statusMessage = "Invalid Status";
            }
        }

        // Parse headers
        auto headerEnd = responseData.indexOf("\r\n\r\n");
        if (headerEnd >= 0) {
            string headersSection = responseData[statusEnd + 2 .. headerEnd];
            string[] headerLines = headersSection.split("\r\n");

            foreach(line; headerLines) {
                auto colonPos = line.indexOf(':');
                if (colonPos > 0) {
                    string headerName = line[0..colonPos].strip();
                    string headerValue = line[colonPos + 1..$].strip();
                    response.headers[headerName] = headerValue;
                }
            }

            // Extract body
            response.body = responseData[headerEnd + 4 .. $];
        }

        return response;
    }

    private TCPSocket createSSLConnection(string host, ushort port) {
        // This would create an SSL/TLS connection
        // For now, throw an exception as SSL is not implemented
        throw new NetworkException("SSL/TLS not yet implemented");
    }

    private Clock.TimePoint startTime;
}

/// Network exception
class NetworkException : Exception {
    this(string message) {
        super(message);
    }
}
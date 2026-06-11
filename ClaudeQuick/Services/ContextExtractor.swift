import Foundation

enum ContextExtractorError: Error {
    case shellExecutionFailed(String)
    case gitOperationFailed(String)
    case fileReadingFailed(String)
    case invalidPath(String)
    case cacheMiss
    case encodingFailed
    case decodingFailed
}

class ContextExtractor {
    static let shared = ContextExtractor()

    private let fileManager = FileManager.default
    private let processQueue = DispatchQueue(label: "com.claudequick.contextextractor", attributes: .concurrent)
    private var cache: [String: CachedContext] = [:]
    private let cacheLock = NSLock()
    private let cacheExpirationInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Initialization

    init() {
        // Initialize cache
    }

    // MARK: - Public Methods

    /// Executes a shell command and captures its output
    /// - Parameters:
    ///   - command: The shell command to execute
    ///   - workingDirectory: Optional working directory for command execution
    /// - Returns: The stdout output of the command
    func executeShellCommand(_ command: String, workingDirectory: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw ContextExtractorError.shellExecutionFailed(errorString)
            }

            guard let output = String(data: outputData, encoding: .utf8) else {
                throw ContextExtractorError.encodingFailed
            }

            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw ContextExtractorError.shellExecutionFailed(error.localizedDescription)
        }
    }

    /// Reads the current git status of a repository
    /// - Parameter repositoryPath: Path to the git repository
    /// - Returns: Git status information as a string
    func readGitStatus(repositoryPath: String) throws -> String {
        let statusCommand = "cd '\(repositoryPath)' && git status --porcelain"
        return try executeShellCommand(statusCommand)
    }

    /// Reads the current git branch
    /// - Parameter repositoryPath: Path to the git repository
    /// - Returns: The current branch name
    func readGitBranch(repositoryPath: String) throws -> String {
        let branchCommand = "cd '\(repositoryPath)' && git rev-parse --abbrev-ref HEAD"
        return try executeShellCommand(branchCommand)
    }

    /// Reads recent git commits
    /// - Parameters:
    ///   - repositoryPath: Path to the git repository
    ///   - count: Number of recent commits to fetch (default: 5)
    /// - Returns: Recent commits as a formatted string
    func readGitLog(repositoryPath: String, count: Int = 5) throws -> String {
        let logCommand = "cd '\(repositoryPath)' && git log -\(count) --oneline"
        return try executeShellCommand(logCommand)
    }

    /// Reads git diff for current changes
    /// - Parameter repositoryPath: Path to the git repository
    /// - Returns: Git diff output
    func readGitDiff(repositoryPath: String) throws -> String {
        let diffCommand = "cd '\(repositoryPath)' && git diff"
        return try executeShellCommand(diffCommand)
    }

    /// Extracts a file tree structure of a directory
    /// - Parameters:
    ///   - directoryPath: Path to the directory
    ///   - maxDepth: Maximum directory depth to traverse (default: 3)
    ///   - excludePatterns: Patterns of files/folders to exclude
    /// - Returns: A formatted file tree as a string
    func extractFileTree(
        directoryPath: String,
        maxDepth: Int = 3,
        excludePatterns: [String] = ["node_modules", ".git", ".build", "Pods", ".xcodeproj"]
    ) throws -> String {
        guard fileManager.fileExists(atPath: directoryPath) else {
            throw ContextExtractorError.invalidPath(directoryPath)
        }

        var tree = ""
        try buildFileTree(
            directoryPath: directoryPath,
            prefix: "",
            depth: 0,
            maxDepth: maxDepth,
            excludePatterns: excludePatterns,
            output: &tree
        )

        return tree
    }

    /// Caches extraction results with automatic expiration
    /// - Parameters:
    ///   - key: Cache key identifier
    ///   - context: The context data to cache
    func cacheContext(_ context: CachedContext, forKey key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        cache[key] = context
    }

    /// Retrieves cached context if available and not expired
    /// - Parameter key: Cache key identifier
    /// - Returns: Cached context if available and fresh
    func retrieveCachedContext(forKey key: String) throws -> CachedContext {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let cachedContext = cache[key] else {
            throw ContextExtractorError.cacheMiss
        }

        if Date().timeIntervalSince(cachedContext.timestamp) > cacheExpirationInterval {
            cache.removeValue(forKey: key)
            throw ContextExtractorError.cacheMiss
        }

        return cachedContext
    }

    /// Clears the cache
    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        cache.removeAll()
    }

    /// Clears a specific cache entry
    func clearCache(forKey key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        cache.removeValue(forKey: key)
    }

    /// Extracts comprehensive context from a git repository
    /// - Parameter repositoryPath: Path to the git repository
    /// - Returns: A comprehensive RepositoryContext object
    func extractRepositoryContext(repositoryPath: String) throws -> RepositoryContext {
        // Check cache first
        let cacheKey = "repo_context_\(repositoryPath)"
        if let cachedContext = try? retrieveCachedContext(forKey: cacheKey) {
            return cachedContext.repositoryContext
        }

        var results = RepositoryContext(
            repositoryPath: repositoryPath,
            branch: "",
            status: "",
            recentCommits: "",
            fileTree: "",
            extractedAt: Date()
        )

        // Execute operations concurrently
        let group = DispatchGroup()
        var errors: [Error] = []
        let errorLock = NSLock()

        group.enter()
        processQueue.async {
            do {
                results.branch = try self.readGitBranch(repositoryPath: repositoryPath)
            } catch {
                errorLock.lock()
                errors.append(error)
                errorLock.unlock()
            }
            group.leave()
        }

        group.enter()
        processQueue.async {
            do {
                results.status = try self.readGitStatus(repositoryPath: repositoryPath)
            } catch {
                errorLock.lock()
                errors.append(error)
                errorLock.unlock()
            }
            group.leave()
        }

        group.enter()
        processQueue.async {
            do {
                results.recentCommits = try self.readGitLog(repositoryPath: repositoryPath)
            } catch {
                errorLock.lock()
                errors.append(error)
                errorLock.unlock()
            }
            group.leave()
        }

        group.enter()
        processQueue.async {
            do {
                results.fileTree = try self.extractFileTree(directoryPath: repositoryPath)
            } catch {
                errorLock.lock()
                errors.append(error)
                errorLock.unlock()
            }
            group.leave()
        }

        group.wait()

        // If any critical operation failed, throw the first error
        if !errors.isEmpty {
            throw errors[0]
        }

        // Cache the result
        let cachedContext = CachedContext(
            repositoryContext: results,
            timestamp: Date()
        )
        cacheContext(cachedContext, forKey: cacheKey)

        return results
    }

    // MARK: - Private Methods

    private func buildFileTree(
        directoryPath: String,
        prefix: String,
        depth: Int,
        maxDepth: Int,
        excludePatterns: [String],
        output: inout String
    ) throws {
        guard depth < maxDepth else { return }

        let contents = try fileManager.contentsOfDirectory(atPath: directoryPath)
        let sortedContents = contents.sorted()

        for (index, item) in sortedContents.enumerated() {
            let itemPath = (directoryPath as NSString).appendingPathComponent(item)

            // Check if item matches exclude patterns
            if excludePatterns.contains(where: { item.contains($0) }) {
                continue
            }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDir) else {
                continue
            }

            let isLast = index == sortedContents.count - 1
            let connector = isLast ? "└── " : "├── "
            let nextPrefix = prefix + (isLast ? "    " : "│   ")

            output += prefix + connector + item + (isDir.boolValue ? "/" : "") + "\n"

            if isDir.boolValue {
                try buildFileTree(
                    directoryPath: itemPath,
                    prefix: nextPrefix,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    excludePatterns: excludePatterns,
                    output: &output
                )
            }
        }
    }
}

// MARK: - Supporting Types

struct RepositoryContext: Codable {
    let repositoryPath: String
    var branch: String
    var status: String
    var recentCommits: String
    var fileTree: String
    let extractedAt: Date

    enum CodingKeys: String, CodingKey {
        case repositoryPath
        case branch
        case status
        case recentCommits
        case fileTree
        case extractedAt
    }
}

struct CachedContext {
    let repositoryContext: RepositoryContext
    let timestamp: Date
}

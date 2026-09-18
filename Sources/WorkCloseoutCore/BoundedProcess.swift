import Darwin
import Foundation

/// Runs a subprocess in its own process group with a hard timeout and bounded stdout/stderr capture.
///
/// On timeout the entire process group is signaled (TERM then KILL), and output is drained with a
/// short deadline so a surviving writer cannot block `read` forever.
enum BoundedProcess {
    struct Outcome: Sendable {
        var exitCode: Int32
        var output: String
        var timedOut: Bool
    }

    static func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        timeout: TimeInterval,
        maximumOutputCharacters: Int
    ) throws -> Outcome {
        let outputPipe = Pipe()
        let readFD = outputPipe.fileHandleForReading.fileDescriptor
        let writeFD = outputPipe.fileHandleForWriting.fileDescriptor

        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw CloseoutError.invalidConfiguration("unable to initialize process file actions")
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        guard posix_spawn_file_actions_adddup2(&fileActions, writeFD, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&fileActions, writeFD, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addclose(&fileActions, writeFD) == 0,
              posix_spawn_file_actions_addclose(&fileActions, readFD) == 0
        else {
            throw CloseoutError.invalidConfiguration("unable to configure process stdio")
        }

        let directoryPath = currentDirectory.path
        guard posix_spawn_file_actions_addchdir_np(&fileActions, directoryPath) == 0 else {
            throw CloseoutError.invalidConfiguration("unable to set process working directory")
        }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw CloseoutError.invalidConfiguration("unable to initialize process attributes")
        }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0
        else {
            throw CloseoutError.invalidConfiguration("unable to configure process group")
        }

        var argvPointers = ([executable] + arguments).map { strdup($0) }
        argvPointers.append(nil)
        defer { argvPointers.forEach { free($0) } }

        var pid: pid_t = 0
        let spawnError: Int32 = argvPointers.withUnsafeMutableBufferPointer { buffer in
            posix_spawn(&pid, executable, &fileActions, &attributes, buffer.baseAddress, environ)
        }
        try outputPipe.fileHandleForWriting.close()
        guard spawnError == 0 else {
            throw CloseoutError.invalidConfiguration("failed to spawn \(executable) (errno \(spawnError))")
        }

        let flags = fcntl(readFD, F_GETFL)
        _ = fcntl(readFD, F_SETFL, flags | O_NONBLOCK)

        let maximumBytes = max(maximumOutputCharacters * 4, maximumOutputCharacters)
        var collected = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var exitCode: Int32 = 0
        var reaped = false

        while !reaped {
            appendAvailable(from: readFD, into: &collected, limit: maximumBytes)

            var status: Int32 = 0
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid {
                exitCode = decodeStatus(status)
                reaped = true
                break
            }
            if waited < 0, errno != EINTR {
                throw CloseoutError.invalidConfiguration("waitpid failed for \(executable)")
            }

            if Date() >= deadline {
                timedOut = true
                _ = kill(-pid, SIGTERM)
                let graceDeadline = Date().addingTimeInterval(0.5)
                while Date() < graceDeadline {
                    appendAvailable(from: readFD, into: &collected, limit: maximumBytes)
                    var graceStatus: Int32 = 0
                    if waitpid(pid, &graceStatus, WNOHANG) == pid {
                        exitCode = 124
                        reaped = true
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if !reaped {
                    _ = kill(-pid, SIGKILL)
                    let killDeadline = Date().addingTimeInterval(1.0)
                    while Date() < killDeadline {
                        appendAvailable(from: readFD, into: &collected, limit: maximumBytes)
                        var killStatus: Int32 = 0
                        if waitpid(pid, &killStatus, WNOHANG) == pid {
                            exitCode = 124
                            reaped = true
                            break
                        }
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    if !reaped {
                        exitCode = 124
                        reaped = true
                    }
                }
                break
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        let drainDeadline = Date().addingTimeInterval(timedOut ? 0.75 : 2.0)
        while Date() < drainDeadline {
            let before = collected.count
            appendAvailable(from: readFD, into: &collected, limit: maximumBytes)
            if collected.count == before { break }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let text = String(decoding: collected, as: UTF8.self)
        return Outcome(
            exitCode: timedOut ? 124 : exitCode,
            output: String(text.prefix(maximumOutputCharacters)),
            timedOut: timedOut
        )
    }

    private static func appendAvailable(from fd: Int32, into data: inout Data, limit: Int) {
        guard data.count < limit else { return }
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.count < limit {
            let count = read(fd, &buffer, min(buffer.count, limit - data.count))
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count == 0 { return }
            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR { return }
            return
        }
    }

    private static func decodeStatus(_ status: Int32) -> Int32 {
        // Darwin wait macros are unavailable as Swift imports; decode manually.
        let wstatus = status & 0o177
        if wstatus == 0 { return (status >> 8) & 0xff }
        if wstatus != 0o177 { return 128 + wstatus }
        return status
    }
}

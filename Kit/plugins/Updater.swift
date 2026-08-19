//
//  Updater.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 14/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import CryptoKit
import SystemConfiguration
import Security

public struct version_s {
    public let current: String
    public let latest: String
    public let newest: Bool
    public let url: String
    /// Where the published SHA-256 of `url` lives, when the release ships one.
    public let checksumURL: String?

    public init(current: String, latest: String, newest: Bool, url: String, checksumURL: String? = nil) {
        self.current = current
        self.latest = latest
        self.newest = newest
        self.url = url
        self.checksumURL = checksumURL
    }
}

/// Picks the download and its checksum out of a release's asset list.
///
/// Internal rather than nested so it can be tested directly: a matching bug here means the
/// app silently never finds an update, which is exactly how the inherited version failed.
/// The release ships a zip, and the name carries the app's own name with spaces removed,
/// because GitHub rewrites a space in an asset filename to a dot.
public func pickReleaseAssets(
    _ assets: [(name: String, url: String)], appName: String
) -> (zip: String, checksum: String?)? {
    let slug = appName.replacingOccurrences(of: " ", with: "")
    guard let zip = assets.first(where: {
        $0.name.hasSuffix(".zip") && $0.name.localizedCaseInsensitiveContains(slug)
    }) else { return nil }

    let checksum = assets.first(where: { $0.name == "\(zip.name).sha256" })
        ?? assets.first(where: { $0.name.hasSuffix(".zip.sha256") })
    return (zip.url, checksum?.url)
}

/// Reads a checksum out of the body of a `.sha256` file, which is `<hash>  <filename>`.
public func parseChecksum(_ text: String) -> String? {
    guard let field = text.split(whereSeparator: { $0 == " " || $0.isNewline }).first else {
        return nil
    }
    let hash = String(field)
    // A SHA-256 is 64 hex characters, and anything else is a mistake worth refusing rather
    // than comparing against.
    guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { return nil }
    return hash
}

internal struct release_s {
    let tag: String
    let url: String
    let checksumURL: String?
}

internal struct Version {
    var major: Int = 0
    var minor: Int = 0
    var patch: Int = 0
    
    var beta: Int? = nil
}

public class Updater {
    private let github: URL
    private let server: URL?
    
    private let appName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    private let currentVersion: String = "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String)"
    
    private var observation: NSKeyValueObservation?
    
    private var lastCheckTS: Int {
        get {
            return Store.shared.int(key: "updater_check_ts", defaultValue: -1)
        }
        set {
            Store.shared.set(key: "updater_check_ts", value: newValue)
        }
    }
    private var lastInstallTS: Int {
        get {
            return Store.shared.int(key: "updater_install_ts", defaultValue: -1)
        }
        set {
            Store.shared.set(key: "updater_install_ts", value: newValue)
        }
    }
    
    /// `url` is an optional mirror checked before GitHub. Pass an empty string when there
    /// is none, so no guaranteed-failing request is fired on every check.
    public init(github: String, url: String = "") {
        self.github = URL(string: "https://api.github.com/repos/\(github)/releases/latest")!
        self.server = url.isEmpty
            ? nil
            : URL(string: "\(url)?macOS=\(ProcessInfo().operatingSystemVersion.getFullVersion())")
    }
    
    deinit {
        observation?.invalidate()
    }
    
    public func check(force: Bool = false, completion: @escaping (_ result: version_s?, _ error: Error?) -> Void) {
        if !isConnectedToNetwork() {
            completion(nil, "No internet connection")
            return
        }
        
        let diff = (Int(Date().timeIntervalSince1970) - self.lastCheckTS) / 60
        if !force && diff <= 10 {
            completion(nil, "last check was \(diff) minutes ago, stopping...")
            return
        }
        
        defer {
            self.lastCheckTS = Int(Date().timeIntervalSince1970)
        }
        
        guard let server = self.server else {
            self.fetchRelease(uri: self.github) { (result, err) in
                guard let result = result, err == nil else {
                    completion(nil, err)
                    return
                }
                completion(version_s(
                    current: self.currentVersion,
                    latest: result.tag,
                    newest: isNewestVersion(currentVersion: self.currentVersion, latestVersion: result.tag),
                    url: result.url,
                    checksumURL: result.checksumURL
                ), nil)
            }
            return
        }

        self.fetchRelease(uri: server) { (result, err) in
            guard let result = result, err == nil else {
                self.fetchRelease(uri: self.github) { (result, err) in
                    guard let result = result, err == nil else {
                        completion(nil, err)
                        return
                    }
                    
                    completion(version_s(
                        current: self.currentVersion,
                        latest: result.tag,
                        newest: isNewestVersion(currentVersion: self.currentVersion, latestVersion: result.tag),
                        url: result.url,
                        checksumURL: result.checksumURL
                    ), nil)
                }
                return
            }
            
            completion(version_s(
                current: self.currentVersion,
                latest: result.tag,
                newest: isNewestVersion(currentVersion: self.currentVersion, latestVersion: result.tag),
                url: result.url,
                checksumURL: result.checksumURL
            ), nil)
        }
    }
    
    private func fetchRelease(uri: URL, completion: @escaping (_ result: release_s?, _ error: Error?) -> Void) {
        let task = URLSession.shared.dataTask(with: uri) { data, _, error in
            guard let data = data, error == nil else {
                completion(nil, "no data")
                return
            }
            
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])
                guard let jsonArray = jsonResponse as? [String: Any],
                      let lastVersion = jsonArray["tag_name"] as? String,
                      let assets = jsonArray["assets"] as? [[String: Any]] else {
                    completion(nil, "parse json")
                    return
                }

                let named: [(name: String, url: String)] = assets.compactMap {
                    guard let name = $0["name"] as? String,
                        let link = $0["browser_download_url"] as? String else { return nil }
                    return (name, link)
                }

                guard let picked = pickReleaseAssets(named, appName: self.appName) else {
                    completion(nil, "no zip asset in the latest release")
                    return
                }

                completion(
                    release_s(tag: lastVersion, url: picked.zip, checksumURL: picked.checksum), nil)
            } catch let parsingError {
                completion(nil, parsingError)
            }
        }
        task.resume()
    }
    
    public func download(_ url: URL, progress: @escaping (_ progress: Progress) -> Void = {_ in }, completion: @escaping (_ path: String) -> Void = {_ in }) {
        let downloadTask = URLSession.shared.downloadTask(with: url) { urlOrNil, _, _ in
            guard let fileURL = urlOrNil else { return }
            do {
                let temporary = try FileManager.default.url(
                    for: .itemReplacementDirectory, in: .userDomainMask,
                    appropriateFor: Bundle.main.bundleURL, create: true)
                let destinationURL = temporary.appendingPathComponent(url.lastPathComponent)
                
                self.copyFile(from: fileURL, to: destinationURL) { (path, error) in
                    if error != nil {
                        print("copy file error: \(error ?? "copy error")")
                        return
                    }
                    
                    completion(path)
                }
            } catch {
                print("file error: \(error)")
            }
        }
        
        self.observation = downloadTask.progress.observe(\.fractionCompleted) { value, _ in
            progress(value)
        }
        
        downloadTask.resume()
    }
    
    /// The whole update in one call: resolve the published checksum, download, verify and
    /// install. Every caller goes through here so none of them can forget the checksum.
    public func downloadAndInstall(
        _ version: version_s,
        progress: @escaping (_ progress: Progress) -> Void = {_ in },
        completion: @escaping (_ error: String?) -> Void
    ) {
        guard let url = URL(string: version.url) else {
            completion("the release does not give a download link")
            return
        }

        let proceed: (String?) -> Void = { checksum in
            self.download(url, progress: progress) { path in
                self.install(path: path, checksum: checksum, completion: completion)
            }
        }

        guard let checksumURL = version.checksumURL, let link = URL(string: checksumURL) else {
            // No published checksum means nothing to verify the download against, so the
            // update is refused rather than installed on trust.
            completion("this release publishes no checksum, so it was not installed automatically")
            return
        }
        self.fetchChecksum(link) { checksum in
            guard let checksum else {
                completion("could not read the checksum this release publishes")
                return
            }
            proceed(checksum)
        }
    }

    /// Installs a downloaded release zip over the running app.
    ///
    /// What this verifies, stated plainly because the app has no Developer ID: the download
    /// matches the SHA-256 the release publishes, the bundle inside is this app by identifier,
    /// its version really is newer, and its own signature is intact. That is integrity, not
    /// authenticity. It rests on TLS to GitHub and on the release itself being genuine,
    /// because a checksum fetched from the same place as the file cannot prove authorship.
    /// Proving that needs a signing key, which this project does not have yet.
    ///
    /// There is deliberately no privileged path. If the app cannot be replaced without
    /// elevation it says so instead of raising a root prompt to overwrite itself.
    public func install(path: String, checksum expected: String? = nil, completion: @escaping (_ error: String?) -> Void) {
        let zip = path.replacingOccurrences(of: "file://", with: "")
        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: zip) else {
            completion("the download is missing at \(zip)")
            return
        }
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            completion("\(parent.path) is not writable, so move Dead Air somewhere it is, or install the new version by hand")
            return
        }

        if let expected, !expected.isEmpty {
            guard let actual = Self.sha256(ofFileAt: zip) else {
                completion("could not read the download to check it")
                return
            }
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                try? FileManager.default.removeItem(atPath: zip)
                completion("the download does not match the checksum the release publishes, so it was not installed")
                return
            }
        }

        let staging: URL
        do {
            staging = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: parent, create: true)
        } catch {
            completion("could not make a staging directory: \(error.localizedDescription)")
            return
        }
        // Cleaned up on every failure path. On success the staging directory holds the
        // running app, which must outlive this process, so the relaunch script removes it
        // once we are gone rather than a defer pulling it out from under us.
        var cleanUpStaging = true
        defer {
            if cleanUpStaging { try? FileManager.default.removeItem(at: staging) }
        }

        let unzip = self.runProcess("/usr/bin/ditto", ["-x", "-k", zip, staging.path])
        guard unzip.exit == 0 else {
            completion("could not unpack the download: \(unzip.error)")
            return
        }

        guard let app = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" }) else {
            completion("the download does not contain an app")
            return
        }

        if let problem = self.validate(app) {
            completion(problem)
            return
        }

        // Both paths are in the same parent, so the swap is a rename on one volume and the
        // window in which no app exists at the destination is as short as it can be.
        let old = staging.appendingPathComponent("previous.app")
        do {
            try FileManager.default.moveItem(at: destination, to: old)
        } catch {
            completion("could not move the running app aside: \(error.localizedDescription)")
            return
        }
        do {
            try FileManager.default.moveItem(at: app, to: destination)
        } catch {
            // Put the old one back rather than leaving nothing installed.
            try? FileManager.default.moveItem(at: old, to: destination)
            completion("could not put the new version in place: \(error.localizedDescription)")
            return
        }

        try? FileManager.default.removeItem(atPath: zip)
        self.lastInstallTS = Int(Date().timeIntervalSince1970)
        cleanUpStaging = false

        completion(nil)
        self.relaunch(at: destination, removing: staging)
    }

    /// Structural checks on the bundle that came out of the zip.
    private func validate(_ app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else {
            return "the downloaded app has no readable Info.plist"
        }
        guard let identifier = info["CFBundleIdentifier"] as? String,
            identifier == Bundle.main.bundleIdentifier else {
            return "the downloaded app is a different application"
        }
        guard let version = info["CFBundleShortVersionString"] as? String else {
            return "the downloaded app does not say which version it is"
        }
        guard isNewestVersion(currentVersion: self.currentVersion, latestVersion: "v\(version)") else {
            return "the downloaded app is not newer than the one running"
        }
        // Verifies the bundle against its own signature: it catches a truncated or tampered
        // download, and says nothing about who built it.
        let check = self.runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard check.exit == 0 else {
            return "the downloaded app fails its own signature check"
        }
        return nil
    }

    /// Starts the new copy once this process is gone, and only then removes the old one.
    /// Values arrive as positional arguments, never interpolated into the script.
    private func relaunch(at app: URL, removing staging: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c", "sleep 2; /bin/rm -rf \"$2\"; /usr/bin/open -n \"$1\"",
            "sh", app.path, staging.path
        ]
        try? task.run()
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    /// An argv array and an absolute path, never a shell string.
    private func runProcess(_ launch: String, _ args: [String]) -> (output: String, error: String, exit: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launch)
        task.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            return ("", error.localizedDescription, -1)
        }

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let failure = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        task.waitUntilExit()

        return (output.trimmingCharacters(in: .whitespacesAndNewlines),
                failure.trimmingCharacters(in: .whitespacesAndNewlines),
                task.terminationStatus)
    }

    private static func sha256(ofFileAt path: String) -> String? {
        guard let stream = InputStream(fileAtPath: path) else { return nil }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let size = 1 << 16
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read < 0 { return nil }
            if read == 0 { break }
            hasher.update(data: Data(buffer[0..<read]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Fetches the published checksum for a release asset. The body is `<hash>  <filename>`,
    /// the same shape `shasum` writes, so only the first field is taken.
    public func fetchChecksum(_ url: URL, completion: @escaping (_ checksum: String?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let text = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            completion(parseChecksum(text))
        }.resume()
    }

    private func copyFile(from: URL, to: URL, completionHandler: @escaping (_ path: String, _ error: Error?) -> Void) {
        var toPath = to
        let fileName = (URL(fileURLWithPath: to.absoluteString)).lastPathComponent
        let fileExt  = (URL(fileURLWithPath: to.absoluteString)).pathExtension
        var fileNameWithoutSuffix: String!
        var newFileName: String!
        var counter = 0
        
        if fileName.hasSuffix(fileExt) {
            fileNameWithoutSuffix = String(fileName.prefix(fileName.count - (fileExt.count+1)))
        }
        
        while toPath.checkFileExist() {
            counter += 1
            newFileName =  "\(fileNameWithoutSuffix!)-\(counter).\(fileExt)"
            toPath = to.deletingLastPathComponent().appendingPathComponent(newFileName)
        }
        
        do {
            try FileManager.default.moveItem(at: from, to: toPath)
            // .path, not .absoluteString: the caller uses this as a filesystem path, and
            // an app name with a space in it percent encodes into a path that never exists.
            completionHandler(toPath.path, nil)
        } catch {
            completionHandler("", error)
        }
    }
    
    // https://stackoverflow.com/questions/30743408/check-for-internet-connection-with-swift
    private func isConnectedToNetwork() -> Bool {
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }
        
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let ret = (isReachable && !needsConnection)
        
        return ret
    }
}

import Combine
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WishlistCore
import XCTest

/// Holds a scripted asynchronous call open until the test decides to release it.
///
/// Session-lifecycle bugs are ordering bugs, so the tests that cover them have to control the
/// ordering. A gate makes "this request is in flight right now" and "this request finishes now"
/// explicit events, which is both deterministic and far more readable than sleeping and hoping.
final class AsyncGate: @unchecked Sendable {
  private let lock = NSLock()
  private var isOpen: Bool
  private var arrivals = 0
  private var blocked: [CheckedContinuation<Void, Never>] = []
  private var arrivalWatchers: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] =
    []

  init(open: Bool = false) {
    isOpen = open
  }

  var arrivalCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return arrivals
  }

  /// Called by a fake service: records that the call started, then suspends it until `open()`.
  func arriveAndWait() async {
    lock.lock()
    arrivals += 1
    let reached = arrivals
    let watchers = arrivalWatchers.filter { $0.threshold <= reached }.map(\.continuation)
    arrivalWatchers.removeAll { $0.threshold <= reached }
    let alreadyOpen = isOpen
    lock.unlock()

    for watcher in watchers {
      watcher.resume()
    }
    if alreadyOpen { return }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      lock.lock()
      if isOpen {
        lock.unlock()
        continuation.resume()
      } else {
        blocked.append(continuation)
        lock.unlock()
      }
    }
  }

  /// Releases everything waiting at the gate, and everything that arrives later.
  func open() {
    lock.lock()
    isOpen = true
    let waiting = blocked
    blocked.removeAll()
    lock.unlock()

    for continuation in waiting {
      continuation.resume()
    }
  }

  /// Suspends until at least `count` calls have reached the gate.
  func waitForArrivals(_ count: Int) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      lock.lock()
      if arrivals >= count {
        lock.unlock()
        continuation.resume()
      } else {
        arrivalWatchers.append((count, continuation))
        lock.unlock()
      }
    }
  }
}

/// Records every phase the controller publishes.
///
/// A settled state cannot prove that an intermediate one never appeared, so the identity tests
/// assert on the whole sequence instead.
@MainActor
final class PhaseRecorder {
  private(set) var phases: [AuthenticationPhase] = []
  private var subscription: AnyCancellable?

  init(_ controller: SessionController) {
    subscription = controller.$phase.sink { [weak self] phase in
      self?.phases.append(phase)
    }
  }

  func occurrences(of phase: AuthenticationPhase) -> Int {
    phases.filter { $0 == phase }.count
  }
}

extension XCTestCase {
  /// Polls on the main actor until `condition` holds, so tests do not depend on a fixed delay.
  @MainActor
  func waitUntil(
    _ description: String,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for \(description)", file: file, line: line)
  }
}

/// A scriptable stand-in for the Supabase authentication service.
///
/// Recording call counts is what lets the tests assert that a duplicate submission never reaches the
/// network and that a superseded request is discarded rather than applied.
///
/// The event stream is created in `init` rather than lazily in `events()`. `SessionController.start()`
/// observes the stream from an unstructured `Task`, so a test that emits immediately after `start()`
/// would otherwise drop the event if the continuation did not exist yet.
final class FakeAuthenticationService: AuthenticationService, @unchecked Sendable {
  private let lock = NSLock()
  private var storedUser: AuthenticatedUser?
  private var verifyResult: Result<AuthenticatedUser, AuthenticationFailure> = .failure(
    .sessionExpired)
  private var magicLinkResult: Result<Void, AuthenticationFailure> = .success(())
  private var callbackResult: Result<AuthenticatedUser, AuthenticationFailure> = .failure(
    .callbackInvalid)
  private var appleResult: Result<AuthenticatedUser, AuthenticationFailure> = .failure(
    .appleCredentialRejected)
  private var signOutResult: Result<Void, AuthenticationFailure> = .success(())
  private var verifyGate: AsyncGate?
  private var appleGate: AsyncGate?
  private let eventStream: AsyncStream<AuthenticationServiceEvent>
  private let eventContinuation: AsyncStream<AuthenticationServiceEvent>.Continuation

  init() {
    let stream = AsyncStream.makeStream(
      of: AuthenticationServiceEvent.self,
      bufferingPolicy: .unbounded
    )
    eventStream = stream.stream
    eventContinuation = stream.continuation
  }

  deinit {
    eventContinuation.finish()
  }

  private var sentAddresses: [EmailAddress] = []
  private var callbackURLs: [URL] = []
  private var appleCredentials: [AppleIdentityCredential] = []
  private var signOutCount = 0

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  // MARK: - Scripting

  func setStoredUser(_ user: AuthenticatedUser?) {
    locked { storedUser = user }
  }

  func setVerifyResult(_ result: Result<AuthenticatedUser, AuthenticationFailure>) {
    locked { verifyResult = result }
  }

  func setMagicLinkResult(_ result: Result<Void, AuthenticationFailure>) {
    locked { magicLinkResult = result }
  }

  func setCallbackResult(_ result: Result<AuthenticatedUser, AuthenticationFailure>) {
    locked { callbackResult = result }
  }

  func setAppleResult(_ result: Result<AuthenticatedUser, AuthenticationFailure>) {
    locked { appleResult = result }
  }

  func setSignOutResult(_ result: Result<Void, AuthenticationFailure>) {
    locked { signOutResult = result }
  }

  /// Holds `verifiedUser()` open so a test can act while a refresh is still in flight.
  func setVerifyGate(_ gate: AsyncGate?) {
    locked { verifyGate = gate }
  }

  /// Holds `signInWithApple(credential:)` open the same way.
  func setAppleGate(_ gate: AsyncGate?) {
    locked { appleGate = gate }
  }

  func emit(_ event: AuthenticationServiceEvent) {
    eventContinuation.yield(event)
  }

  var sentAddressCount: Int { locked { sentAddresses.count } }
  var callbackCount: Int { locked { callbackURLs.count } }
  var appleCredentialCount: Int { locked { appleCredentials.count } }
  var recordedSignOutCount: Int { locked { signOutCount } }
  var lastSentAddress: EmailAddress? { locked { sentAddresses.last } }

  // MARK: - AuthenticationService

  func restoredUser() async -> AuthenticatedUser? {
    locked { storedUser }
  }

  func verifiedUser() async throws -> AuthenticatedUser {
    let (result, gate) = locked {
      (verifyResult, verifyGate)
    }
    await gate?.arriveAndWait()
    return try result.get()
  }

  func events() -> AsyncStream<AuthenticationServiceEvent> {
    eventStream
  }

  func sendMagicLink(to address: EmailAddress) async throws {
    let result = locked { () -> Result<Void, AuthenticationFailure> in
      sentAddresses.append(address)
      return magicLinkResult
    }
    try result.get()
  }

  func completeSignIn(callback url: URL) async throws -> AuthenticatedUser {
    let result = locked { () -> Result<AuthenticatedUser, AuthenticationFailure> in
      callbackURLs.append(url)
      return callbackResult
    }
    return try result.get()
  }

  func signInWithApple(credential: AppleIdentityCredential) async throws -> AuthenticatedUser {
    let (result, gate) = locked {
      () -> (Result<AuthenticatedUser, AuthenticationFailure>, AsyncGate?) in
      appleCredentials.append(credential)
      return (appleResult, appleGate)
    }
    await gate?.arriveAndWait()
    return try result.get()
  }

  func signOut() async throws {
    let result = locked { () -> Result<Void, AuthenticationFailure> in
      signOutCount += 1
      return signOutResult
    }
    try result.get()
  }
}

/// A scriptable stand-in for the Supabase profile service.
final class FakeProfileService: ProfileService, @unchecked Sendable {
  private let lock = NSLock()
  private var loadResult: Result<UserProfile, any Error>
  private var saveResult: Result<UserProfile, any Error>?
  private var uploadResult: Result<UserProfile, any Error>?
  private var removeResult: Result<UserProfile, any Error>?
  private var avatarResult: Result<Data, any Error> = .success(Data())
  private var deleteResult: Result<Void, any Error> = .success(())
  private var loadResultsByUser: [UUID: Result<UserProfile, any Error>] = [:]
  private var loadGate: AsyncGate?

  private var savedDrafts: [(draft: ProfileDraft, completingOnboarding: Bool)] = []
  private var uploads: [ProfileImageUpload] = []
  private var removeCount = 0
  private var deleteCount = 0
  private var loadCount = 0
  private var loadedUserIDs: [UUID] = []

  init(profile: UserProfile) {
    loadResult = .success(profile)
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  // MARK: - Scripting

  func setLoadResult(_ result: Result<UserProfile, any Error>) {
    locked { loadResult = result }
  }

  /// Scripts the row returned for one account, so a test can script two identities at once.
  func setLoadResult(_ result: Result<UserProfile, any Error>, for userID: UUID) {
    locked { loadResultsByUser[userID] = result }
  }

  /// Holds every profile read open so a test can act while one is in flight.
  func setLoadGate(_ gate: AsyncGate?) {
    locked { loadGate = gate }
  }

  func setSaveResult(_ result: Result<UserProfile, any Error>) {
    locked { saveResult = result }
  }

  func setUploadResult(_ result: Result<UserProfile, any Error>) {
    locked { uploadResult = result }
  }

  func setRemoveResult(_ result: Result<UserProfile, any Error>) {
    locked { removeResult = result }
  }

  func setAvatarResult(_ result: Result<Data, any Error>) {
    locked { avatarResult = result }
  }

  func setDeleteResult(_ result: Result<Void, any Error>) {
    locked { deleteResult = result }
  }

  var recordedSaves: [(draft: ProfileDraft, completingOnboarding: Bool)] { locked { savedDrafts } }
  var recordedUploads: [ProfileImageUpload] { locked { uploads } }
  var recordedRemoveCount: Int { locked { removeCount } }
  var recordedDeleteCount: Int { locked { deleteCount } }
  var recordedLoadCount: Int { locked { loadCount } }
  /// Every account a profile was read for, in order.
  var recordedLoadedUserIDs: [UUID] { locked { loadedUserIDs } }

  // MARK: - ProfileService

  func loadProfile(userID: UUID) async throws -> UserProfile {
    let (result, gate) = locked { () -> (Result<UserProfile, any Error>, AsyncGate?) in
      loadCount += 1
      loadedUserIDs.append(userID)
      return (loadResultsByUser[userID] ?? loadResult, loadGate)
    }
    await gate?.arriveAndWait()
    return try result.get()
  }

  func saveProfile(_ draft: ProfileDraft, completingOnboarding: Bool) async throws -> UserProfile {
    if let issue = draft.validationIssues().first {
      throw ProfileServiceError.validation(issue)
    }
    let result = locked { () -> Result<UserProfile, any Error> in
      savedDrafts.append((draft, completingOnboarding))
      return saveResult ?? loadResult
    }
    return try result.get()
  }

  func uploadAvatar(_ upload: ProfileImageUpload) async throws -> UserProfile {
    let result = locked { () -> Result<UserProfile, any Error> in
      uploads.append(upload)
      return uploadResult ?? loadResult
    }
    return try result.get()
  }

  func removeAvatar() async throws -> UserProfile {
    let result = locked { () -> Result<UserProfile, any Error> in
      removeCount += 1
      return removeResult ?? loadResult
    }
    return try result.get()
  }

  func avatarData(path: String) async throws -> Data {
    try locked { avatarResult }.get()
  }

  func deleteAccount() async throws {
    let result = locked { () -> Result<Void, any Error> in
      deleteCount += 1
      return deleteResult
    }
    try result.get()
  }
}

enum TestFixtures {
  static let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  static let otherID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!

  static var user: AuthenticatedUser {
    AuthenticatedUser(id: ownerID, email: "mia.owner@example.invalid")
  }

  /// A second account, used by the tests that cover an identity changing under an open session.
  static var otherUser: AuthenticatedUser {
    AuthenticatedUser(id: otherID, email: "leo.other@example.invalid")
  }

  static func profile(
    id: UUID = ownerID,
    displayName: String = "Mia Chen",
    avatarPath: String? = nil,
    onboardingCompleted: Bool = true
  ) -> UserProfile {
    UserProfile(
      id: id,
      displayName: displayName,
      avatarPath: avatarPath,
      onboardingCompleted: onboardingCompleted,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  static func otherProfile(onboardingCompleted: Bool = true) -> UserProfile {
    profile(id: otherID, displayName: "Leo Marsh", onboardingCompleted: onboardingCompleted)
  }

  /// Fixed, valid values, so the initializer cannot fail. A failure here is a broken fixture rather
  /// than a test outcome, which is why it stops the suite instead of being reported as one.
  static let configuration: AppConfiguration = {
    guard let url = URL(string: "https://project.example.invalid"),
      let configuration = try? AppConfiguration(
        supabaseURL: url,
        publishableKey: "publishable-test-key",
        shareLinkHost: "gifts.example.invalid",
        authRedirectScheme: "jiejie-debug",
        appleSignInEnabled: true
      )
    else {
      preconditionFailure("the test configuration fixture is not a usable configuration")
    }
    return configuration
  }()

  static func appleCredential() throws -> AppleIdentityCredential {
    try AppleIdentityCredential(
      identityToken: "header.payload.signature",
      nonce: SignInWithAppleNonce(raw: String(repeating: "a", count: 32))
    )
  }

  /// A real, decodable PNG so image preparation runs the same code path it does in the app.
  static func pngData(width: Int = 8, height: Int = 8) throws -> Data {
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw FixtureError.couldNotBuildImage
    }
    context.setFillColor(red: 0.4, green: 0.2, blue: 0.4, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage() else { throw FixtureError.couldNotBuildImage }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw FixtureError.couldNotBuildImage
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw FixtureError.couldNotBuildImage
    }

    let data = output as Data
    guard ProfileImageFormat.detected(in: data) == .png else {
      throw FixtureError.couldNotBuildImage
    }
    return data
  }

  enum FixtureError: Error {
    case couldNotBuildImage
  }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WishlistCore

/// A scriptable stand-in for the Supabase authentication service.
///
/// Recording call counts is what lets the tests assert that a duplicate submission never reaches the
/// network and that a superseded request is discarded rather than applied.
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
  private var continuation: AsyncStream<AuthenticationServiceEvent>.Continuation?

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

  func emit(_ event: AuthenticationServiceEvent) {
    locked { continuation }?.yield(event)
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
    try locked { verifyResult }.get()
  }

  func events() -> AsyncStream<AuthenticationServiceEvent> {
    AsyncStream { continuation in
      locked { self.continuation = continuation }
    }
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
    let result = locked { () -> Result<AuthenticatedUser, AuthenticationFailure> in
      appleCredentials.append(credential)
      return appleResult
    }
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
  private var loadDelayNanoseconds: UInt64 = 0

  private var savedDrafts: [(draft: ProfileDraft, completingOnboarding: Bool)] = []
  private var uploads: [ProfileImageUpload] = []
  private var removeCount = 0
  private var deleteCount = 0
  private var loadCount = 0

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

  func setLoadDelay(nanoseconds: UInt64) {
    locked { loadDelayNanoseconds = nanoseconds }
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

  // MARK: - ProfileService

  func loadProfile(userID: UUID) async throws -> UserProfile {
    let (result, delay) = locked { () -> (Result<UserProfile, any Error>, UInt64) in
      loadCount += 1
      return (loadResult, loadDelayNanoseconds)
    }
    if delay > 0 {
      try? await Task.sleep(nanoseconds: delay)
    }
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

  static func profile(
    displayName: String = "Mia Chen",
    avatarPath: String? = nil,
    onboardingCompleted: Bool = true
  ) -> UserProfile {
    UserProfile(
      id: ownerID,
      displayName: displayName,
      avatarPath: avatarPath,
      onboardingCompleted: onboardingCompleted,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  static var configuration: AppConfiguration {
    AppConfiguration(
      supabaseURL: URL(string: "https://project.example.invalid")!,
      publishableKey: "publishable-test-key",
      shareLinkHost: "gifts.example.invalid",
      authRedirectScheme: "jiejie-debug",
      appleSignInEnabled: true
    )
  }

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

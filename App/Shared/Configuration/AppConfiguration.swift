import Foundation
import Supabase

struct AppConfiguration: Equatable, Sendable {
  let supabaseURL: URL
  let publishableKey: String
  let shareLinkHost: String

  static func load(bundle: Bundle = .main) throws -> AppConfiguration {
    guard
      let urlText = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
      let url = URL(string: urlText),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || url.host == "127.0.0.1",
      !urlText.contains("YOUR_PROJECT_REF"),
      let key = bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
      !key.isEmpty,
      !key.contains("YOUR_PUBLISHABLE_KEY"),
      let shareLinkHost = bundle.object(forInfoDictionaryKey: "SHARE_LINK_HOST") as? String,
      !shareLinkHost.isEmpty,
      shareLinkHost != "example.invalid"
    else {
      throw ConfigurationError.missingLocalConfiguration
    }

    return AppConfiguration(
      supabaseURL: url,
      publishableKey: key,
      shareLinkHost: shareLinkHost.lowercased()
    )
  }
}

enum ConfigurationError: Error, Equatable {
  case missingLocalConfiguration
}

enum SupabaseClientFactory {
  static func make(configuration: AppConfiguration) -> SupabaseClient {
    SupabaseClient(
      supabaseURL: configuration.supabaseURL,
      supabaseKey: configuration.publishableKey
    )
  }
}

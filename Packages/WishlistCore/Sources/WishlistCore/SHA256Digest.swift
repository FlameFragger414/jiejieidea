import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#endif

/// SHA-256 hashing for values that must be hashed identically on every platform.
///
/// Apple platforms — the only platforms Jiejie ships on — use CryptoKit. The portable
/// implementation below exists so the domain package and its tests still run on Linux CI, where
/// CryptoKit is unavailable and the shared `WishlistCore` tests would otherwise have to be skipped.
/// Both paths are covered by the published NIST test vectors in `SHA256DigestTests`.
public enum SHA256Digest {
  /// Returns the lowercase hexadecimal SHA-256 digest of `text` encoded as UTF-8.
  public static func hexadecimal(of text: String) -> String {
    hexadecimal(of: Array(text.utf8))
  }

  /// Returns the lowercase hexadecimal SHA-256 digest of `bytes`.
  public static func hexadecimal(of bytes: [UInt8]) -> String {
    digest(of: bytes).map { String(format: "%02x", $0) }.joined()
  }

  static func digest(of bytes: [UInt8]) -> [UInt8] {
    #if canImport(CryptoKit)
      return Array(CryptoKit.SHA256.hash(data: Data(bytes)))
    #else
      return PortableSHA256.digest(of: bytes)
    #endif
  }
}

/// A minimal FIPS 180-4 SHA-256 used only where CryptoKit is unavailable.
enum PortableSHA256 {
  private static let roundConstants: [UInt32] = [
    0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4,
    0xab1c_5ed5, 0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe,
    0x9bdc_06a7, 0xc19b_f174, 0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f,
    0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da, 0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
    0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967, 0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc,
    0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85, 0xa2bf_e8a1, 0xa81a_664b,
    0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070, 0x19a4_c116,
    0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
    0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7,
    0xc671_78f2,
  ]

  static func digest(of bytes: [UInt8]) -> [UInt8] {
    var state: [UInt32] = [
      0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
      0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]

    var padded = bytes
    let bitCount = UInt64(bytes.count) * 8
    padded.append(0x80)
    while padded.count % 64 != 56 {
      padded.append(0)
    }
    for shift in stride(from: 56, through: 0, by: -8) {
      padded.append(UInt8(truncatingIfNeeded: bitCount >> UInt64(shift)))
    }

    var schedule = [UInt32](repeating: 0, count: 64)
    for chunkStart in stride(from: 0, to: padded.count, by: 64) {
      for index in 0..<16 {
        let base = chunkStart + index * 4
        schedule[index] =
          UInt32(padded[base]) << 24
          | UInt32(padded[base + 1]) << 16
          | UInt32(padded[base + 2]) << 8
          | UInt32(padded[base + 3])
      }
      for index in 16..<64 {
        let previous = schedule[index - 15]
        let recent = schedule[index - 2]
        let sigma0 =
          rotateRight(previous, 7) ^ rotateRight(previous, 18) ^ (previous >> 3)
        let sigma1 = rotateRight(recent, 17) ^ rotateRight(recent, 19) ^ (recent >> 10)
        schedule[index] = schedule[index - 16] &+ sigma0 &+ schedule[index - 7] &+ sigma1
      }

      var a = state[0]
      var b = state[1]
      var c = state[2]
      var d = state[3]
      var e = state[4]
      var f = state[5]
      var g = state[6]
      var h = state[7]

      for index in 0..<64 {
        let sum1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
        let choose = (e & f) ^ (~e & g)
        let temp1 = h &+ sum1 &+ choose &+ roundConstants[index] &+ schedule[index]
        let sum0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
        let majority = (a & b) ^ (a & c) ^ (b & c)
        let temp2 = sum0 &+ majority

        h = g
        g = f
        f = e
        e = d &+ temp1
        d = c
        c = b
        b = a
        a = temp1 &+ temp2
      }

      state[0] = state[0] &+ a
      state[1] = state[1] &+ b
      state[2] = state[2] &+ c
      state[3] = state[3] &+ d
      state[4] = state[4] &+ e
      state[5] = state[5] &+ f
      state[6] = state[6] &+ g
      state[7] = state[7] &+ h
    }

    return state.flatMap { word in
      [
        UInt8(truncatingIfNeeded: word >> 24),
        UInt8(truncatingIfNeeded: word >> 16),
        UInt8(truncatingIfNeeded: word >> 8),
        UInt8(truncatingIfNeeded: word),
      ]
    }
  }

  private static func rotateRight(_ value: UInt32, _ amount: UInt32) -> UInt32 {
    (value >> amount) | (value << (32 - amount))
  }
}

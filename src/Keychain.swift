import Foundation
import Security

enum Keychain {
  enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
  }

  static func getPassword(service: String, account: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnData as String: true,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    guard let data = item as? Data else { throw KeychainError.invalidData }
    return String(data: data, encoding: .utf8)
  }

  static func setPassword(_ password: String, service: String, account: String) throws {
    try setPassword(password, service: service, account: account, label: nil)
  }

  static func setPassword(_ password: String, service: String, account: String, label: String?) throws {
    let data = password.data(using: .utf8) ?? Data()

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    var attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    if let label, !label.isEmpty {
      attributes[kSecAttrLabel as String] = label
      attributes[kSecAttrDescription as String] = label
    }

    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess { return }
    if status != errSecItemNotFound { throw KeychainError.unexpectedStatus(status) }

    var addQuery = query
    for (k, v) in attributes { addQuery[k] = v }
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
  }

  static func deletePassword(service: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let status = SecItemDelete(query as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound { return }
    throw KeychainError.unexpectedStatus(status)
  }
}

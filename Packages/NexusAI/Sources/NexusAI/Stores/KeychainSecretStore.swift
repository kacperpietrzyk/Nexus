import Foundation
import Security
import os.log

/// Production `SecretStore` using Apple Keychain Services. One Keychain item
/// per `ProviderID`; `service` is supplied at init (defaults to
/// `"co.kacper.nexus.ai"`) and `kSecAttrAccount` is the provider rawValue.
///
/// `setSecret(nil, for:)` deletes the entry — matches `InMemorySecretStore` and
/// the protocol contract. The protocol is non-throwing, so callers cannot
/// observe Keychain errors directly; instead, write/delete failures and
/// non-`itemNotFound` read failures are logged via `os.Logger` (subsystem
/// `com.kacperpietrzyk.Nexus`, category `ai.secrets`) so operators can spot
/// issues without crashing the app or leaking secret values.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` keeps secrets non-syncing
/// (D6: secrets never leave device). `kSecAttrSynchronizable: false` is set
/// explicitly as defense-in-depth — if the accessibility constant ever changes
/// in a future maintenance pass, the explicit flag still pins items to the
/// local device.
///
/// `useDataProtectionKeychain` controls `kSecUseDataProtectionKeychain` (defaults
/// to `true` for production parity between macOS and iOS — without it, macOS items
/// land in the legacy file-based login.keychain instead of the data-protection
/// keychain). Tests pass `false` because the SwiftPM test bundle is unsigned/
/// unentitled and would otherwise hit `errSecMissingEntitlement`. Production app
/// targets always carry the required entitlements via signing.
public actor KeychainSecretStore: SecretStore {

    private let service: String
    private let useDataProtectionKeychain: Bool
    private let logger = Logger(subsystem: "com.kacperpietrzyk.Nexus", category: "ai.secrets")

    public init(
        service: String = "co.kacper.nexus.ai",
        useDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    public func secret(for provider: ProviderID) async -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error(
                "KeychainSecretStore: read failed for \(provider.rawValue, privacy: .public) (status \(status, privacy: .public))"
            )
        }
        guard status == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    public func setSecret(_ secret: String?, for provider: ProviderID) async {
        var baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
        if useDataProtectionKeychain {
            baseQuery[kSecUseDataProtectionKeychain as String] = true
        }

        guard let secret, let data = secret.data(using: .utf8) else {
            // nil → delete; ignore errSecItemNotFound (idempotent).
            let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
            if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
                let account = provider.rawValue
                logger.error(
                    "KeychainSecretStore: delete failed for \(account, privacy: .public) (status \(deleteStatus, privacy: .public))"
                )
            }
            return
        }

        // Try update first; if not present, add.
        var updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        if useDataProtectionKeychain {
            updateAttrs[kSecUseDataProtectionKeychain as String] = true
        }
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error(
                    "KeychainSecretStore: add failed for \(provider.rawValue, privacy: .public) (status \(addStatus, privacy: .public))"
                )
            }
        } else if updateStatus != errSecSuccess {
            logger.error(
                "KeychainSecretStore: update failed for \(provider.rawValue, privacy: .public) (status \(updateStatus, privacy: .public))"
            )
        }
    }
}

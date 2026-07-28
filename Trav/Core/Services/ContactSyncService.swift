import Contacts
import CryptoKit
import Foundation

enum ContactAuthorizationStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Reads the device address book and produces privacy-preserving contact hashes.
enum ContactSyncService {
    static var authorizationStatus: ContactAuthorizationStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .authorized, .limited: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }

    static func requestAccess() async -> Bool {
        let store = CNContactStore()
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    /// Collects hashed phones/emails from contacts the user has granted access to.
    static func fetchContactHashes() throws -> [ContactHash] {
        let status = authorizationStatus
        guard status == .authorized else { return [] }

        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var hashes: [ContactHash] = []
        var seen = Set<String>()

        try store.enumerateContacts(with: request) { contact, _ in
            for phone in contact.phoneNumbers {
                let digits = normalizePhone(phone.value.stringValue)
                guard digits.count >= 7 else { continue }
                let hash = hashValue(digits)
                if seen.insert(hash).inserted {
                    hashes.append(ContactHash(hash: hash, kind: .phone))
                }
            }
            for email in contact.emailAddresses {
                let normalized = normalizeEmail(email.value as String)
                guard !normalized.isEmpty else { continue }
                let hash = hashValue(normalized)
                if seen.insert(hash).inserted {
                    hashes.append(ContactHash(hash: hash, kind: .email))
                }
            }
        }

        return hashes
    }

    static func hashEmail(_ email: String) -> ContactHash? {
        let normalized = normalizeEmail(email)
        guard !normalized.isEmpty else { return nil }
        return ContactHash(hash: hashValue(normalized), kind: .email)
    }

    static func normalizePhone(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    static func normalizeEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func hashValue(_ normalized: String) -> String {
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

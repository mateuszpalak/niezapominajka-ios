import Foundation
import Contacts

/// Wyszukiwanie numeru telefonu po imieniu/nazwie kontaktu.
struct ContactsService {
    func phoneNumber(for name: String) async throws -> String {
        let store = CNContactStore()
        let granted: Bool = try await withCheckedThrowingContinuation { cont in
            store.requestAccess(for: .contacts) { ok, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: ok) }
            }
        }
        guard granted else {
            throw NSError(domain: "Reminder", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Brak dostępu do Kontaktów — włącz w Ustawieniach."])
        }
        // unifiedContacts jest synchroniczne — przy dużej bazie kontaktów
        // zamroziłoby UI; wykonaj w tle.
        let contacts = try await Task.detached {
            let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor]
            return try store.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
        }.value
        guard let number = contacts.first(where: { !$0.phoneNumbers.isEmpty })?
            .phoneNumbers.first?.value.stringValue else {
            throw NSError(domain: "Reminder", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Nie znalazłem kontaktu „\(name)” z numerem telefonu."])
        }
        return number
    }
}

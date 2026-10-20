import Foundation
import Contacts

/// Kontakt pasujący do wypowiedzianego imienia (z numerami telefonu).
struct ContactMatch: Identifiable, Equatable, Hashable {
    struct Phone: Equatable, Hashable {
        /// Etykieta po polsku: „komórka”, „dom”, „praca”…
        let label: String
        let value: String
    }

    let id: String
    let name: String
    let numbers: [Phone]

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// „komórka · 512 *** 204”
    var subtitle: String {
        guard let phone = numbers.first else { return "" }
        return "\(phone.label) · \(Self.mask(phone.value))"
    }

    func number(labeled label: String?) -> String? {
        (numbers.first { $0.label == label } ?? numbers.first)?.value
    }

    static func mask(_ number: String) -> String {
        var digits = number.filter(\.isNumber)
        if digits.count == 11, digits.hasPrefix("48") { digits.removeFirst(2) }
        guard digits.count >= 7 else { return number }
        return "\(digits.prefix(3)) *** \(digits.suffix(3))"
    }
}

/// Wyszukiwanie kontaktów po imieniu/nazwie.
struct ContactsService {
    /// Wszystkie kontakty z numerem telefonu pasujące do imienia.
    func matches(for name: String) async throws -> [ContactMatch] {
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
        // CNContact nie jest Sendable — zamień na ContactMatch jeszcze w tle.
        return try await Task.detached {
            let keys = [CNContactPhoneNumbersKey as CNKeyDescriptor,
                        CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
            let contacts = try store.unifiedContacts(
                matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)
            return contacts.filter { !$0.phoneNumbers.isEmpty }.map { contact in
                ContactMatch(
                    id: contact.identifier,
                    name: CNContactFormatter.string(from: contact, style: .fullName) ?? name,
                    numbers: contact.phoneNumbers.map {
                        ContactMatch.Phone(label: Self.polishLabel($0.label), value: $0.value.stringValue)
                    })
            }
        }.value
    }

    /// Najlepsze dopasowanie (dokładna nazwa ma pierwszeństwo).
    func bestMatch(for name: String) async throws -> ContactMatch {
        let all = try await matches(for: name)
        guard let match = all.first(where: { $0.name.lowercased() == name.lowercased() }) ?? all.first else {
            throw NSError(domain: "Reminder", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Nie znalazłem kontaktu „\(name)” z numerem telefonu."])
        }
        return match
    }

    private static func polishLabel(_ label: String?) -> String {
        switch label {
        case CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone: return "komórka"
        case CNLabelHome: return "dom"
        case CNLabelWork: return "praca"
        case CNLabelPhoneNumberMain: return "główny"
        case nil: return "telefon"
        case let label?: return CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: label)
        }
    }
}

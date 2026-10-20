# Niezapominajka

Polska aplikacja na iPhone'a do głosowych poleceń. Mówisz, co trzeba zrobić, a ona zapisuje przypomnienie, wydarzenie, notatkę albo listę zakupów, wysyła SMS lub dzwoni. Polecenia rozpoznaje [Claude](https://www.anthropic.com/claude) (model Claude Haiku 5.5).

## Co potrafi

- **Słucha od razu po otwarciu.** Nagranie kończy się samo po krótkiej ciszy.
- **Zapisuje bez potwierdzania.** Przypomnienia, wydarzenia, notatki i zakupy trafiają od razu do aplikacji Apple, a „Odrzuć” lub „Cofnij” je usuwa.
- **SMS i połączenie po odliczaniu** z możliwością anulowania albo wykonania od razu.
- **Kilka poleceń naraz**, np. „dodaj mleko do zakupów i przypomnij mi o 20 o tabletce”.
- **Dopytuje**, gdy pasuje kilka kontaktów („Do której Ani wysłać?”).
- **Edycja treści polecenia** i ponowna analiza.
- **Tryb podglądu**, w którym nic nie zapisuje się bez zatwierdzenia, a pola karty da się edytować.
- **Widżet na ekranie blokady**, kontrolka dla Action Button i skrót Siri.
- **Historia „Ostatnio”** z usuwaniem gestem.

## Wymagania

- iPhone z iOS 26 lub nowszym
- Xcode 26 lub nowszy
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Własny klucz Claude API z [platform.claude.com](https://platform.claude.com)

## Uruchomienie

```sh
xcodegen generate
open Reminder.xcodeproj
```

W Xcode wybierz swój zespół w zakładce *Signing & Capabilities* dla targetów `Reminder` i `ReminderWidget`, a potem uruchom aplikację na iPhonie. W aplikacji otwórz Ustawienia (zębatka) i wklej klucz API. Stan „Klucz działa” potwierdzi, że jest poprawny.

Testy:

```sh
xcodebuild test -project Reminder.xcodeproj -scheme Reminder \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Prywatność

- Klucz API jest przechowywany tylko w Keychain na urządzeniu.
- Do Claude API trafia wyłącznie tekst rozpoznanego polecenia, bez nagrania głosu. Mowę na tekst zamienia systemowe rozpoznawanie mowy Apple.
- Aplikacja nie ma własnego serwera ani analityki.

## Struktura

| Katalog | Zawartość |
|---|---|
| `Reminder/Views` | Ekrany SwiftUI: główny, karta akcji, Ustawienia |
| `Reminder/Services` | Mowa, interpretacja poleceń przez Claude, Przypomnienia, Kalendarz, Kontakty, alarmy |
| `Reminder/Models` | Polecenia i historia (SwiftData) |
| `ReminderWidget` | Widżet ekranu blokady i kontrolka |
| `Shared` | Intent wspólny dla aplikacji i widżetu |

## Licencja

[MIT](LICENSE)

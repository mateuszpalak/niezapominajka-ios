# Jak pomóc w rozwoju Niezapominajki

Dzięki, że chcesz pomóc! Każdy wkład się liczy: zgłoszenie błędu, pomysł, poprawka literówki albo nowa funkcja.

## Zgłaszanie błędów i pomysłów

- Najpierw przeszukaj [issues](https://github.com/mateuszpalak/niezapominajka-ios/issues), czy temat już nie istnieje.
- Użyj szablonu „Błąd” albo „Pomysł na funkcję”.
- Przy błędach rozpoznawania poleceń podaj, co dokładnie powiedziałeś. To najważniejsza wskazówka.
- **Nigdy nie wklejaj swojego klucza API.**
- Luki bezpieczeństwa zgłaszaj prywatnie, zgodnie z [SECURITY.md](SECURITY.md).

## Praca nad kodem

1. Zrób fork i utwórz gałąź od `main`, np. `poprawka-dat-w-przypomnieniach`.
2. Przygotuj projekt:
   ```sh
   brew install xcodegen
   xcodegen generate
   open Reminder.xcodeproj
   ```
3. Projekt generuje XcodeGen z `project.yml`. Nowe pliki i ustawienia dodawaj tam, a nie tylko w Xcode, bo `xcodegen generate` nadpisze `Reminder.xcodeproj`.
4. Uruchom testy:
   ```sh
   xcodebuild test -project Reminder.xcodeproj -scheme Reminder \
     -destination 'platform=iOS Simulator,name=iPhone 17'
   ```
5. Otwórz pull request z opisem zmian. CI zbuduje projekt i uruchomi testy.

### Bez mikrofonu w symulatorze

Symulator nie obsługuje dyktowania. Do sprawdzania UI służy tryb demo (tylko build Debug), np.:

```sh
xcrun simctl launch booted software.plq.niezapominajka -demo multi
```

Stany: `home`, `listening`, `result`, `multi`, `sms`, `settings`. Pełny przepływ z mową testuj na iPhonie z własnym kluczem Claude API.

## Styl

- Swift i SwiftUI, styl jak w istniejącym kodzie.
- Teksty w aplikacji i komentarze są po polsku.
- Logikę, którą da się sprawdzić bez urządzenia (np. parsowanie odpowiedzi Claude, formatowanie dat), pokrywaj testami w `ReminderTests`.
- Jeden PR = jedna zmiana. Małe PR-y szybciej trafiają do `main`.

## Licencja

Wysyłając pull request, zgadzasz się, że twój wkład będzie udostępniony na licencji [MIT](LICENSE), tak jak cały projekt.

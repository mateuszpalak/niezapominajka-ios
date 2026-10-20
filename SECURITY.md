# Bezpieczeństwo

## Zgłaszanie podatności

Jeśli znajdziesz lukę bezpieczeństwa, **nie zgłaszaj jej w publicznym issue**.

Użyj [prywatnego zgłoszenia na GitHubie](https://github.com/mateuszpalak/niezapominajka-ios/security/advisories/new). Opisz problem, jak go powtórzyć i jakie może mieć skutki. Odpowiem najszybciej, jak się da, zwykle w ciągu kilku dni.

## Zakres

Szczególnie interesują mnie:

- wyciek klucza Claude API z urządzenia albo w ruchu sieciowym,
- wykonanie akcji (SMS, połączenie, zapis w kalendarzu) bez wiedzy użytkownika,
- przekazanie do Claude danych innych niż tekst polecenia.

## Wspierane wersje

Poprawki bezpieczeństwa trafiają do najnowszej wersji z gałęzi `main`.

import Foundation

/// Realistic Polish meeting-summary strings for the §9 feasibility spike.
/// Each contains decisions + action items representative of a real personal-assistant workload.
enum PolishMeetingSummaries {
    static let all: [String] = [
        // 1. Product planning
        """
        Spotkanie z zespołem produktowym w sprawie roadmapy na Q3. Zdecydowaliśmy, \
        że priorytetem jest redesign ekranu onboardingu. Kacper przygotuje makiety do piątku. \
        Tomek sprawdzi czy mamy wystarczające zasoby backendowe. Umówiliśmy się na follow-up \
        za dwa tygodnie. Trzeba też wysłać podsumowanie do stakeholderów przed końcem dnia.
        """,

        // 2. Client review
        """
        Rozmowa z klientem dotycząca projektu migracji danych. Klient zaakceptował harmonogram, \
        ale poprosił o dodatkowy raport z postępu co tydzień. Ustaliliśmy, że migracja \
        etapu pierwszego zakończy się 30 czerwca. Muszę zaktualizować kontrakt i wysłać \
        go do podpisu. Dodatkowo należy przygotować środowisko testowe do środy.
        """,

        // 3. Design critique
        """
        Przegląd projektu graficznego nowej aplikacji mobilnej. Zatwierdzono paletę kolorów \
        i typografię. Natomiast ikony wymagają poprawek — Ania przerobi je do poniedziałku. \
        Postanowiliśmy usunąć animację wejścia, bo spowalnia czas ładowania. \
        Potrzebujemy nowego zestawu ikon eksportowanych w trzech rozdzielczościach. \
        Następny przegląd w przyszłym tygodniu po poprawkach.
        """,

        // 4. Sprint retrospective
        """
        Retrospektywa sprintu nr 14. Zespół wskazał, że zbyt dużo czasu tracimy na \
        ręczne testy regresyjne. Zdecydowaliśmy wdrożyć automatyczne testy UI do końca miesiąca. \
        Bartek napisze plan wdrożenia do czwartku. Poprawiliśmy też definicję done — \
        od teraz każde zadanie musi mieć testy jednostkowe. Trzeba zaktualizować dokumentację \
        procesu w Confluence i poinformować cały zespół.
        """,

        // 5. Budget review
        """
        Spotkanie z dyrektorem finansowym w sprawie budżetu na kolejny kwartał. \
        Zaakceptowano dodatkowe 20 tysięcy na infrastrukturę chmurową. Muszę przesłać \
        zaktualizowany kosztorys do księgowości do jutra rano. Omówiliśmy też możliwość \
        zatrudnienia dodatkowego inżyniera — decyzja za dwa tygodnie po analizie obciążenia \
        zespołu. Potrzebna jest prezentacja wyników dla zarządu na koniec miesiąca.
        """,
    ]
}

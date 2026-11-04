import Foundation

/// Localisation minimale, sans fichiers .strings : l'app suit la langue du
/// système. Français si la langue préférée commence par « fr », anglais sinon.
///
/// Minimal localisation, no .strings files: the app follows the system
/// language. French when the preferred language starts with "fr", else English.
enum L {
    static let isFrench: Bool = {
        guard let first = Locale.preferredLanguages.first?.lowercased() else { return false }
        return first.hasPrefix("fr")
    }()

    /// `L.t("English text", "Texte français")`
    static func t(_ en: String, _ fr: String) -> String {
        isFrench ? fr : en
    }

    /// Nombre accordé : `L.count(3, en: "item", fr: "élément")` → "3 items" / "3 éléments".
    /// L'anglais met le pluriel dès que n ≠ 1, le français seulement au-delà de 1.
    /// `enPlural` sert aux pluriels irréguliers (« match » → « matches »).
    static func count(_ n: Int, en: String, enPlural: String? = nil, fr: String) -> String {
        if isFrench {
            return "\(n) " + (n > 1 ? fr + "s" : fr)
        }
        return "\(n) " + (n == 1 ? en : (enPlural ?? en + "s"))
    }

    /// Locale utilisée pour les dates relatives (« 2 min ago » / « il y a 2 min »).
    static var dateLocale: Locale {
        isFrench ? Locale(identifier: "fr_FR") : Locale(identifier: "en_US")
    }
}

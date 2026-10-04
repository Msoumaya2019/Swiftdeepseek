// Coran1441Install.swift
// Les règles d'installation du Coran 1441 : nom des fichiers, bornes, validité
// d'une image, et marqueur de fin.
//
// POURQUOI CES RÈGLES SONT ICI, ET PAS DANS LE SERVICE
//   Elles sont pures : ni réseau, ni disque, ni horloge. Cela les rend
//   éprouvables sur des octets construits pour l'occasion, sans télécharger
//   102 Mo ni attendre une connexion. Le service, lui, ne fait que les
//   enchaîner.
//
// D'OÙ VIENNENT CES RÈGLES
//   De `src/services/quranDownload.ts` de l'application React Native, qui les
//   applique déjà. Elles ne sont pas réinventées : une archive acceptée ici doit
//   l'être là-bas, et réciproquement.
//
//   | Règle | Original |
//   | --- | --- |
//   | Nom dans l'archive | `^width_1440/(\d+)/(\d+)\.png$` (`:81`) |
//   | Bornes | page 1…604, ligne 1…15 (`:84`) |
//   | Nom installé | `%03d-%02d.png` (`:85`) |
//   | Taille maximale | 2 Mio par image (`:90`) |
//   | Validité | signature PNG, puis `1440 × 232` (`:93`) |
//   | Total exigé | 9 060 fichiers (`:110`) |
//   | Marqueur | `ready-v1.json`, `version: 1` (`:111`) |
//
//   Les bornes de pages et de lignes ne sont pas recopiées de l'original : elles
//   viennent de `QuranSourceService.totalPages` et `VerseBounds.linesPerPage`,
//   déjà éprouvés. Deux constantes qui doivent valoir la même chose finissent
//   par diverger ; une seule ne le peut pas.
//
// UN ÉCART ASSUMÉ, ET POURQUOI
//   L'original ne vérifie que les **deux premiers** octets de la signature PNG
//   (`bytes[0]!==137||bytes[1]!==80`, `:93`). Ici les **huit** sont vérifiés.
//   Ce n'est pas une divergence de comportement : une image PNG véritable porte
//   toujours les huit octets, donc rien de valide n'est refusé. C'est une garde
//   en plus contre une archive corrompue, qui produirait sinon des pages
//   affichées à moitié.

import Foundation

public enum Coran1441Install {

    // MARK: Ce qui est attendu

    /// Nombre de pages du Moushaf. Vient de la source, n'est pas recopié.
    public static var pages: Int { QuranSourceService.totalPages }

    /// Bandes par page. Vient de `VerseBounds`, qui porte déjà la géométrie.
    public static var linesPerPage: Int { VerseBounds.linesPerPage }

    /// Nombre d'images qu'une installation complète doit contenir — 9 060.
    public static var requiredFileCount: Int { pages * linesPerPage }

    /// Largeur d'une bande, en pixels — `VerseBounds.imageSize.width`.
    public static var imageWidth: Int { Int(VerseBounds.imageSize.width) }

    /// Hauteur d'une bande, en pixels. Ce n'est **pas** la hauteur de la page :
    /// une page du 1441 fait `1440 × 2320` et contient quinze bandes de 232,
    /// réparties à pas constant (voir `VerseBounds.bandRect`).
    public static var imageHeight: Int { Int(VerseBounds.coran1441BandHeight) }

    /// Taille maximale admise pour une image — 2 Mio (`quranDownload.ts:90`).
    public static let maximumImageBytes = 2 * 1_024 * 1_024

    /// Taille exacte de l'archive publiée (`quranDownload.ts:6`).
    ///
    /// Elle sert de contrôle d'intégrité : un téléchargement interrompu rend
    /// presque toujours un fichier plus court, et une archive tronquée se lit
    /// comme une archive valide tant qu'on n'a pas atteint la fin. Comparer la
    /// taille évite de découvrir le problème au milieu de l'extraction.
    public static let archiveBytes = 102_608_011

    /// L'archive publiée — même adresse que l'application React Native.
    public static var archiveURL: URL? { QuranSourceService.coran1441ArchiveURL }

    /// Nom du dossier d'installation, sous le dossier de téléchargement.
    public static var folderName: String { QuranSourceService.coran1441FolderName }

    /// Nom du marqueur d'installation terminée.
    public static let markerName = "ready-v1.json"

    /// Nom du ZIP en cours de téléchargement, dans le dossier d'installation.
    public static let archiveName = "download.zip"

    /// Nom du fichier de reprise d'un téléchargement interrompu.
    ///
    /// Nommé `.bin` et non `.json` comme dans l'original : le contenu est le
    /// jeton binaire rendu par `URLSession`, pas du JSON. L'original l'enveloppe
    /// dans un objet JSON parce que son API le lui rend sous forme de chaîne —
    /// ce que Swift n'exige pas. Ce fichier est interne à une application et
    /// n'est jamais relu par l'autre ; seul le nom des images et le marqueur
    /// doivent coïncider.
    public static let resumeName = "resume.bin"

    /// Témoin écrit quand le ZIP est complet, avant extraction.
    public static let downloadCompleteName = "download-complete.json"

    /// Version du marqueur comprise par cette application.
    public static let markerVersion = 1

    // MARK: Nom des fichiers

    /// Le nom du fichier installé pour une bande donnée.
    ///
    /// `page` est **1-basée** et `line` **1-basée** : `(1, 1)` donne
    /// `001-01.png`. C'est le nom que lit `QuranSourceService.imageURLs`, qui
    /// construit `%03d-%02d.png` pour `index + 1` avec `index` de 0 à 14.
    ///
    /// Rend `nil` hors bornes, plutôt qu'un nom plausible pour une page qui
    /// n'existe pas.
    public static func fileName(page: Int, line: Int) -> String? {
        guard (1...pages).contains(page), (1...linesPerPage).contains(line) else { return nil }
        return String(format: "%03d-%02d.png", page, line)
    }

    /// L'emplacement décrit par un chemin de l'archive.
    ///
    /// `width_1440/12/3.png` donne `(page: 12, line: 3)`.
    ///
    /// Reproduit exactement `^width_1440/(\d+)/(\d+)\.png$` (`quranDownload.ts:81`),
    /// mais **sans expression régulière** : le motif n'a qu'une forme, et une
    /// analyse directe dit la même chose sans dépendre d'un moteur. Le `^` et le
    /// `$` de l'original comptent — ils refusent `autre/width_1440/1/1.png` et
    /// `width_1440/1/1.png.bak`. D'où les contrôles de préfixe et de suffixe,
    /// et le refus de tout segment supplémentaire.
    ///
    /// Rend `nil` pour tout ce qui ne correspond pas : c'est ainsi que l'original
    /// refuse de « extraire des chemins arbitraires ou des bases de données »
    /// (`:82`) — l'archive peut contenir autre chose que des images.
    public static func location(inArchivePath path: String) -> (page: Int, line: Int)? {
        let prefix = "width_1440/"
        let suffix = ".png"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return nil }

        let middle = path.dropFirst(prefix.count).dropLast(suffix.count)
        let parts = middle.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        // `\d+` refuse la chaîne vide ; `Int("")` aussi, mais le dire
        // explicitement évite de dépendre de ce détail.
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        // `Int()` accepterait « +7 » et « ٧ » (chiffre arabo-indien). Le motif de
        // l'original, `\d+`, ne les accepte pas. Rester sur des chiffres ASCII
        // évite d'installer une image sous un nom que personne n'attend.
        guard parts[0].allSatisfy(isASCIIDigit), parts[1].allSatisfy(isASCIIDigit) else { return nil }

        guard let page = Int(parts[0]), let line = Int(parts[1]) else { return nil }
        return (page, line)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }

    // MARK: Validité d'une image

    /// Les huit octets qui ouvrent tout fichier PNG.
    public static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Une image de bande du Coran 1441 est-elle valide ?
    ///
    /// Trois contrôles, dans cet ordre : la taille, la signature, puis les
    /// dimensions lues dans l'en-tête `IHDR`.
    ///
    /// Les dimensions sont en **gros-boutiste** — c'est l'ordre du format PNG,
    /// et l'inverse de celui du ZIP, qui est petit-boutiste. Les confondre
    /// donne `0x0900` au lieu de `0x05A0` : une image refusée, ou pire, une
    /// image acceptée avec les mauvaises dimensions.
    ///
    /// L'en-tête `IHDR` commence au seizième octet : 8 de signature, 4 de
    /// longueur de bloc, 4 de type. La largeur occupe les octets 16 à 19, la
    /// hauteur les octets 20 à 23 — exactement ce que lit l'original
    /// (`quranDownload.ts:93`).
    public static func isValidPageImage(_ data: Data) -> Bool {
        guard data.count >= 24, data.count <= maximumImageBytes else { return false }
        guard data.prefix(pngSignature.count).elementsEqual(pngSignature) else { return false }
        guard data.u32BigEndian(16) == UInt32(imageWidth),
              data.u32BigEndian(20) == UInt32(imageHeight) else { return false }
        return true
    }

    // MARK: Ce qui peut échouer

    /// Les échecs de l'installation.
    ///
    /// Déclarés ici, et non dans le service : ils décrivent les règles de
    /// l'installation, pas son exécution — et le code qui les lève n'est pas
    /// toujours sur le fil principal. Les y placer évite de faire dépendre la
    /// construction d'une erreur d'un contexte d'exécution.
    public enum Failure: LocalizedError, Equatable {
        case archiveMissing
        case archiveSizeMismatch(expected: Int, found: Int)
        case pageOutOfRange(String)
        case imageTooLarge(String)
        case invalidImage(String)
        case incomplete(count: Int)

        public var errorDescription: String? {
            switch self {
            case .archiveMissing:
                return "L'adresse de l'archive du Coran 1441 est introuvable."
            case .archiveSizeMismatch(let expected, let found):
                return "Téléchargement incomplet (\(found) octets sur \(expected)). Réessaie avec une connexion stable."
            case .pageOutOfRange(let name):
                return "L'archive contient une page hors bornes (« \(name) »). Ce n'est pas celle attendue."
            case .imageTooLarge(let name):
                return "Une image de l'archive dépasse la taille admise (« \(name) »)."
            case .invalidImage(let name):
                return "Une image du Moushaf est invalide (« \(name) »). L'archive est corrompue."
            case .incomplete(let count):
                return "Certaines pages sont manquantes (\(count) sur \(requiredFileCount)). Réessaie."
            }
        }
    }

    // MARK: Marqueur d'installation

    /// Le contenu de `ready-v1.json`.
    ///
    /// Les trois champs sont ceux de l'original (`quranDownload.ts:111`) :
    /// `version`, `files`, `installedAt`. `version` et `files` sont lus ;
    /// `installedAt` est conservé pour que l'application React Native, si elle
    /// relit ce dossier, y retrouve ce qu'elle a écrit.
    public struct Ready: Codable, Equatable, Sendable {
        public var version: Int
        public var files: Int
        public var installedAt: String

        public init(version: Int, files: Int, installedAt: String) {
            self.version = version
            self.files = files
            self.installedAt = installedAt
        }
    }

    /// Lit le marqueur d'un dossier d'installation, s'il existe et s'il est
    /// compris.
    public static func ready(in directory: URL, fileManager: FileManager = .default) -> Ready? {
        let url = directory.appendingPathComponent(markerName)
        guard let data = fileManager.contents(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(Ready.self, from: data)
    }

    /// L'installation est-elle complète ?
    ///
    /// Reproduit `quranDownloaded()` (`quranDownload.ts:17`) : il faut un
    /// marqueur, **et** la bonne version, **et** le bon nombre de fichiers. Un
    /// marqueur seul ne suffit pas — un dossier amputé après coup resterait
    /// déclaré prêt, et le lecteur afficherait des pages à moitié vides.
    ///
    /// Le nombre est relu dans le marqueur, et non recompté sur le disque : c'est
    /// le marqueur qui fait foi, et le recompter à chaque affichage coûterait
    /// 9 060 appels au système de fichiers.
    public static func isReady(in directory: URL, fileManager: FileManager = .default) -> Bool {
        guard let marker = ready(in: directory, fileManager: fileManager) else { return false }
        return marker.version == markerVersion && marker.files == requiredFileCount
    }
}

// MARK: - Lecture gros-boutiste

extension Data {
    /// Entier 32 bits en **gros-boutiste** — l'ordre du format PNG, à l'inverse
    /// de celui du ZIP. Les deux existent dans ce projet ; les nommer
    /// différemment évite de les confondre.
    func u32BigEndian(_ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let base = startIndex + offset
        return (UInt32(self[base]) << 24)
            | (UInt32(self[base + 1]) << 16)
            | (UInt32(self[base + 2]) << 8)
            | UInt32(self[base + 3])
    }
}

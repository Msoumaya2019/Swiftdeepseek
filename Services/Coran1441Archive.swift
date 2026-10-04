// Coran1441Archive.swift
// Lecture d'une archive ZIP, sans dépendance externe.
//
// POURQUOI CE FICHIER EXISTE
//   Le Coran 1441 n'est pas embarqué dans l'application : ses 9 060 images
//   vivent dans une archive ZIP de 102 608 011 octets, publiée par la même
//   source que celle qu'utilise l'application React Native
//   (`src/services/quranDownload.ts:5`). Pour les installer, il faut lire un
//   ZIP — et Foundation n'expose aucune API publique pour cela.
//
//   L'application d'origine s'appuie sur `fflate`. Ici, pas de dépendance : le
//   format est lu directement. C'est peu de code, et cela évite d'ajouter un
//   paquet à un projet qui n'en a aucun (voir `project.yml`, « Aucune
//   dépendance externe »).
//
// CE QUE CE FICHIER LIT, ET RIEN DE PLUS
//   Le répertoire central (qui porte les tailles et les décalages réels) et les
//   en-têtes locaux (qui portent l'emplacement des données). Il ne lit ni les
//   attributs, ni les dates, ni le commentaire, ni le CRC — aucun n'est utile
//   ici, et un champ non lu est un champ qui ne peut pas être mal lu.
//
// LES DEUX MÉTHODES DE COMPRESSION
//   0 — « stored » : les octets sont recopiés tels quels.
//   8 — « deflate » : flux DEFLATE BRUT (RFC 1951), sans en-tête ni somme zlib.
//   Toute autre valeur fait échouer la lecture, plutôt que de produire un
//   fichier silencieusement faux.
//
//   Le point qui mérite d'être prouvé plutôt que supposé : la constante
//   `COMPRESSION_ZLIB` d'Apple désigne bien le DEFLATE **brut**, celui d'un ZIP,
//   et non un flux enveloppé d'un en-tête zlib. Les deux formats diffèrent de
//   deux octets au début et quatre à la fin ; se tromper donne une archive
//   entière illisible. C'est mesuré par `Coran1441DownloadTests`, sur deux
//   flux construits pour l'occasion — l'un brut, l'autre enveloppé — et sur
//   l'exigence que le second **échoue**.
//
// POURQUOI `Reader` PLUTÔT QU'UN `Data`
//   L'archive pèse 102 Mo. La charger entièrement en mémoire pour n'en extraire
//   que des images de quelques kilo-octets serait un gaspillage qui, sur un
//   appareil chargé, se termine en fermeture par le système. Tout passe donc
//   par une closure de lecture ; le service lui donne un `FileHandle`, et les
//   tests lui donnent un `Data` en mémoire. Le même code sert aux deux, et
//   c'est le code de production qui est testé.

import Compression
import Foundation

public enum Coran1441Archive {

    // MARK: Échecs

    public enum Failure: LocalizedError, Equatable {
        case noCentralDirectory
        case truncated
        case notALocalHeader(String)
        case unsupportedCompression(UInt16)
        case inflationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noCentralDirectory:
                return "Ce fichier n'est pas une archive ZIP lisible."
            case .truncated:
                return "L'archive est incomplète : le téléchargement doit être repris."
            case .notALocalHeader(let name):
                return "L'entrée « \(name) » de l'archive est illisible."
            case .unsupportedCompression(let method):
                return "L'archive utilise une compression non gérée (\(method))."
            case .inflationFailed(let name):
                return "Le contenu de « \(name) » n'a pas pu être décompressé."
            }
        }
    }

    // MARK: Une entrée

    /// Une entrée du répertoire central — c'est-à-dire un fichier de l'archive.
    ///
    /// Les tailles viennent du **répertoire central**, jamais de l'en-tête
    /// local : quand un archiveur écrit les données en flux, il laisse les
    /// tailles à zéro dans l'en-tête local et les renseigne après coup dans le
    /// répertoire central. Lire les tailles locales donnerait zéro octet à
    /// extraire, sans erreur — un fichier vide au lieu d'une image.
    public struct Entry: Equatable, Sendable {
        public let name: String
        public let method: UInt16
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let localHeaderOffset: Int

        public init(
            name: String,
            method: UInt16,
            compressedSize: Int,
            uncompressedSize: Int,
            localHeaderOffset: Int
        ) {
            self.name = name
            self.method = method
            self.compressedSize = compressedSize
            self.uncompressedSize = uncompressedSize
            self.localHeaderOffset = localHeaderOffset
        }
    }

    /// Lit `length` octets à partir de `offset`. Peut rendre moins que demandé
    /// en fin de fichier — l'appelant doit vérifier.
    public typealias Reader = (_ offset: Int, _ length: Int) throws -> Data

    /// Le répertoire central : où il commence, quelle taille il a, combien
    /// d'entrées il décrit.
    public struct CentralDirectory: Equatable, Sendable {
        public let offset: Int
        public let size: Int
        public let count: Int

        public init(offset: Int, size: Int, count: Int) {
            self.offset = offset
            self.size = size
            self.count = count
        }
    }

    // MARK: Signatures

    static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    static let centralFileHeaderSignature: UInt32 = 0x0201_4b50
    static let localFileHeaderSignature: UInt32 = 0x0403_4b50

    /// Taille d'un enregistrement de fin de répertoire central.
    static let endOfCentralDirectoryLength = 22
    /// Taille d'un en-tête de fichier du répertoire central.
    static let centralFileHeaderLength = 46
    /// Taille d'un en-tête local.
    static let localFileHeaderLength = 30
    /// Longueur maximale du commentaire d'archive — elle décide de la fenêtre
    /// dans laquelle chercher l'enregistrement de fin.
    static let maximumCommentLength = 65_535

    /// La fenêtre de fin à lire pour trouver l'enregistrement de fin : sa
    /// taille plus le commentaire maximal qui peut le suivre.
    public static let tailLength = endOfCentralDirectoryLength + maximumCommentLength

    // MARK: Enregistrement de fin

    /// Trouve le répertoire central d'une archive.
    ///
    /// - Parameters:
    ///   - fileSize: taille totale de l'archive.
    ///   - tail: les **derniers** octets de l'archive, au plus `tailLength`.
    ///
    /// Le décalage du répertoire central est lu **dans** l'enregistrement de fin,
    /// et il est déjà compté depuis le début de l'archive : la position de la
    /// fenêtre de fin n'entre donc pas dans le calcul du résultat.
    ///
    /// L'enregistrement de fin est cherché **en remontant** depuis la fin : il
    /// peut être suivi d'un commentaire d'archive, et un commentaire peut
    /// contenir la signature par hasard. Partir du début trouverait alors le
    /// commentaire au lieu de l'enregistrement.
    ///
    /// Remonter ne suffit pas pour autant : le commentaire est **après**
    /// l'enregistrement, donc c'est lui qu'on rencontre en premier. Un candidat
    /// n'est donc retenu que si le répertoire qu'il décrit se termine
    /// **exactement** là où il commence — le répertoire central précède
    /// immédiatement l'enregistrement de fin dans tout ZIP bien formé. C'est
    /// cette égalité, et non la signature seule, qui distingue le vrai
    /// enregistrement d'une suite d'octets qui lui ressemble.
    ///
    /// Si aucune correspondance exacte n'est trouvée, un candidat dont les
    /// bornes tiennent dans l'archive est accepté en repli : certaines archives
    /// intercalent un enregistrement de signature entre les deux, et refuser une
    /// archive lisible serait pire que d'accepter la première correspondance
    /// plausible.
    public static func centralDirectory(
        fileSize: Int,
        tail: Data
    ) throws -> CentralDirectory {
        guard tail.count >= endOfCentralDirectoryLength else { throw Failure.noCentralDirectory }
        guard tail.count <= fileSize else { throw Failure.truncated }

        let tailStart = fileSize - tail.count
        var fallback: CentralDirectory?

        var cursor = tail.count - endOfCentralDirectoryLength
        while cursor >= 0 {
            if tail.u32(cursor) == endOfCentralDirectorySignature,
               let count = tail.u16(cursor + 10),
               let size = tail.u32(cursor + 12),
               let offset = tail.u32(cursor + 16) {
                let directory = CentralDirectory(
                    offset: Int(offset),
                    size: Int(size),
                    count: Int(count)
                )
                let endPosition = tailStart + cursor
                let withinArchive = directory.offset >= 0
                    && directory.size >= 0
                    && directory.offset + directory.size <= fileSize

                if withinArchive, directory.offset + directory.size == endPosition {
                    return directory
                }
                if withinArchive, fallback == nil {
                    fallback = directory
                }
            }
            cursor -= 1
        }

        if let fallback { return fallback }
        throw Failure.noCentralDirectory
    }

    // MARK: Répertoire central

    /// Lit les entrées décrites par un répertoire central.
    ///
    /// Le parcours s'arrête au premier enregistrement dont la signature n'est
    /// pas celle attendue, ou dès que `count` entrées ont été lues. Le nombre
    /// annoncé fait foi : un répertoire central peut être suivi d'autres
    /// données, et s'y fier aveuglément produirait des entrées fantômes.
    public static func entries(centralDirectory: Data, count: Int) throws -> [Entry] {
        var result: [Entry] = []
        result.reserveCapacity(count)

        var cursor = 0
        while result.count < count {
            guard cursor + centralFileHeaderLength <= centralDirectory.count else {
                throw Failure.truncated
            }
            guard centralDirectory.u32(cursor) == centralFileHeaderSignature else {
                throw Failure.truncated
            }
            guard let method = centralDirectory.u16(cursor + 10),
                  let compressedSize = centralDirectory.u32(cursor + 20),
                  let uncompressedSize = centralDirectory.u32(cursor + 24),
                  let nameLength = centralDirectory.u16(cursor + 28),
                  let extraLength = centralDirectory.u16(cursor + 30),
                  let commentLength = centralDirectory.u16(cursor + 32),
                  let localOffset = centralDirectory.u32(cursor + 42) else {
                throw Failure.truncated
            }

            let nameStart = cursor + centralFileHeaderLength
            let nameEnd = nameStart + Int(nameLength)
            guard nameEnd <= centralDirectory.count else { throw Failure.truncated }

            // Le décalage part de `startIndex`, comme les lectures d'entiers :
            // `subdata(in:)` attend des indices du récepteur, et un `Data` reçu
            // en tranche ne commence pas à zéro.
            let base = centralDirectory.startIndex
            let nameData = centralDirectory.subdata(in: (base + nameStart)..<(base + nameEnd))
            // Les noms d'un ZIP sont censés être en UTF-8 quand le drapeau 0x800
            // est posé, et en CP437 sinon. Les archives du Moushaf n'utilisent
            // que des caractères ASCII ; une conversion qui échoue est donc le
            // signe d'une entrée qui ne nous concerne pas, et non d'un cas à
            // gérer.
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw Failure.truncated
            }

            result.append(
                Entry(
                    name: name,
                    method: method,
                    compressedSize: Int(compressedSize),
                    uncompressedSize: Int(uncompressedSize),
                    localHeaderOffset: Int(localOffset)
                )
            )

            cursor = nameEnd + Int(extraLength) + Int(commentLength)
        }
        return result
    }

    // MARK: Contenu d'une entrée

    /// Lit et décompresse le contenu d'une entrée.
    ///
    /// Le décalage des données n'est **pas** celui de l'en-tête local : il faut
    /// d'abord lire cet en-tête pour connaître la longueur de son nom et de son
    /// champ d'extension, qui varient d'une entrée à l'autre. Utiliser le
    /// décalage de l'en-tête comme décalage des données lit l'en-tête lui-même
    /// au lieu de l'image — un résultat qui a la bonne taille et pas le bon
    /// contenu.
    public static func contents(of entry: Entry, read: Reader) throws -> Data {
        let header = try read(entry.localHeaderOffset, localFileHeaderLength)
        guard header.count >= localFileHeaderLength,
              header.u32(0) == localFileHeaderSignature else {
            throw Failure.notALocalHeader(entry.name)
        }
        guard let nameLength = header.u16(26),
              let extraLength = header.u16(28) else {
            throw Failure.notALocalHeader(entry.name)
        }

        let dataOffset = entry.localHeaderOffset
            + localFileHeaderLength
            + Int(nameLength)
            + Int(extraLength)

        switch entry.method {
        case 0:
            let stored = try read(dataOffset, entry.compressedSize)
            guard stored.count == entry.compressedSize else { throw Failure.truncated }
            return stored
        case 8:
            guard entry.compressedSize > 0 else { return Data() }
            let compressed = try read(dataOffset, entry.compressedSize)
            guard compressed.count == entry.compressedSize else { throw Failure.truncated }
            return try inflate(compressed, expecting: entry.uncompressedSize, name: entry.name)
        default:
            throw Failure.unsupportedCompression(entry.method)
        }
    }

    /// Décompresse un flux DEFLATE brut.
    ///
    /// `expecting` est la taille annoncée par le répertoire central. Elle sert à
    /// dimensionner la destination en une fois, ce qui évite les réallocations
    /// sur 9 060 images. Quand elle vaut zéro — l'archive n'a pas renseigné la
    /// taille — la destination double jusqu'à convenir.
    ///
    /// `COMPRESSION_ZLIB` désigne ici le DEFLATE **brut** : c'est le nom de la
    /// constante, pas celui du format qu'elle encode. Un flux enveloppé d'un
    /// en-tête zlib n'est pas décodé par cette fonction — et c'est voulu, un ZIP
    /// n'en contient pas.
    static func inflate(_ source: Data, expecting: Int, name: String) throws -> Data {
        guard !source.isEmpty else { return Data() }

        var capacity = max(expecting, 4_096)
        // Borne haute : la plus grosse image admise, avec de la marge. Au-delà,
        // c'est que le flux est corrompu et non qu'il est volumineux.
        let ceiling = 8 * 1_024 * 1_024

        while capacity <= ceiling {
            var destination = Data(count: capacity)
            let written = destination.withUnsafeMutableBytes { output -> Int in
                guard let outputBase = output.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return source.withUnsafeBytes { input -> Int in
                    guard let inputBase = input.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(
                        outputBase,
                        capacity,
                        inputBase,
                        source.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }

            if written > 0 {
                return Data(destination.prefix(written))
            }
            // La taille annoncée était connue : un échec à cette taille est un
            // vrai échec, pas un manque de place.
            if expecting > 0 { break }
            capacity *= 2
        }
        throw Failure.inflationFailed(name)
    }
}

// MARK: - Lecture d'entiers

/// Lecture de petits-boutistes, comme le veut le format ZIP.
///
/// Les décalages sont comptés depuis `startIndex` : `Data` peut être une
/// tranche, dont les indices ne commencent pas à zéro. Les compter depuis zéro
/// marcherait sur un `Data` neuf et lirait à côté sur une tranche — le genre
/// d'erreur qui ne se voit que sur les données réelles.
extension Data {
    func u16(_ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let base = startIndex + offset
        return UInt16(self[base]) | (UInt16(self[base + 1]) << 8)
    }

    func u32(_ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let base = startIndex + offset
        return UInt32(self[base])
            | (UInt32(self[base + 1]) << 8)
            | (UInt32(self[base + 2]) << 16)
            | (UInt32(self[base + 3]) << 24)
    }
}

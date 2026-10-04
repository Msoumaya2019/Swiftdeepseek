// Coran1441DownloadTests.swift
// L'installation du Coran 1441 : lecture du ZIP, décompression, nommage,
// validation des images, marqueur de fin.
//
// POURQUOI CES TESTS SONT ÉCRITS AINSI
//   Rien de tout ceci ne peut être essayé à la main : il faudrait télécharger
//   102 Mo, attendre, et regarder 9 060 fichiers. Les tests portent donc sur
//   l'**archive elle-même**, construite octet par octet ici, et sur un flux
//   DEFLATE produit par un autre outil que le code testé.
//
// LE TEST QUI COMPTE LE PLUS
//   `testARawDeflateStreamIsDecoded` et `testAZlibWrappedStreamIsNotDecoded`
//   forment une paire. La constante `COMPRESSION_ZLIB` d'Apple pourrait
//   désigner un flux DEFLATE **brut** — celui d'un ZIP — ou un flux enveloppé
//   d'un en-tête zlib. Les deux se ressemblent, et se tromper rend l'archive
//   entière illisible. Le premier test exige que le flux **brut** soit décodé,
//   le second exige que le flux **enveloppé** ne le soit **pas**. Un seul des
//   deux ne prouverait rien : il passerait avec l'une ou l'autre sémantique.
//
//   Les deux flux sont produits par `zlib` (via Python), pas par le framework
//   Apple. Un aller-retour avec le seul framework serait vert quelle que soit
//   sa sémantique, puisque les deux côtés se tromperaient ensemble.

import Compression
import CryptoKit
import XCTest
@testable import Swiftdeepseek

final class Coran1441DownloadTests: XCTestCase {

    // MARK: Constantes de référence

    /// Le PNG de référence : 1 051 octets, `1440 × 232`, produit par `zlib`.
    static let referencePNGBytes = 1_051
    static let referencePNGSHA256 = "6aa1d1d58511354beadfb21bf8e0bfefb37e68df032e8b052ca03f152ad8a6ff"

    /// Ce même PNG, compressé en DEFLATE **brut** (`wbits = -15`) — la forme
    /// que porte un ZIP de méthode 8.
    static let rawDeflateBase64 =
        "6wzwc+flkuJiYGDg9fRwCWJgYF0AZL/gYAKS0z5esWRgYH7k6eIYUnHr7UFDRqDgoQVf/XN5+UGqRsEoGAVDH1QY+ZxkYPxb3bAPxPN09XNZ55TQBAA="

    /// Le même PNG, compressé avec l'en-tête et la somme **zlib** (`wbits = 15`).
    /// Ce n'est pas ce que contient un ZIP ; ce test existe pour l'exiger.
    static let zlibWrappedBase64 =
        "eNrrDPBz5+WS4mJgYOD19HAJYmBgXQBkv+BgApLTPl6xZGBgfuTp4hhScevtQUNGoOChBV/9c3n5QapGwSgYBUMfVBj5nGRg/FvdsA/E83T1c1nnlNAEADAuF3k="

    // MARK: La décompression

    /// Le flux brut doit être décodé, et rendre exactement le PNG attendu.
    ///
    /// L'empreinte est comparée, et pas seulement la taille : deux contenus de
    /// même longueur ne se distinguent pas autrement, et c'est précisément un
    /// contenu faux qu'on chercherait à ne pas produire.
    func testARawDeflateStreamIsDecoded() throws {
        let compressed = try XCTUnwrap(
            Data(base64Encoded: Self.rawDeflateBase64),
            "Le flux de référence doit être un base64 valide."
        )

        let png = try Coran1441Archive.inflate(
            compressed,
            expecting: Self.referencePNGBytes,
            name: "reference.png"
        )

        XCTAssertEqual(png.count, Self.referencePNGBytes)
        XCTAssertEqual(
            SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
            Self.referencePNGSHA256,
            "Le contenu décompressé n'est pas celui du PNG de référence."
        )
        XCTAssertTrue(
            Coran1441Install.isValidPageImage(png),
            "Le PNG de référence doit être accepté : c'est la forme réelle des images du Coran 1441."
        )
    }

    /// Le flux enveloppé d'un en-tête zlib doit être **refusé**.
    ///
    /// C'est ce test qui fixe la sémantique. S'il échoue, alors
    /// `COMPRESSION_ZLIB` attend un flux enveloppé — et c'est tout le lecteur
    /// d'archive qu'il faut corriger, pas ce test.
    func testAZlibWrappedStreamIsNotDecoded() throws {
        let wrapped = try XCTUnwrap(Data(base64Encoded: Self.zlibWrappedBase64))

        XCTAssertThrowsError(
            try Coran1441Archive.inflate(wrapped, expecting: Self.referencePNGBytes, name: "enveloppe.png"),
            "Un flux zlib ne doit pas être accepté comme du DEFLATE brut : un ZIP n'en contient pas."
        )
    }

    // MARK: Lecture du ZIP

    func testAStoredEntryIsExtractedVerbatim() throws {
        let image = Self.pageImage()
        let archive = Self.makeArchive([
            ArchiveEntry(name: "width_1440/1/1.png", method: 0, compressed: image, uncompressedSize: image.count)
        ])

        let entries = try Self.read(archive)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "width_1440/1/1.png")
        XCTAssertEqual(entries[0].method, 0)

        let contents = try Coran1441Archive.contents(of: entries[0], read: Self.reader(archive))
        XCTAssertEqual(contents, image)
    }

    func testADeflatedEntryIsExtracted() throws {
        let image = Self.pageImage()
        let compressed = Self.deflate(image)
        XCTAssertFalse(compressed.isEmpty, "La compression d'essai doit produire quelque chose.")

        let archive = Self.makeArchive([
            ArchiveEntry(
                name: "width_1440/7/3.png",
                method: 8,
                compressed: compressed,
                uncompressedSize: image.count
            )
        ])

        let entries = try Self.read(archive)
        let contents = try Coran1441Archive.contents(of: entries[0], read: Self.reader(archive))
        XCTAssertEqual(contents, image, "Le contenu décompressé doit être identique à l'original.")
    }

    /// Le décalage des données n'est pas celui de l'en-tête local : il dépend de
    /// la longueur du nom, qui varie d'une entrée à l'autre. Une entrée dont le
    /// nom est plus long que celui de la première décale toutes les suivantes.
    func testTheDataOffsetFollowsTheLengthOfEachName() throws {
        let short = Self.pageImage(padding: 32)
        let long = Self.pageImage(padding: 96)

        let archive = Self.makeArchive([
            ArchiveEntry(name: "width_1440/1/1.png", method: 0, compressed: short, uncompressedSize: short.count),
            ArchiveEntry(name: "width_1440/2/10.png", method: 0, compressed: long, uncompressedSize: long.count),
            ArchiveEntry(name: "width_1440/3/2.png", method: 0, compressed: short, uncompressedSize: short.count)
        ])

        let entries = try Self.read(archive)
        XCTAssertEqual(entries.count, 3)

        let read = Self.reader(archive)
        XCTAssertEqual(try Coran1441Archive.contents(of: entries[0], read: read), short)
        XCTAssertEqual(try Coran1441Archive.contents(of: entries[1], read: read), long)
        XCTAssertEqual(try Coran1441Archive.contents(of: entries[2], read: read), short)
    }

    /// Le commentaire d'archive peut contenir la signature de fin. Le lecteur
    /// doit trouver le vrai enregistrement, pas la suite d'octets qui lui
    /// ressemble dans le commentaire.
    func testTheEndOfTheArchiveIsFoundDespiteAComment() throws {
        let image = Self.pageImage()
        let entry = ArchiveEntry(name: "width_1440/1/1.png", method: 0, compressed: image, uncompressedSize: image.count)

        // Un commentaire qui contient la signature, et des octets plausibles.
        var comment = Data([0x50, 0x4B, 0x05, 0x06])
        comment.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        comment.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])
        comment.append(Data(repeating: 0x41, count: 40))

        let archive = Self.makeArchive([entry], comment: comment)
        let entries = try Self.read(archive)

        XCTAssertEqual(entries.count, 1, "Le répertoire central doit être trouvé malgré le commentaire.")
        XCTAssertEqual(entries[0].name, "width_1440/1/1.png")
    }

    func testAFileThatIsNotAnArchiveIsRefused() {
        let junk = Data(repeating: 0x2A, count: 4_096)
        XCTAssertThrowsError(try Self.read(junk))
    }

    // MARK: Nommage et bornes

    func testArchivePathsAreReadLikeTheOriginalPattern() {
        XCTAssertEqual(Coran1441Install.location(inArchivePath: "width_1440/1/1.png")?.page, 1)
        XCTAssertEqual(Coran1441Install.location(inArchivePath: "width_1440/1/1.png")?.line, 1)
        XCTAssertEqual(Coran1441Install.location(inArchivePath: "width_1440/604/15.png")?.page, 604)
        XCTAssertEqual(Coran1441Install.location(inArchivePath: "width_1440/12/3.png")?.line, 3)

        // Ce que le `^` et le `$` du motif de l'original refusent.
        XCTAssertNil(Coran1441Install.location(inArchivePath: "width_1440/1/1.png.bak"))
        XCTAssertNil(Coran1441Install.location(inArchivePath: "autre/width_1440/1/1.png"))
        XCTAssertNil(Coran1441Install.location(inArchivePath: "width_1440/1/1/2.png"))
        XCTAssertNil(Coran1441Install.location(inArchivePath: "width_1440/1/1.jpg"))
        XCTAssertNil(Coran1441Install.location(inArchivePath: "readme.txt"))
        XCTAssertNil(Coran1441Install.location(inArchivePath: "width_1440//1.png"))
        XCTAssertNil(Coran1441Install.location(inArchivePath: "width_1440/1/.png"))

        // `\d+` n'accepte ni le signe, ni les chiffres non ASCII.
        XCTAssertNil(Coran1441Install.location(inArchivePath: "width_1440/+7/1.png"))
        XCTAssertNil(Coran1441Install.location(inArchivePath: "width_1440/1/+7.png"))
        XCTAssertNil(Coran1441Install.location(inArchivePath: "width_1440/١/1.png"))
    }

    func testInstalledNamesAreZeroPadded() {
        XCTAssertEqual(Coran1441Install.fileName(page: 1, line: 1), "001-01.png")
        XCTAssertEqual(Coran1441Install.fileName(page: 9, line: 9), "009-09.png")
        XCTAssertEqual(Coran1441Install.fileName(page: 604, line: 15), "604-15.png")
        XCTAssertEqual(Coran1441Install.fileName(page: 100, line: 10), "100-10.png")

        XCTAssertNil(Coran1441Install.fileName(page: 0, line: 1))
        XCTAssertNil(Coran1441Install.fileName(page: 605, line: 1))
        XCTAssertNil(Coran1441Install.fileName(page: 1, line: 0))
        XCTAssertNil(Coran1441Install.fileName(page: 1, line: 16))
    }

    /// Les bornes ne sont pas recopiées : elles viennent de la source. Ce test
    /// vérifie qu'elles restent d'accord avec le nombre d'images attendu.
    func testTheExpectedCountIsTheProductOfPagesAndLines() {
        XCTAssertEqual(Coran1441Install.pages, 604)
        XCTAssertEqual(Coran1441Install.linesPerPage, 15)
        XCTAssertEqual(Coran1441Install.requiredFileCount, 9_060)
    }

    // MARK: Validité des images

    func testOnlyImagesOfTheRightDimensionsAreAccepted() {
        XCTAssertTrue(Coran1441Install.isValidPageImage(Self.pageImage()))

        // Bonne signature, mauvaises dimensions.
        XCTAssertFalse(Coran1441Install.isValidPageImage(Self.pageImage(width: 1_000, height: 232)))
        XCTAssertFalse(Coran1441Install.isValidPageImage(Self.pageImage(width: 1_440, height: 2_320)))

        // Signature absente ou tronquée.
        XCTAssertFalse(Coran1441Install.isValidPageImage(Data(repeating: 0x89, count: 64)))
        XCTAssertFalse(Coran1441Install.isValidPageImage(Data(Self.pageImage().dropLast(80))))
        XCTAssertFalse(Coran1441Install.isValidPageImage(Data()))
    }

    /// La largeur et la hauteur sont en **gros-boutiste** — l'ordre du PNG, à
    /// l'inverse du ZIP. Les confondre donnerait `0x00000900` au lieu de
    /// `0x000005A0`, et refuserait toutes les images réelles.
    func testTheDimensionsAreReadBigEndian() {
        var image = Data(Coran1441Install.pngSignature)
        image.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])
        image.append(contentsOf: Array("IHDR".utf8))
        image.append(contentsOf: [0x00, 0x00, 0x05, 0xA0])   // 1 440
        image.append(contentsOf: [0x00, 0x00, 0x00, 0xE8])   // 232
        image.append(Data(repeating: 0, count: 32))

        XCTAssertTrue(Coran1441Install.isValidPageImage(image))
    }

    // MARK: Extraction sur le disque

    func testAnEntryOutsideThePatternIsIgnored() throws {
        let image = Self.pageImage()
        let archive = Self.makeArchive([
            ArchiveEntry(name: "readme.txt", method: 0, compressed: Data("bonjour".utf8), uncompressedSize: 7),
            ArchiveEntry(name: "width_1440/1/1.png", method: 0, compressed: image, uncompressedSize: image.count),
            ArchiveEntry(name: "base.sqlite", method: 0, compressed: Data(repeating: 1, count: 16), uncompressedSize: 16)
        ])

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let installed = try Self.extract(archive, into: directory)

        XCTAssertEqual(installed, 1, "Seule l'image conforme doit être installée.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("001-01.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("readme.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("base.sqlite").path))
    }

    /// Un nom qui correspond au motif mais désigne une page hors bornes arrête
    /// l'installation, comme dans l'original (`quranDownload.ts:84`) : c'est le
    /// signe que l'archive n'est pas celle attendue.
    func testAPageOutsideTheBoundsStopsTheInstallation() throws {
        let image = Self.pageImage()
        let archive = Self.makeArchive([
            ArchiveEntry(name: "width_1440/1/1.png", method: 0, compressed: image, uncompressedSize: image.count),
            ArchiveEntry(name: "width_1440/700/1.png", method: 0, compressed: image, uncompressedSize: image.count)
        ])

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try Self.extract(archive, into: directory)) { error in
            XCTAssertEqual(
                error as? Coran1441Install.Failure,
                .pageOutOfRange("width_1440/700/1.png")
            )
        }
    }

    func testAnImageOfTheWrongDimensionsStopsTheInstallation() throws {
        let wrong = Self.pageImage(width: 1_000, height: 232)
        let archive = Self.makeArchive([
            ArchiveEntry(name: "width_1440/1/1.png", method: 0, compressed: wrong, uncompressedSize: wrong.count)
        ])

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try Self.extract(archive, into: directory)) { error in
            XCTAssertEqual(error as? Coran1441Install.Failure, .invalidImage("001-01.png"))
        }
    }

    /// L'extraction écrit les images **et rien d'autre** : ni le ZIP, ni un
    /// fichier de travail, dans le dossier d'installation.
    func testTheInstallationWritesOnlyTheImages() throws {
        let image = Self.pageImage()
        var files: [ArchiveEntry] = []
        for line in 1...15 {
            files.append(
                ArchiveEntry(
                    name: String(format: "width_1440/1/%02d.png", line),
                    method: 8,
                    compressed: Self.deflate(image),
                    uncompressedSize: image.count
                )
            )
        }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let installed = try Self.extract(Self.makeArchive(files), into: directory)
        XCTAssertEqual(installed, 15)

        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(written.count, 15, "Le dossier ne doit contenir que les quinze images.")
        XCTAssertTrue(written.allSatisfy { $0.hasSuffix(".png") })
    }

    // MARK: Marqueur

    func testTheMarkerDecidesWhetherTheInstallationIsReady() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let markerURL = directory.appendingPathComponent(Coran1441Install.markerName)

        XCTAssertFalse(Coran1441Install.isReady(in: directory), "Sans marqueur, rien n'est installé.")

        // Mauvais nombre de fichiers : le dossier a été amputé après coup.
        try Data(#"{"version":1,"files":9000,"installedAt":"2026-10-04T00:00:00Z"}"#.utf8).write(to: markerURL)
        XCTAssertFalse(Coran1441Install.isReady(in: directory))

        // Mauvaise version : marqueur d'une autre époque, à ne pas comprendre.
        try Data(#"{"version":2,"files":9060,"installedAt":"2026-10-04T00:00:00Z"}"#.utf8).write(to: markerURL)
        XCTAssertFalse(Coran1441Install.isReady(in: directory))

        // Marqueur illisible.
        try Data("pas du json".utf8).write(to: markerURL)
        XCTAssertFalse(Coran1441Install.isReady(in: directory))

        // Le bon marqueur.
        let marker = Coran1441Install.Ready(version: 1, files: 9_060, installedAt: "2026-10-04T00:00:00Z")
        try JSONEncoder().encode(marker).write(to: markerURL)

        XCTAssertTrue(Coran1441Install.isReady(in: directory))
        XCTAssertEqual(Coran1441Install.ready(in: directory)?.files, 9_060)
    }

    /// Le marqueur écrit par l'application doit être relisible par elle, et
    /// porter les trois champs de l'original.
    func testTheMarkerCarriesTheThreeFieldsOfTheOriginal() throws {
        let marker = Coran1441Install.Ready(version: 1, files: 9_060, installedAt: "2026-10-04T12:00:00Z")
        let data = try JSONEncoder().encode(marker)

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["version", "files", "installedAt"])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["files"] as? Int, 9_060)
    }
}

// MARK: - Outils de construction

/// Une entrée d'archive, telle que la construit un test.
struct ArchiveEntry {
    var name: String
    var method: UInt16
    var compressed: Data
    var uncompressedSize: Int
}

extension Coran1441DownloadTests {

    /// Un PNG dont l'en-tête est réel — signature, `IHDR`, dimensions — suivi
    /// d'octets quelconques.
    ///
    /// Les données de pixels ne sont pas un vrai flux d'image : le contrôle
    /// porte sur l'en-tête, comme dans l'original (`quranDownload.ts:93`), et
    /// fabriquer un mégaoctet de pixels n'apprendrait rien de plus.
    static func pageImage(width: UInt32 = 1_440, height: UInt32 = 232, padding: Int = 64) -> Data {
        func bigEndian(_ value: UInt32) -> [UInt8] {
            [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            ]
        }

        var data = Data(Coran1441Install.pngSignature)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])   // longueur du bloc IHDR
        data.append(contentsOf: Array("IHDR".utf8))
        data.append(contentsOf: bigEndian(width))
        data.append(contentsOf: bigEndian(height))
        data.append(contentsOf: [8, 2, 0, 0, 0])             // profondeur, type, etc.
        data.append(Data(repeating: 0x7A, count: padding))
        return data
    }

    /// Compresse en DEFLATE. Sert à construire des entrées de méthode 8 ; la
    /// question de savoir si c'est bien du DEFLATE **brut** est tranchée par
    /// `testARawDeflateStreamIsDecoded`, pas ici.
    static func deflate(_ data: Data) -> Data {
        let capacity = max(data.count + 1_024, 4_096)
        var destination = Data(count: capacity)
        let written = destination.withUnsafeMutableBytes { output -> Int in
            guard let outputBase = output.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { input -> Int in
                guard let inputBase = input.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(
                    outputBase,
                    capacity,
                    inputBase,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        return written > 0 ? Data(destination.prefix(written)) : Data()
    }

    /// Construit une archive ZIP complète, en mémoire.
    ///
    /// Les champs non lus par le lecteur — dates, CRC, attributs — sont écrits à
    /// zéro : ils existent pour que les décalages soient justes, pas pour être
    /// vérifiés.
    static func makeArchive(_ entries: [ArchiveEntry], comment: Data = Data()) -> Data {
        var body = Data()
        var central = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            let localOffset = body.count

            body.appendLittleEndian(UInt32(0x0403_4B50))          // signature locale
            body.appendLittleEndian(UInt16(20))                   // version nécessaire
            body.appendLittleEndian(UInt16(0))                    // drapeaux
            body.appendLittleEndian(entry.method)
            body.appendLittleEndian(UInt16(0))                    // heure
            body.appendLittleEndian(UInt16(0))                    // date
            body.appendLittleEndian(UInt32(0))                    // CRC
            body.appendLittleEndian(UInt32(entry.compressed.count))
            body.appendLittleEndian(UInt32(entry.uncompressedSize))
            body.appendLittleEndian(UInt16(name.count))
            body.appendLittleEndian(UInt16(0))                    // extension
            body.append(name)
            body.append(entry.compressed)

            central.appendLittleEndian(UInt32(0x0201_4B50))       // signature du répertoire
            central.appendLittleEndian(UInt16(20))                // version d'écriture
            central.appendLittleEndian(UInt16(20))                // version nécessaire
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(entry.method)
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt16(0))
            central.appendLittleEndian(UInt32(0))
            central.appendLittleEndian(UInt32(entry.compressed.count))
            central.appendLittleEndian(UInt32(entry.uncompressedSize))
            central.appendLittleEndian(UInt16(name.count))
            central.appendLittleEndian(UInt16(0))                 // extension
            central.appendLittleEndian(UInt16(0))                 // commentaire
            central.appendLittleEndian(UInt16(0))                 // disque
            central.appendLittleEndian(UInt16(0))                 // attributs internes
            central.appendLittleEndian(UInt32(0))                 // attributs externes
            central.appendLittleEndian(UInt32(localOffset))
            central.append(name)
        }

        let centralOffset = body.count
        body.append(central)

        body.appendLittleEndian(UInt32(0x0605_4B50))              // fin du répertoire
        body.appendLittleEndian(UInt16(0))                        // numéro de disque
        body.appendLittleEndian(UInt16(0))                        // disque du répertoire
        body.appendLittleEndian(UInt16(entries.count))            // entrées sur ce disque
        body.appendLittleEndian(UInt16(entries.count))            // entrées au total
        body.appendLittleEndian(UInt32(central.count))
        body.appendLittleEndian(UInt32(centralOffset))
        body.appendLittleEndian(UInt16(comment.count))
        body.append(comment)
        return body
    }

    /// Lit les entrées d'une archive tenue en mémoire.
    static func read(_ archive: Data) throws -> [Coran1441Archive.Entry] {
        let tailLength = min(Coran1441Archive.tailLength, archive.count)
        let tail = archive.subdata(in: (archive.count - tailLength)..<archive.count)
        let central = try Coran1441Archive.centralDirectory(fileSize: archive.count, tail: tail)
        let directoryData = archive.subdata(in: central.offset..<(central.offset + central.size))
        return try Coran1441Archive.entries(centralDirectory: directoryData, count: central.count)
    }

    /// Une closure de lecture sur une archive en mémoire.
    static func reader(_ archive: Data) -> Coran1441Archive.Reader {
        { offset, length in
            guard offset >= 0, length >= 0, offset + length <= archive.count else { return Data() }
            return archive.subdata(in: offset..<(offset + length))
        }
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coran1441-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Écrit l'archive sur le disque et la fait extraire par le code de
    /// production — celui-là même que la CI exercera sur l'archive réelle.
    ///
    /// L'archive d'essai est écrite **hors** du dossier d'extraction : dans le
    /// dossier, elle serait comptée comme un fichier installé, et le test qui
    /// vérifie que seules les images sont écrites échouerait — pour une raison
    /// qui n'a rien à voir avec le code testé.
    static func extract(_ archive: Data, into directory: URL) throws -> Int {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coran1441-fixture-\(UUID().uuidString).zip")
        try archive.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        return try Coran1441DownloadService.extractEntries(
            from: url,
            into: directory,
            total: Coran1441Install.requiredFileCount,
            progress: { _ in }
        )
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

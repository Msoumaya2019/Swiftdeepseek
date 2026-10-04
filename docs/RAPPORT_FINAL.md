# Rapport final — première mission

Date : 4 octobre 2026.

---

## 1. Dépôt

| | |
| --- | --- |
| URL | `https://github.com/Msoumaya2019/Swiftdeepseek` |
| Nom | **`Swiftdeepseek`** — exactement, sans variante |
| Visibilité | **publique** (nécessaire : les exécuteurs macOS sont facturés sur un dépôt privé) |
| Branche par défaut | `main` |
| Taille | 116 693 Ko |
| Commits | 10 |
| Dépôt indépendant | oui — ni fourche, ni branche, ni sous-dossier, ni sous-module du dépôt de référence |

## 2. Dépôt de référence — intact, et aucun commit

`Msoumaya2019/coran-memoire`, clone local en lecture seule.

| Contrôle | Mesure |
| --- | --- |
| `HEAD` | `f538ae37565abf70032e7e215fe57c8b96c2152f` — inchangé |
| Branches | `main`, une seule |
| Dépôts distants configurés | **0** — une poussée y est donc *impossible* |
| Fichiers modifiés | **0** |
| Commits présents dans le clone | **1** — le sommet du clone |
| Entrées de `reflog` | **1** — `clone: from https://github.com/Msoumaya2019/coran-memoire.git` |
| Refs | `refs/heads/main` uniquement |

Le `reflog` est la preuve la plus forte disponible : il enregistre **toute**
opération qui déplace une ref. Une seule entrée, et c'est le clone. **Aucun
commit, aucune branche, aucune poussée, aucune modification de fichier, aucune
migration Supabase** n'a eu lieu dans le dépôt de référence.

Aucun changement Supabase n'a été appliqué : ni table, ni colonne, ni politique
RLS, ni fonction. Aucune donnée n'a été écrite dans le projet.

## 3. Garde-fou Git

```
SOURCE_REPOSITORY = Msoumaya2019/coran-memoire
SOURCE_MODE       = READ_ONLY
TARGET_REPOSITORY = Msoumaya2019/Swiftdeepseek
TARGET_MODE       = READ_WRITE
```

`make guard` lit `git remote get-url origin` et refuse de continuer si la
destination n'est pas exactement `Msoumaya2019/Swiftdeepseek`. Éprouvé sur quatre
configurations : cible (0), dépôt de référence (1), inconnue (1), aucune (1).

La destination a été revérifiée **avant chaque poussée** de cette session.

## 4. Structure Swift créée

Architecture MVVM, 39 fichiers Swift, 677 fichiers suivis.

```
App/            SwiftdeepseekApp, ContentView
Core/           AppState, OfflineMerge, JSONValue, DateKeys, Program, Review,
                Quran, WeeklyProgress, Bookmark, AppConfig
Features/       Home, Quran (QuranScreenView + Reader/), Program, Progress,
                Review, Friends, Navigation, Shared
Models/         ViewModels/
Networking/     SupabaseRESTClient
Repositories/   AppStateRepository
Services/       Auth, StateSync, Social, QuranSource, Connectivity, Audio
Storage/        LocalStore, KeychainStore
Theme/          Tests/        Resources/ (Data, Mushaf, Fonts)
Config/         Base/Debug/Release.xcconfig, Secrets.xcconfig.example
.github/workflows/ios.yml      Makefile      project.yml      scripts/
```

Navigation conservée : **Accueil, Coran, Programme, Progrès, Amis**.

## 5. Connexion Supabase

Même projet que l'application React Native (`npbwnvrqmajwqtnncuyv`), donc **mêmes
comptes, mêmes `user_id`, mêmes données**. Ni projet nouveau, ni Auth nouvelle,
ni utilisateur dupliqué.

- Seule la clé **publiable** est utilisée. La clé `service_role` n'apparaît nulle
  part : vérifié par recherche dans le dépôt et dans l'historique Git.
- Aucun secret n'est committé : les valeurs arrivent par `Config/Secrets.xcconfig`,
  ignoré par Git, et sont injectées dans `Info.plist` à la compilation.
- Sans configuration, l'application **ne plante pas** : elle affiche un écran qui
  nomme ce qui manque.
- Délai de requête aligné sur celui de l'application d'origine (`sync.ts:10` — 8000 ms).

## 6. Comportement de l'authentification

`Services/AuthService.swift` — `ObservableObject` sur le fil principal, état
`checking` / `signedOut` / `signedIn`.

Mêmes points d'entrée que l'application d'origine : connexion, inscription,
déconnexion, réinitialisation du mot de passe, renvoi de confirmation, changement
de mot de passe, traitement du lien d'authentification, restauration de session
au lancement, et rafraîchissement du jeton d'accès.

- Session conservée dans le **trousseau**, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Schéma d'URL propre : `swiftdeepseek://auth` — **différent** de celui de
  l'application d'origine (`coranmemoire://`), pour qu'elles ne se disputent pas
  le même schéma au niveau du système.
- Identifiant de paquet propre : `fr.swiftdeepseek.app`. Celui de l'application
  d'origine (`fr.coranmemoire.app`) n'est pas touché.

## 7. Test avec un utilisateur existant — **non effectué**

À dire clairement : **aucune connexion de bout en bout avec un compte réel n'a
été exécutée.** Aucun appareil ni émulateur n'était disponible, et aucun
identifiant ne peut figurer dans le dépôt ni dans les secrets de l'intégration
continue.

Ce qui est établi, et ce qui ne l'est pas :

| | |
| --- | --- |
| Établi | le code d'authentification compile et passe les tests unitaires |
| Établi | le projet Xcode se génère, la compilation et l'archivage réussissent |
| Établi | la fusion hors ligne est couverte par des tests unitaires (trois à quatre voies, tombstones, union) |
| **Non établi** | qu'un compte existant se connecte réellement et retrouve ses données sur l'appareil |

C'est **la première vérification à faire** dès qu'un appareil est disponible
(voir §11).

## 8. Données récupérées

Le contrat de compatibilité est **`public.user_state`** : un document JSONB
unique par utilisateur, protégé par quatre politiques RLS. Aucune modification de
schéma n'a été nécessaire — le document est lu et réécrit tel quel.

Le client Swift fait transiter le JSON **sans le déformer** (`JSONValue`, qui
préserve les types et l'ordre), et ne touche que les clés qu'il connaît. C'est ce
qui rend la compatibilité bidirectionnelle possible : une action faite dans
l'application React Native apparaît dans l'application Swift, et réciproquement.

Fusion hors ligne à trois voies (`base` / `local` / `remote`), avec :

- fusion des tableaux par identifiant, et **tombstones** (une suppression ne
  ressuscite pas) ;
- maximum monotone sur `.through` ;
- priorité à `status: done` ;
- union pour `validations`, `History`, `readPages`, `completed` ;
- progression d'étude indexée par `"<mode>:<id>"` → `learning:<id>` / `revision:<id>`.

## 9. Données éventuellement locales uniquement

`LOCAL_DATA_MIGRATION.md` (175 lignes) établit une conclusion qu'il faut connaître
avant d'installer l'application :

> **Aucune donnée locale de l'application React Native n'est récupérable par
> l'application Swift.**

Les deux applications ont des identifiants de paquet différents : iOS leur donne
des **bacs à sable séparés**. La base SQLite, le trousseau et les fichiers de
l'une sont invisibles pour l'autre — et le resteront. La migration ne peut donc
pas être automatique.

Ce qui vit **uniquement** en local : la file d'attente hors ligne
(`pending_sync`), la base SQLite locale, le trousseau, les réglages
`AsyncStorage`, les fichiers.

**Le seul point vraiment sensible est la file d'attente hors ligne.** Si elle
n'est pas vidée, la personne qui ouvre l'application Swift voit l'état du
serveur, donc **sans** ces modifications. Les changements ne sont pas détruits
(ils restent sur l'appareil), mais ils ne sont pas visibles côté Swift.

**Marche à suivre, sans toucher au dépôt de référence** — c'est une consigne
d'usage, pas une modification de code : **faire ouvrir l'application React Native
avec du réseau et la laisser synchroniser avant d'installer l'application Swift.**

## 10. État du lecteur Coran

Lecteur plein écran du Moushaf, `Features/Quran/Reader/`.

- **`UIPageViewController`** encapsulé dans un `UIViewControllerRepresentable` :
  geste de balayage natif, transition « page », et maintien en mémoire des
  **seules pages voisines** (`preloadNeighbours`, page −1 / page / page +1).
  Rien d'autre n'est préchargé.
- **Centrage vertical sans marge haute fixe.** La zone de page prend **tout
  l'espace restant** après la barre de titre (hauteur mesurée, jamais fixée en
  dur), le mini-lecteur et la barre d'actions ; la page est centrée **dans** cette
  zone par contraintes (`centerYAnchor`). Elle s'adapte donc seule à l'encoche, à
  l'île dynamique et à la barre d'accueil. **Aucune marge haute fixe, nulle part.**
- **Ratio des pages jamais modifié** (`scaleAspectFit`).
- Cinq éditions déclarées : Coran de Médine, Coran 1441, Lecture simplifiée,
  Moushaf Tajwid, Coran avec règles de Tajwid. **Seul le Coran de Médine est
  embarqué** (604 pages). Le téléchargement du Coran 1441 **n'est pas implémenté**
  — voir §11.
- Audio : `AVFoundation`, récitateurs et correspondance d'audio repris de
  l'application d'origine.

## 11. Fichiers et ressources copiés

| Ressource | Contenu | Vérification |
| --- | --- | --- |
| `Resources/Mushaf/` | **604 pages** du Coran de Médine | **MD5 identiques** aux 604 fichiers source, un à un |
| `Resources/Data/` | **14 fichiers** (`verses.json`, `pages.json`, `bounds.json`, `meta.json`, `ipa-audio-source.json`, `tajweed-*.json`, `coran_1441-*.json`, `translation-fr-rashid.json`, `TANZIL-LICENSE.txt`) | tracés jusqu'à leur source par MD5 |
| `TANZIL-LICENSE.txt` | attribution du fournisseur des pages | fichier rédigé, sans jumeau côté source |

Fidélité binaire revérifiée : `git hash-object` du fichier de travail égale
`git rev-parse :chemin` pour les pages 1, 302 et 604 et pour `verses.json`.

**Non copié, volontairement** — omissions documentées dans `SWIFT_MIGRATION.md` :
`mushaf-tajweed` (134 Mo), `tajweed` (124 Mo), `coran-test` (51 Mo), `themes`,
`illustrations`. Raisons : ressources non nécessaires à la première mission, ou
licences incertaines. Vérifié : **aucun code Swift ne référence** `medallion.png`,
`themes` ni `fonts`. `Resources/Fonts/` est donc vide.

## 12. Intégration continue — trois runs verts

| Run | Commit | Conclusion | Durée |
| --- | --- | --- | --- |
| #8 | `cc7f747` | **success** | 7 min 26 s |
| #9 | `79def4b` | **success** | 6 min 46 s |
| #10 | `c4f5609` | **success** | 5 min 12 s |

Run #10 : **les 13 étapes en `success`** — garde-fou de dépôt, contrôle des flux,
Xcode, XcodeGen, génération du projet, **compilation**, **tests**, **archive non
signée**, **empaquetage de l'IPA**, **publication des artefacts** — et **1
artefact de 120 242 376 octets**. La taille est le second témoin : elle prouve que
les 604 pages sont réellement dans le paquet, et pas seulement que le fichier a
été créé.

L'IPA est **non signé** : il s'installe par sideloading, pas par l'App Store.

## 13. Problèmes rencontrés

1. **Aucun compilateur Swift sur la machine de rédaction.** Tout le code Swift a
   été écrit sans pouvoir le compiler. Les erreurs ont été découvertes par
   l'intégration continue, en quatre vagues — 3, 6, 3 erreurs, puis les tests.
2. **Le journal de CI exige une session (HTTP 403).** Sans jeton, seul
   « exit code 65 » était lisible. Le flux a donc été rendu
   **auto-diagnostiquant** : il réémet les erreurs du compilateur et des tests en
   annotations publiques. Le défaut a été de devoir découvrir que le shell par
   défaut d'un `run:` est `bash -e`, ce qui faisait que le bloc de capture ne
   s'exécutait **jamais**.
3. **Deux vocabulaires de notes dans l'application d'origine** — piège réel :
   tâches de révision `perfect | hesitant | rework` (`program.ts:23`) ; révisions
   de versets `perfect | hesitant | errors | relearn` (`program.ts:11`). Côté
   Swift, les valeurs traversent le document en `String`, donc sans perte ; seule
   la signature d'entrée était fausse.
4. **Contradiction entre la documentation et le code du dépôt de référence**
   (documentée dans `SWIFT_MIGRATION.md` §9.2, non corrigée : le dépôt de
   référence est en lecture seule).
5. **Trois tests qui affirmaient la mauvaise forme.** Les tests passaient l'objet
   *parent* tout en nommant l'enfant dans `path` ; la fusion rendait donc `nil`.
   Le défaut était dans les **tests**, pas dans l'implémentation.
6. **Actions épinglées à des versions dépréciées.** `checkout@v4` et
   `upload-artifact@v4` visent Node 20. Piège mesuré : monter `upload-artifact` de
   v4 à **v5 ne corrige rien**, v5 déclare encore `node20`. Cibles retenues, les
   plus petites qui déclarent `node24` : `checkout@v5`, `upload-artifact@v6`.
7. **`GET /actions/jobs/{id}` renvoie `annotations: []` même sur un job en échec**
   qui en porte treize dans le HTML. Le HTML est la source pour la cause ; l'API,
   pour le détail des étapes.

## 14. Étapes suivantes

**En premier, dès qu'un appareil est disponible :**

1. **Éprouver la connexion avec un compte existant** (§7) — c'est la seule
   vérification de la mission qui reste entièrement à faire.
2. **Vérifier la compatibilité bidirectionnelle** : une action dans l'une des
   applications doit apparaître dans l'autre.

**Puis, par ordre d'importance fonctionnelle** (détaillé dans `SWIFT_MIGRATION.md` §9) :

3. Brancher la **notation des révisions** dans l'interface (§9.6).
4. **Affichage rouge des versets difficiles** (§9.7).
5. **Téléchargement du Coran 1441** (§9.4) — non implémenté ; seule l'édition de
   Médine est embarquée.
6. Consommer `ReaderRequest.reviewTask` et `.consolidation` dans le lecteur.
7. « Tawjeed test 2 » et « Medine Test » (§9.3).
8. Assistant d'objectif hebdomadaire, écran d'apparence, messagerie, groupes,
   quiz, notifications, récitations, mini-lecteur.

**Côté Apple** (README §« Ce qu'il reste à faire côté Apple ») : compte de
développeur, identifiant de paquet enregistré, profil de provisionnement et
certificat, pour passer de l'IPA non signé à une installation normale.

---

## Règle non négociable, pour mémoire

> Le dépôt de référence est en **LECTURE SEULE**. Le seul dépôt modifiable est
> **`Swiftdeepseek`**. En cas de doute : **s'arrêter et demander.**

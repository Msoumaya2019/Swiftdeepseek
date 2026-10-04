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
| Taille | 116 710 Ko (mesurée par l'API GitHub) |
| Commits | 20 au commit `aa90394`, dernier run vert de code (#20). Ancré sur ce commit : un compteur de commits ne peut pas se citer lui-même, puisque le commit qui porte ce rapport en ajoute un. |
| Fichiers suivis | 682 — dont **43 fichiers Swift** et **110 tests** déclarés |
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

Architecture MVVM, **43 fichiers Swift**, 682 fichiers suivis.

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

### Ce qui a été mesuré sur le projet réel

Quatre appels passés sur `npbwnvrqmajwqtnncuyv` avec la clé publiable. Ils ne
modifient rien. Détail et conséquences : `SUPABASE_COMPATIBILITY.md` §1.5.

| Appel | Code | Conclusion |
| --- | --- | --- |
| `GET /auth/v1/health` | 200 | projet joignable |
| `GET /auth/v1/settings` | 200 | **clé acceptée** ; fournisseur `email` actif, confirmation d'adresse exigée |
| `POST /auth/v1/token` (identifiants volontairement faux) | 400 `invalid_credentials` | **la clé n'est pas en cause** — une clé invalide donnerait `invalid_api_key` |
| `GET /rest/v1/user_state` | 401 `42501` | le rôle `anon` n'a **aucun privilège** sur la table |

Le quatrième point est le plus utile pour la suite : `anon` est refusé **avant**
RLS, au niveau du privilège. L'application doit donc être **authentifiée avant de
lire**, comme l'application React Native — il n'y a pas de « mode invité » à
prévoir, et il ne faut pas en ajouter un.

**Piège à connaître** : `GET /rest/v1/` répond `401 « Secret API key required »`
avec une clé publiable, **par conception** — Supabase réserve la racine PostgREST
aux clés secrètes. Tester la validité d'une clé publiable sur cette adresse mène à
une conclusion fausse.

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
- **Limite connue, à trancher par le propriétaire du projet.** L'état initial
  repris de l'original donne `reader.mushaf = "coranTest"` (`Program.swift:94`,
  d'après `program.ts`), et cette édition — « Coran avec règles de Tajwid » — n'a
  **ni images ni rectangles** côté Swift (ressources non copiées, 51 Mo). Un
  utilisateur qui arrive de l'application React Native avec cette préférence, ou
  avec `tajweedPages`, voit donc le message « pas encore disponible » au lieu d'un
  Moushaf. Le faire retomber **silencieusement** sur le Coran de Médine n'a pas
  été fait, et c'est délibéré : `ReaderView` enregistre les marque-pages avec
  `source: edition.rawValue`, donc un repli silencieux écrirait des marque-pages
  marqués `traditional` pour un utilisateur dont la préférence est `coranTest` —
  une divergence de données avec l'application React Native. Deux options
  propres : soit **copier** les ressources de ces éditions, soit **afficher un
  choix** plutôt que de décider à la place de l'utilisateur.
- **Deux formes de page, et c'est la différence qui compte.** Le Coran de Médine
  est **une** image par page (`1920 × 3106`) ; le Coran 1441 est **quinze bandes
  par page** (`1440 × 232` chacune), empilées à pas constant
  (`MushafPage.tsx:48`). Les deux formes sont rendues par le même
  `MushafPageViewController`, et leurs quinze `UIImageView` sont positionnées par
  `VerseBounds.bandRect` — la **même** fonction qui projette les mises en
  évidence. Dans l'original, les bandes sont placées dans l'espace de la vue et
  les mises en évidence dans l'espace de l'image : les deux ne coïncident que si
  la vue a exactement le ratio de la page. Ici, elles coïncident toujours, et un
  test le fixe.
- Audio : `AVFoundation`, récitateurs et correspondance d'audio repris de
  l'application d'origine.
- **Mise en évidence des versets** : `Core/VerseBounds.swift` lit
  `Resources/Data/bounds.json` (604 pages, **13 766** rectangles) et
  `coran_1441-bounds.json` (604 pages, **13 273** rectangles) — deux fichiers
  jusqu'ici **lus par aucun code** — et `VerseHighlightView` les dessine
  par-dessus la page. Sont repris de `MushafPage.tsx:51-52` le rouge `#E85B5B` à
  0,18 pour un verset difficile, le vert du signet à 0,18, la surbrillance de
  lecture à 0,42, les coins à 4 et l'icône de signet sur le bord droit.
  La **taille de la page** est celle de la source, lue page par page pour le
  Coran 1441 : se tromper de taille ne lève aucune erreur, cela déplace toutes
  les mises en évidence — un test chiffre ce décalage (plus de 150 pt).
- **Ce qui n'est pas repris** : les repères de progression de séance dans la marge
  (`marginAnnotations`, `MushafPage.tsx:53`), qui dépendent du suivi de séance
  (`sessionThrough`), non porté ; le bouton « Ma voix », l'enregistrement des
  récitations n'étant pas implémenté ; et les libellés d'accessibilité par verset
  mis en évidence, une page étant un élément d'accessibilité unique.
- **Barre d'action selon la raison d'ouverture** : trois notes de révision
  (Parfait / Quelques hésitations / À retravailler) puis « Écouter » pour une
  tâche de révision ; « Valider la consolidation · J+n » pour une consolidation ;
  « Valider » pour une séance d'apprentissage.

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

## 12. Intégration continue

| Run | Commit | Conclusion | Durée |
| --- | --- | --- | --- |
| #8 | `cc7f747` | **success** | 7 min 26 s |
| #9 | `79def4b` | **success** | 6 min 46 s |
| #10 | `c4f5609` | **success** | 5 min 12 s |
| **#11** | `6e795cc` | **échec** — simulateur nommé en dur | — |
| #12 | `76fad6e` | **success** | 6 min 14 s |
| #13 | `36cfa8a` | **success** | — |
| **#14** | `d152c06` | **échec** — `Set<CGRect>` (voir ci-dessous) | — |
| **#15** | `6102105` | **échec** — assertion de test inversée | — |
| **#16** | `c0bf461` | **échec** — égalité exacte sur un flottant | — |
| **#17** | `3e63067` | **success** | 4 min 49 s |
| **#18** | `a89cf04` | **success** — documentation seule | — |
| **#19** | `a23ba05` | **échec** — une assertion de test trop forte | — |
| **#20** | `aa90394` | **success** | — |
| **#21** | `0e4a19f` | **success** — documentation seule | 4 min 56 s |
| **#22** | `ededb3b` | **success** — documentation seule | 5 min 34 s |
| **#23** | `17ea205` | **annulé** — remplacé par #24 (`cancel-in-progress`) | 5 min 59 s |
| **#24** | `17ea205` | **success** — mais la configuration restait vide (voir ci-dessous) | 4 min 26 s |
| **#25** | `593b8b1` | **success** — ordre des `#include?` corrigé | 7 min 57 s |

Le tableau ne s'étend pas pour un run dont la seule cause est une modification de
ce rapport : il s'étend quand un run **porte un fait**. Les runs #22 à #25 en
portent deux — un défaut réel, et son correctif.

Run #17 : **les 13 étapes en `success`** — garde-fou de dépôt, contrôle des flux,
Xcode, XcodeGen, génération du projet, **compilation**, **tests**, **archive non
signée**, **empaquetage de l'IPA**, **publication des artefacts** — et **1
artefact de 120 263 470 octets**. La taille est le second témoin : elle prouve que
les 604 pages sont réellement dans le paquet, et pas seulement que le fichier a
été créé.

Les **110 tests** de la cible de tests sont joués à chaque run. Deux d'entre eux
(`AppWiringTests`) sont **ignorés** tant que les secrets `SUPABASE_URL` et
`SUPABASE_ANON_KEY` ne sont pas posés sur le dépôt : ils vérifient la
configuration, qui est alors absente. Ils s'activeront d'eux-mêmes.

L'IPA est **non signé** : il s'installe par sideloading, pas par l'App Store.

### L'échec #11, et ce qu'il a appris

Le run #11 a échoué en **code 70**, sur l'étape des tests, avec pour seule cause
lisible :

```
xcodebuild: error: Unable to find a device matching the provided destination
specifier:
```

Ce qui rend cet échec instructif : **le même fichier, à trois runs verts près,
passait**. La destination était `name=iPhone 16`. C'est donc le *contenu de
l'image de l'exécuteur* qui avait changé, pas le code — et nommer un appareil
n'est pas stable d'une image à l'autre.

Deux corrections en ont découlé :

1. **Le simulateur est désormais résolu à l'exécution** — `xcrun simctl list
   devices available` fournit un appareil réellement présent, désigné par son
   identifiant (`id=`), qui ne dépend pas du catalogue. Si aucun iPhone n'est
   disponible, le pas échoue en **listant les appareils vus**, au lieu d'un
   message tronqué.
2. **La réémission porte maintenant les lignes qui suivent l'erreur** (`grep -A`,
   6 lignes pour les tests, 4 pour la compilation). Sans elles, l'annotation
   s'arrêtait sur « `specifier:` » : la liste des appareils vus par `xcodebuild`
   était **sur les lignes suivantes**, et n'était donc pas publiée. Un message
   d'erreur tronqué au moment précis où il allait être utile.

Le run #12 est vert avec ce correctif.

### Les échecs #14, #15 et #16 : trois fois un test, jamais le code

Ces trois runs se suivent et échouent tous à l'étape « Jouer les tests », **après
une compilation réussie**. C'est le signal utile : le défaut est dans un test, pas
dans l'application. Les trois causes sont différentes, et les trois valent d'être
connues.

**#14 — `Set<CGRect>`.** `CGRect` ne conforme à `Hashable` qu'au-delà de la cible
iOS 16 du projet. Le compilateur réclamait un contrôle `if #available`. Les
annotations ne montraient que des lignes `note:`, jamais la ligne `error:` — mais
la note suffisait : « `add 'if #available' version check` » ne s'affiche que pour
un symbole plus récent que la cible de déploiement. Corrigé en comparant des
tableaux, ce qui est en prime une assertion plus forte (elle tient l'ordre).

**#15 — une assertion inversée.** Le test comparait `other` au récitateur **après**
l'avoir affecté : les deux étaient égaux par construction, et le test échouait
toujours. Le journal le dit sans ambiguïté, les deux valeurs imprimées étant
identiques.

**#16 — une égalité exacte sur un flottant.** `XCTAssertEqual` sur deux `CGRect`
refuse `979.0000000000001` contre `979.0`. Le calcul est juste : `979 / 3106 *
3106` ne redonne pas `979` en virgule flottante, et l'erreur est de 1e-13 point —
douze ordres de grandeur sous le pixel. Corrigé en comparant avec `accuracy:`.

**La cause commune est l'absence de compilateur Swift sur la machine de
rédaction** : ces tests n'avaient jamais tourné avant d'atteindre l'intégration
continue. Deux conséquences en ont été tirées :

1. **Un contrôle local a été ajouté** (`_banc/coherence-swift.mjs`, non livré) : il
   signale toute `XCTAssertEqual` sur une valeur géométrique **dérivée**
   (`.minX`, une projection) sans `accuracy:`. Il a été **falsifié** — un fichier
   portant volontairement le défaut le fait échouer, et sa suppression le remet au
   vert.
2. **La distinction à retenir** : un rectangle en coordonnées d'**image** vient
   d'entiers convertis en `CGFloat` sans division — l'égalité exacte y est
   légitime. Une valeur **projetée** se compare avec tolérance.

Run #17 est vert avec le troisième correctif, en 4 min 49 s.

### L'échec #19 : un test plus fort que l'invariant qu'il décrit

Quatrième échec de la même famille — compilation verte, tests rouges — et
quatrième fois, la cause est dans le **test**.

Ce test vérifiait que les bandes du Coran 1441 et les rectangles de ses versets
se projettent au même endroit. Il affirmait **en plus** que leurs `minX` projetés
sont **égaux**. C'est faux par construction : une bande couvre **toute la
largeur** de la ligne, un verset n'en occupe qu'une **partie**. Neuf lignes de la
page 1 ont donc échoué.

Les valeurs publiées se relisent exactement, et c'est ce qui a permis de trancher
sans deviner :

```
352,08 / 1440 × 390 = 95,355
```

`352,08` est le `x1` de la première ligne de la page 1, `1440` la largeur de sa
page, `390` la largeur de la vue du test.

Ce qui doit être **égal** : le haut et la hauteur — la ligne du verset *est* la
bande, et le fichier porte `y1 = pas × ligne` avec une hauteur de 232 pour ses
13 273 lignes, sans exception. Ce qui doit être **contenu** : l'étendue
horizontale. L'assertion est désormais de cette forme, et le balayage porte sur
quatre pages (58 lignes) au lieu d'une.

**La leçon dépasse le correctif.** Une assertion plus forte que l'invariant
qu'elle décrit n'est pas de la rigueur : c'est un défaut, et il échoue sur du code
juste. Les échecs #14, #15 et #16 venaient d'assertions mal **écrites** ;
celui-ci vient d'une assertion mal **conçue**.

Run #20 est vert avec ce correctif.

### Lire le verdict quand le quota d'API est épuisé

Le run #20 a été jugé **sans l'API**. La sonde qui interrogeait
`/actions/runs?head_sha=…` toutes les 20 secondes a épuisé les **60 requêtes par
heure** en dix-huit minutes — et le refus ne ressemble pas à un refus :
`workflow_runs` est simplement absent du corps, si bien que la sonde a conclu
« aucun run pour ce commit » alors que le run tournait.

Le repli est la **page HTML du run**, publique et sans quota :

```bash
curl -s -o run.html "https://github.com/Msoumaya2019/Swiftdeepseek/actions/runs/<id>"
grep -o '<annotation-message' run.html | wc -l   # 2 sur un run vert, 12 sur un échec
grep -c 'In progress' run.html                   # 1 = pas encore terminé
```

Deux précautions, toutes deux mesurées :

- **`0` annotation ne veut pas dire « vert »**, cela peut vouloir dire « en
  cours ». Il faut contrôler les deux : le nombre d'annotations **et** l'absence
  de `In progress`.
- **Le nombre d'annotations n'est pas le nombre d'échecs.** Dix lignes de test
  échouaient ; **neuf** annotations ont été publiées. La dixième — la dernière —
  n'est jamais apparue. Ce qui manque est toujours la fin de la liste.

Le run #20 porte exactement les **deux** annotations d'un run vert : clés
Supabase absentes (la compilation continue) et mise en file des exécuteurs macOS
arm64.

### Le défaut #24 : la configuration n'atteignait pas le binaire

Le run #24 a été déclenché **après** la pose des deux secrets de dépôt, et il est
vert. Il portait pourtant un défaut, invisible au verdict.

**Ce qui a été mesuré.** L'étape « Écrire Config/Secrets.xcconfig » a bien écrit
**137 octets** — les deux vraies valeurs. Et pourtant, dans l'IPA produite,
`Payload/Swiftdeepseek.app/Info.plist` portait :

```
SUPABASE_URL      = ''
SUPABASE_ANON_KEY = ''
```

Les clés étaient là, substituées, mais **vides**.

**La cause.** Dans `Config/Base.xcconfig`, le `#include? "Secrets.xcconfig"` était
écrit **avant** les deux valeurs de repli vides. Dans un xcconfig, la **dernière
affectation gagne** : les replis écrasaient les vraies valeurs.

**Pourquoi personne ne le voyait.** Les deux tests qui vérifient que la
configuration arrive dans l'application se **sautent** quand elle paraît absente
(`XCTSkipUnless(AppConfig.isConfigured)`). Le défaut rendait la configuration
absente — donc les tests se sautaient, et le run restait vert. **Le défaut
éteignait ses propres garde-fous.** Le journal, lui, ne disait rien : il annonçait
« 110 tests, 3 ignorés », ce qui est un état supporté et documenté.

**Comment il a été trouvé.** En lisant l'artefact plutôt que le verdict. Le journal
du run est **tronqué** (`tail -60`) : les 43 lignes « Test Case » visibles sur 110
ne montraient pas *quels* tests étaient ignorés. L'artefact, lui, contient
`build-tests.log` **complet** — et l'`Info.plist` de l'application construite.
C'est la seule mesure qui a parlé.

**Le correctif, et sa preuve.** Les replis passent **avant** l'include (#25). Le
même contrôle sur l'IPA donne alors :

```
SUPABASE_URL      = 'https://npbwnvrqmajwqtnncuyv.supabase.co'
SUPABASE_ANON_KEY = 'sb_publishable_…'
```

Et le témoin indépendant : les tests ignorés passent de **3 à 1** — les deux tests
`AppWiringTests` s'exécutent désormais, seul reste celui de la traversée du
changement d'heure, sans rapport avec Supabase.

**La garde.** Un pas de CI refuse désormais le cas « secret posé mais variable de
compilation vide » : il lit la variable résolue par `xcodebuild -showBuildSettings`
et échoue si elle est vide. Sans lui, la même panne pourrait se reproduire et se
taire encore.

**Un effet de bord à connaître.** Le flux porte `cancel-in-progress: true` sur le
groupe `ios-main` : déclencher un run à la main **annule** le run du push en cours.
C'est ce qui est arrivé au #23, qui n'est donc pas un échec mais une annulation.

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
8. **Un run vert ne garantit pas que le suivant le sera.** Le run #11 a échoué sur
   une destination de simulateur **nommée**, alors que les trois runs précédents
   passaient avec le même fichier : l'image de l'exécuteur avait changé. Corrigé
   en résolvant l'appareil à l'exécution (§12). Leçon générale : ce qui dépend du
   **contenu de l'image d'exécuteur** — nom d'appareil, version d'outil, catalogue
   de simulateurs — doit être résolu au moment de l'exécution, jamais écrit en dur.
9. **Une colonne lue pour ce qu'elle n'était pas.** La troisième colonne de
   `bounds.json` avait été nommée `ayahEnd` — « verset de fin » — dans le premier
   jet de `VerseBounds`. Elle plafonne en réalité à **15** sur tout le fichier,
   alors qu'un numéro de verset atteindrait 286 (al-Baqarah) ; et trier les lignes
   d'une page par `y1` ne produit **aucune** inversion sur 13 162 paires. C'est un
   **numéro de ligne**, que l'original appelle d'ailleurs `line` là où il s'en
   sert. Deux pièges de plus s'y cachaient : la convention change de base selon la
   source (Médine `1 … 15`, Coran 1441 `0 … 14`), et le fichier du 1441 porte des
   coordonnées **décimales** — décodé en `Int`, il échouerait **en entier**, et
   toutes les mises en évidence du Coran 1441 disparaîtraient sans autre symptôme.
   Leçon : **un nom de champ recopié n'est pas une mesure**. Le renommage s'est
   fait sur trois mesures indépendantes, pas sur la lecture du nom.
10. **Un commentaire qui affirmait le contraire du code.** `VerseBounds` annonçait
    un chargement « paresseux — la source non utilisée n'est jamais lue », alors
    que la boucle sur `Source.allCases` chargeait **les deux** fichiers (1,2 Mo)
    au premier accès. Corrigé en deux `static let` distincts, dont chacun n'est
    initialisé qu'à son premier usage : le commentaire est désormais vrai par
    construction, et non par intention.
11. **Une assertion plus forte que l'invariant qu'elle décrit** — quatrième échec
    dû à un test, et le premier dû à sa *conception* plutôt qu'à son écriture.
    Détail et valeurs en §12.
12. **Un chemin de shell qui n'existe pas pour le binaire Windows.** Le sondeur
    du run #20 écrivait sa page dans `/tmp/run-<id>.html` ; le `curl` de Git Bash
    sous Windows n'a pas créé le fichier, `grep` a échoué, et le contrôle a rendu
    **`annotations=0`** — le verdict rassurant, pour la mauvaise raison. Un
    « zéro » produit par un échec de lecture est indistinguable d'un vrai zéro :
    il faut vérifier que le fichier **existe** (`ls -l`) avant de compter dedans.

## 14. Étapes suivantes

**En premier, dès qu'un appareil est disponible :**

1. **Éprouver la connexion avec un compte existant** (§7) — c'est la seule
   vérification de la mission qui reste entièrement à faire.
2. **Vérifier la compatibilité bidirectionnelle** : une action dans l'une des
   applications doit apparaître dans l'autre.
3. **Autoriser `swiftdeepseek://auth` dans Supabase** — *Authentication* → *URL
   Configuration* → *Redirect URLs*. Le projet porte `mailer_autoconfirm: false`
   (mesuré), donc la confirmation d'inscription est **obligatoire** ; sans ce
   schéma autorisé, le lien de confirmation et celui de réinitialisation ne
   reviennent pas dans l'application. Détaillé dans `SUPABASE_COMPATIBILITY.md`
   §1.1. **C'est le seul geste d'authentification qui ne se pose pas depuis le
   dépôt.**

**Puis, par ordre d'importance fonctionnelle** (détaillé dans `SWIFT_MIGRATION.md` §9) :

4. **Téléchargement du Coran 1441** (§9.4) — **le seul manque du lecteur**. Tout
   le reste est en place : les quinze bandes sont rendues, la géométrie de leurs
   rectangles est lue et testée, la mise en évidence fonctionne pour cette source.
   Il manque les **9 060 images** (archive de 102 608 011 octets). L'édition est
   proposée, et une page absente le **dit** au lieu d'afficher une page blanche.
5. « Tawjeed test 2 » et « Medine Test » (§9.3), **et la décision qui va avec**.
   Les éditions de Tajwid n'ont ni images ni rectangles : `QuranEdition.boundsSource`
   rend `nil`, ce qui produit **aucune** mise en évidence plutôt que celles du
   Coran de Médine appliquées à une autre image. Reste à choisir entre copier
   leurs ressources (51 Mo et 134 Mo) et laisser l'utilisateur choisir une édition
   disponible. Ce n'est pas un cas théorique : l'état initial vaut `coranTest`
   (voir §10).
6. **Repères de progression de séance dans la marge** (`marginAnnotations`,
   `MushafPage.tsx:53`) — dépend du suivi de séance (`sessionThrough`), non porté.
7. Assistant d'objectif hebdomadaire, écran d'apparence, messagerie, groupes,
   quiz, notifications, récitations, mini-lecteur.

*Déjà faites depuis la rédaction de la première version de ce rapport, et donc
retirées de cette liste : la notation des révisions dans l'interface (§10, barre
d'action), l'affichage rouge des versets difficiles (§10, `VerseBounds`), et la
consommation de `ReaderRequest.reviewTask` et `.consolidation` par le lecteur.*

**Côté Apple** (README §« Ce qu'il reste à faire côté Apple ») : compte de
développeur, identifiant de paquet enregistré, profil de provisionnement et
certificat, pour passer de l'IPA non signé à une installation normale.

---

## Règle non négociable, pour mémoire

> Le dépôt de référence est en **LECTURE SEULE**. Le seul dépôt modifiable est
> **`Swiftdeepseek`**. En cas de doute : **s'arrêter et demander.**

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
| Taille | 117 329 Ko (mesurée par l'API GitHub) |
| Commits | 53 au commit `085a7f4`, celui qui porte l'**écran d'apparence** (le thème et la couleur d'accent) et le `swatch` qui manquait sur `Theme.Accent`. Ancré sur ce commit : un compteur de commits ne peut pas se citer lui-même, puisque le commit qui porte ce rapport en ajoute un. |
| Fichiers suivis | 710 — dont **71 fichiers Swift** et **306 tests** déclarés |
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

Architecture MVVM, **71 fichiers Swift**, 710 fichiers suivis.

```
App/            SwiftdeepseekApp, ContentView
Core/           AppState, OfflineMerge, JSONValue, DateKeys, Program, ProgramGoal,
                Review, Quran, WeeklyProgress, Bookmark, AppConfig,
                VerseBounds, VerseMarkers, MarginAnnotations, PassageAudio,
                AudioRepeatPreferences, PassageAudioEngine, ChapterAudioCache,
                AppearanceOptions, SurahListOptions
Features/       Home, Quran (SurahListView, BookmarksView,
                Coran1441InstallView, AudioRepeatSettingsView + Reader/),
                Program, Progress, Review, Friends, Navigation, Shared,
                Settings (SettingsView, KnowledgeEditorView, ProgramEditorView,
                AppearanceView)
Models/         ViewModels/
Networking/     SupabaseRESTClient
Repositories/   AppStateRepository
Services/       Auth, StateSync, Social, QuranSource, Connectivity, Audio,
                PassageAudioExecutor
Storage/        LocalStore, KeychainStore
Theme/          Tests/        Resources/ (Data, Mushaf, Fonts)
Config/         Base/Debug/Release.xcconfig, Secrets.xcconfig.example
.github/workflows/ios.yml      Makefile      project.yml      scripts/
```

`Core/ProgramGoal.swift` porte la couche « objectif » de `src/core/program.ts` —
objectifs préréglés, `validGoal`, `resetAllProgress`, niveaux de rythme —, qui
manquait. `Core/AppearanceOptions.swift` porte les quatre décisions de l'apparence
qui ne doivent pas vivre dans une vue — ordre d'affichage des thèmes, bascule des
thèmes supplémentaires, ordre des accents, accent affiché (`SWIFT_MIGRATION.md`
§9.19). `Features/Settings/` porte les **quatre** écrans : les réglages, « Modifier
mes connaissances », « Modifier mon programme » (`SWIFT_MIGRATION.md` §9.18) et
« Apparence » (§9.19).

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
  Moushaf Tajwid, Coran avec règles de Tajwid. **Trois sont lisibles** : le Coran
  de Médine, embarqué (604 pages) ; le Coran 1441, qui s'installe par un
  téléchargement reprisable de 102 608 011 octets (`SWIFT_MIGRATION.md` §9.4) ; et la
  **Lecture simplifiée**, qui n'est **pas** une page — elle rend le texte verset par
  verset, coloré par règle (`SWIFT_MIGRATION.md` §9.31). Les deux autres ne sont pas
  reprises — voir la limite ci-dessous, et §9.3 de `SWIFT_MIGRATION.md` pour ce
  qu'elles contiennent réellement.
- **Défaut corrigé : le lecteur ouvrait sur une édition qu'il ne sait pas
  rendre.** L'état initial repris de l'original donne
  `reader.mushaf = "coranTest"` (`Program.swift:94`, d'après `program.ts:57`) —
  c'est la valeur de **tout** utilisateur qui n'a jamais touché au choix
  d'affichage. Cette édition n'est pas rendue par une image : l'original la
  dessine dans une page HTML chargée dans un WebView (`coranTest/html.ts`), avec
  607 polices `.woff2`. Résoudre la préférence telle quelle ouvrait donc le
  lecteur sur une édition sans images, et **chaque** page affichait « Cette page
  n'est pas encore disponible hors ligne » — un message faux, qui annonçait
  l'édition comme si c'était la page.

  `QuranEdition.displayed(stored:)` rend maintenant l'édition **affichée**,
  toujours lisible, et le lecteur dit laquelle il substitue. La préférence
  enregistrée n'est **pas** réécrite : elle reste `coranTest` dans le document
  synchronisé, donc l'application React Native retrouve son édition de Tajwid.

  **Sur les marque-pages, l'analyse de la version précédente de ce rapport était
  inversée.** Elle redoutait qu'un repli écrive `source: "traditional"` pour un
  utilisateur dont la préférence est `coranTest`. Or `Bookmark.save` écrit
  `sourcePages[source] = page` : la clé et la valeur doivent désigner **la même
  édition**. Avant la correction, l'application écrivait
  `sourcePages["coranTest"] = <page du Coran de Médine>` — un numéro de page venu
  d'une autre édition, et c'est **cela** qui divergait. Le repli écrit
  `sourcePages["traditional"] = <page du Coran de Médine>`, exactement ce que
  l'application React Native écrit quand l'utilisateur regarde le Coran de
  Médine.

  **Mesure, sur le point qui reste.** `reader.testPage` continue d'être écrit
  quand la préférence vaut `coranTest` (`AppViewModel.recordReading`), comme dans
  l'original (`App.tsx:212`). Ce numéro vient de `Quran.pageOf`, donc de la
  pagination du Coran de Médine. Or les deux paginations **ne coïncident pas
  partout** : sur les 604 pages, **568** portent le même intervalle de versets et
  **36** en diffèrent d'une frontière (page 120 : `740–746` contre `740–745`). Le
  repère de reprise de l'édition de Tajwid peut donc tomber une page à côté. Ce
  n'est pas une régression — l'application écrivait déjà cette valeur — mais une
  imprécision mesurée, que seule la reprise de l'édition lèverait.
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
- **Pastilles de numéro de verset du Coran 1441** — implémentées
  (`SWIFT_MIGRATION.md` §9.11). `Core/VerseMarkers.swift` lit
  `Resources/Data/coran_1441-markers.json` — **6 236** marqueurs sur **604** pages,
  un par verset, jusqu'ici lus par aucun code — et
  `Features/Quran/Reader/VerseMedallionView.swift` les dessine. Sont repris de
  `MushafPage.tsx:49` le fond `#ECFDF5`, la bordure `#047857`, le diamètre
  `largeur × 0,05`, l'épaisseur `× 0,003`, la police `× 0,025` et les chiffres
  arabes orientaux (`٠١٢٣٤٥٦٧٨٩`). La boîte d'une pastille passe par
  `VerseBounds.bandRect` : elle est donc **solidaire de la bande qu'elle annote**,
  et les deux ne peuvent pas diverger — même quand la vue n'a pas le ratio de la
  page, cas où la formule de l'original dérive. Un test vérifie l'invariant sur
  les **6 236** marqueurs.
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
- **Repères de progression de séance dans la marge** — implémentés
  (`SWIFT_MIGRATION.md` §9.12). C'était le dernier repère de `MushafPage.tsx` qui
  manquait : quand une séance est ouverte, un rail vertical et une pastille par
  **ligne** de la page, pleine quand tous les versets de la ligne sont validés.
  `Core/MarginAnnotations.swift` porte le regroupement par ligne et la géométrie,
  `Features/Quran/Reader/VerseMarginView.swift` dessine, et la dérivation de la
  séance (`App.tsx:477-481`) est portée avec ses trois points exacts — en
  apprentissage la séance enregistrée prime sur la plage demandée, la clé de suivi
  dépend du mode, et `through` retombe sur `start - 1`. La vue se trace dans la
  vue **entière** et non dans la boîte de page, parce que le diamètre d'une
  pastille (`min(24, max(8, bordGaucheDeLaPage − 4))`) dépend de la place libre à
  gauche de la page. Vingt-sept tests, dont les nombres sont mesurés par un banc
  qui fait tourner le **vrai** `marginAnnotations.ts` du dépôt de référence.
- **Ce qui n'est pas repris** : le bouton « Ma voix », l'enregistrement des
  récitations n'étant pas implémenté ; et les libellés d'accessibilité par verset
  mis en évidence, une page étant un élément d'accessibilité unique — ce qui vaut
  aussi, sur le Coran 1441, pour les pastilles de numéro et les pastilles de
  séance.
- **Barre d'action selon la raison d'ouverture** : trois notes de révision
  (Parfait / Quelques hésitations / À retravailler) puis « Écouter » pour une
  tâche de révision ; « Valider la consolidation · J+n » pour une consolidation ;
  « Valider » pour une séance d'apprentissage.

## 11. Fichiers et ressources copiés

| Ressource | Contenu | Vérification |
| --- | --- | --- |
| `Resources/Mushaf/` | **604 pages** du Coran de Médine | **MD5 identiques** aux 604 fichiers source, un à un |
| `Resources/Data/` | **15 fichiers** (`verses.json`, `pages.json`, `bounds.json`, `meta.json`, `ipa-audio-source.json`, `tajweed-*.json`, `coran_1441-*.json`, `translation-fr-rashid.json`, `TANZIL-LICENSE.txt`) | tracés jusqu'à leur source par MD5 |
| `Resources/Themes/` | les **5 illustrations de thème** — `white.png`, `emerald.png`, `rose.png`, `lilac.png`, `night.png` | **SHA-256 identiques** aux cinq fichiers source, et dimensions relevées (`white.png` **1613 × 975**, les quatre autres **1254 × 1254**) |
| `TANZIL-LICENSE.txt` | attribution du fournisseur des pages | fichier rédigé, sans jumeau côté source |

Fidélité binaire revérifiée : `git hash-object` du fichier de travail égale
`git rev-parse :chemin` pour les pages 1, 302 et 604 et pour `verses.json`.

**Non copié, volontairement** — omissions documentées dans `SWIFT_MIGRATION.md` :
`mushaf-tajweed` (132,13 Mo), `tajweed` (122,25 Mo), `coran-test` (48,88 Mo),
`illustrations` (les vignettes d'accueil) et les **polices**. Raisons : ressources
non nécessaires, ou licences incertaines. Ce sont les **images et les polices** qui
n'ont pas été copiées ; les **données** de deux de ces éditions le sont, en revanche —
`tajweed-text.json`, `tajweed-rules.json`, `mushaf-tajweed-bounds.json` et
`mushaf-tajweed-dimensions.json` sont dans `Resources/Data/` et ne sont lus par
aucun code Swift (`SWIFT_MIGRATION.md` §9.9). Le dossier `themes` de la référence, lui,
**est** repris — ses cinq PNG sont dans `Resources/Themes/`. Vérifié : **aucun code
Swift ne référence** `medallion.png`, `illustrations` ni `fonts` autrement que dans un
commentaire. `Resources/Fonts/` est donc vide.

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
| **#26** | `54be731` | **success** — documentation seule | — |
| **#27** | `40c7bb3` | **success** — documentation seule | — |
| **#28** | `4f07ea6` | **échec** — six échecs pour **une** constante fausse, un pour une exigence que j'avais inventée (voir ci-dessous) | — |
| **#29** | `16ee5ca` | **success** — 130 tests | — |
| **#30** | `6d49506` | **échec** — `flatMap` résolu sur `Sequence`, non sur `Optional` (`SWIFT_MIGRATION.md` §9.10) | — |
| **#31** | `18ab77e` | **success** — 140 tests, 1 ignoré, 0 échec ; IPA de 120 316 560 octets | 5 min 31 s |
| **#32** | `9b9dd27` | **success** — les pastilles de numéro de verset (`SWIFT_MIGRATION.md` §9.11) ; **152 tests, 1 ignoré, 0 échec** ; IPA de 120 323 680 octets | 4 min 33 s |
| **#33** | `5d25f38` | **success** — documentation seule ; c'est le run #32 qui porte les pastilles | 4 min 35 s |
| **#34** | `d5bc987` | **échec** — trois nombres du test des repères de marge, écrits de mémoire et non mesurés (voir ci-dessous) | 3 min 58 s |
| **#35** | `d33ee11` | **success** — les repères de progression de séance dans la marge (`SWIFT_MIGRATION.md` §9.12) ; **179 tests, 1 ignoré, 0 échec** ; IPA de 120 342 646 octets | 5 min 59 s |
| **#36** | `832a9f1` | **success** — documentation seule ; c'est le run #35 qui porte les repères de marge | 3 min 57 s |
| **#37** | `694d622` | **success** — le moteur de répétition audio et la lecture d'une sourate (`SWIFT_MIGRATION.md` §9.13) ; **201 tests, 1 ignoré, 0 échec** ; IPA de 120 349 892 octets | 3 min 5 s |
| **#38** | `b9ec8ef` | **success** — documentation seule ; c'est le run #37 qui porte le moteur de répétition audio | 5 min 5 s |
| **#39** | `6f502a3` | **échec** — quatre références à un membre statique depuis un contexte d'instance, à qualifier de `Self.` (voir ci-dessous) | 54 s |
| **#40** | `6c3a7b0` | **échec** — deux valeurs écrites de mémoire dans le test, non dans le portage (voir ci-dessous) ; **228 tests, 1 ignoré, 2 échecs** | 8 min 52 s |
| **#41** | `9e9f2bf` | **success** — les réglages de répétition et le contrôle qui relit les listes figées du test (`SWIFT_MIGRATION.md` §9.14) ; **228 tests, 1 ignoré, 0 échec** ; IPA de 120 357 634 octets | 4 min 19 s |
| **#42** | `1eaaa61` | **success** — documentation seule ; c'est le run #41 qui porte les réglages de répétition | 5 min 7 s |
| **#43** | `6f7d778` | **annulé** — remplacé par le run #44 : le correctif `82674fd` a été poussé pendant son exécution, et la file annule le run en cours | 3 min 38 s |
| **#44** | `82674fd` | **success** — la machine d'état de la boucle de répétition (`SWIFT_MIGRATION.md` §9.15) ; **253 tests, 1 ignoré, 0 échec** ; IPA de 120 363 268 octets | 8 min 0 s |
| **#45** | `d383010` | **échec** — **une seule** erreur de compilation : `LocalStore` est un **acteur**, donc sa lecture ne peut pas se faire dans un `init` (voir ci-dessous) | 1 min 32 s |
| **#46** | `ba1c091` | **success** — l'écran des réglages de répétition et le banc qui vérifie que cette vue ne décide de rien (`SWIFT_MIGRATION.md` §9.16) ; **253 tests, 1 ignoré, 0 échec** ; IPA de 120 399 682 octets | 7 min 58 s |
| **#47** | `3049696` | **success** — documentation seule ; c'est le run #46 qui porte l'écran des réglages de répétition | 5 min 43 s |
| **#48** | `eaca778` | **success** — la boucle de répétition branchée sur AVFoundation (`SWIFT_MIGRATION.md` §9.17) | 5 min 35 s |
| **#49** | `f34737d` | **échec** — **deux** erreurs de compilation, toutes deux dans `ProgramEditorView.swift` : une seule fermeture `(Division) -> Bool` y servait à interroger `Quran.surahs`, qui est un tableau de `Surah` (voir ci-dessous) | 55 s |
| **#50** | `76d57a5` | **success** — les réglages : modifier son programme et ses connaissances (`SWIFT_MIGRATION.md` §9.18) ; **286 tests, 1 ignoré, 0 échec** ; IPA de 120 511 485 octets | 6 min 45 s |
| **#51** | `54ef7be` | **success** — documentation seule ; c'est le run #50 qui porte les réglages | — |
| **#52** | `085a7f4` | **success** — l'écran d'apparence (`SWIFT_MIGRATION.md` §9.19) ; **306 tests attendus, 1 ignoré, 0 échec** sur **seize** groupes — compte **déduit**, l'artefact étant inaccessible sans jeton (voir ci-dessous) ; IPA de 120 542 217 octets | 6 min 1 s |
| **#53** | `f1517a1` | **success** — documentation seule ; c'est le run #52 qui porte l'écran d'apparence | 5 min 26 s |
| **#54** | `92874b3` | **échec** — **un seul** test rouge, `testResetAdvancesTheTimestamp` : le portage de `maxISO` divergeait de l'original **sous la milliseconde** (voir ci-dessous) | 4 min 51 s |
| **#55** | `a5a25fd` | **success** — le correctif de `maxISO` ; **307 tests mesurés, 1 ignoré, 0 échec** — c'est le run qui **mesure** le compte au lieu de le déduire | 6 min 31 s |
| **#56** | `e26c817` | **success** — documentation seule ; il consigne le §9.20 et le run #55, et **re-mesure 307 tests** — une seconde mesure indépendante | 4 min 40 s |

Le tableau s'étend aussi pour un run qui ne porte qu'une modification de
documentation : il est alors marqué « documentation seule ». Il s'étend surtout quand un run
**porte un fait**. Les runs #22 à #25 en
portent deux ; #28 à #30 en portent trois — une constante fausse, une exigence
que j'avais inventée, et une résolution de méthode ; #31 porte le correctif de
l'édition affichée ; #33 et #36 ne portent rien, et c'est dit ; #34 et #35 portent
les repères de progression de séance, et la correction des trois nombres de leurs
tests qui avaient été écrits de mémoire ; #37 porte le moteur de répétition audio.
Les trois premiers sont détaillés plus bas, parce qu'aucun n'a la cause que son
message laissait croire. #38 ne porte rien, et c'est dit ; #39 porte une erreur de
compilation — un membre statique lu depuis un contexte d'instance, sans `Self.` ;
#40 porte **deux échecs de test**, dans le fichier de test et non dans le portage ;
#41 porte les réglages de répétition et la section 15 du banc, qui relit les
listes figées du test. #42 ne porte rien, et c'est dit. #43 a été **annulé** par
le correctif `82674fd`, poussé pendant son exécution : la file annule le run en
cours, et c'est le prix d'un correctif poussé trop tôt — le n° 44 l'a remplacé.
#44 porte la **machine d'état de la boucle de répétition** et ses **vingt-cinq**
tests ; #45 porte **une seule erreur de compilation**, et cette erreur vaut d'être
racontée ; #46 porte l'**écran des réglages** et le banc qui vérifie qu'il ne
décide de rien ; #47 ne porte rien, et c'est dit ; #48 branche la boucle de
répétition sur AVFoundation ; #49 porte **deux** erreurs de compilation, et
celles-là aussi valent d'être racontées — elles disent la **limite** des bancs ;
#50 porte les **réglages du programme et des connaissances**, et c'est le premier
run où la cible de tests compile **et** s'exécute avec le nouveau groupe. #51 ne
porte rien, et c'est dit ; #52 porte l'**écran d'apparence** et le champ `swatch`
qui manquait sur `Theme.Accent` — le run dont le compte de tests est **déduit**
faute d'artefact accessible, et la déduction est expliquée plus bas. #53 ne porte
rien non plus — il compile une correction de documentation —, et c'est dit. #54
porte **un défaut de portage**, révélé par un test que cinquante runs verts
avaient laissé passer : c'est le run le plus instructif de la série, et il est
raconté plus bas. #55 porte le **correctif** de ce défaut, et **mesure** le compte
de tests — le premier run dont ce rapport peut écrire le nombre sans le déduire.
#56 ne consigne qu'une documentation, et **re-mesure** ce même nombre : deux runs
indépendants disent **307**.

Le tableau reste donc **en retard d'un run** sur la réalité : consigner un run
demande une poussée, et cette poussée est elle-même un run. C'est structurel, et
c'est dit ici plutôt que corrigé.

Run #17 : **les 13 étapes en `success`** — garde-fou de dépôt, contrôle des flux,
Xcode, XcodeGen, génération du projet, **compilation**, **tests**, **archive non
signée**, **empaquetage de l'IPA**, **publication des artefacts** — et **1
artefact de 120 263 470 octets**. La taille est le second témoin : elle prouve que
les 604 pages sont réellement dans le paquet, et pas seulement que le fichier a
été créé.

Les **306 tests** de la cible de tests sont joués à chaque run, répartis sur
**seize groupes**. Pour les quinze premiers, le compte est lu sur l'**artefact**
du run #50 — et non sur le journal du flux, qui est tronqué (`tail -60`) et ne
porte pas la fin de la suite : `AppWiringTests` 3, `AudioRepeatPreferencesTests`
27, `Coran1441DownloadTests` 20, `DateKeysTests` 8 (dont **1 ignoré**),
`JSONValueTests` 11, `MarginAnnotationsTests` 27, `OfflineMergeTests` 18,
`PassageAudioEngineTests` 25, `PassageAudioTests` 22, `ProgramGoalTests` 33,
`ProgramTests` 14, `QuranEditionTests` 10, `ReviewTests` 30, `VerseBoundsTests`
26, `VerseMarkersTests` 12 — la ligne du paquet le confirme indépendamment
(`SwiftdeepseekTests.xctest` : `286 tests, 1 ignoré, 0 échec`). Le seizième
groupe, **`AppearanceTests`**, en porte **20**.

**Un compte déduit n'est pas un compte mesuré, et la différence est écrite ici.**
Le run n° 52 est vert — cela est **mesuré** (verdict, étapes, taille de l'IPA,
annotation) —, mais son compte de tests ne l'est pas : le téléchargement de
l'artefact rend **401** sans jeton, `gh` n'était pas authentifié dans la session de
mesure, et le résumé du contrôle de commit est vide. Ce qui rend la déduction
solide n'est pas une intuition, c'est une **égalité mesurée** : les quinze fichiers
qui existaient au run n° 50 déclarent **286** méthodes, et le run n° 50 en a
**exécuté 286**. La correspondance « déclaré / exécuté » est donc établie, et
**306** s'en déduit pour seize groupes. Un tableau ou une phrase qui présenterait
ce nombre comme lu sur l'artefact serait faux. **Le run n° 55 a depuis mesuré ce
compte** — **307**, un ignoré, zéro échec — en lisant le journal avec un `gh`
authentifié ; la déduction tombe donc juste, et la nuance reste écrite ici. Le seul test
ignoré est celui de la traversée du changement d'heure, qui n'a rien à éprouver
dans un fuseau sans heure d'été. Deux des tests d'`AppWiringTests` étaient
**ignorés** tant que les secrets `SUPABASE_URL` et `SUPABASE_ANON_KEY` n'étaient
pas posés sur le dépôt : ils vérifient la configuration, qui était alors absente.
Ils s'activent d'eux-mêmes — mesuré, run #31 : `AppWiringTests` passe de
« 3 tests, 2 ignorés » à « 3 tests, 0 ignoré ».

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
« 110 tests, 3 ignorés » (le compte de l'époque), ce qui est un état supporté et documenté.

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

### L'échec #28 : sept rouges ne faisaient pas sept problèmes

Le run #28 (`4f07ea6`) a échoué avec **sept** tests rouges, et le compte était
trompeur : ils ne venaient que de **deux** causes.

**Six des sept, une seule constante fausse.** `Coran1441Install.imageWidth`
rendait **1920** — la largeur d'une page du Coran de **Médine**, lue dans
`VerseBounds.imageSize` — au lieu de **1440**, la largeur d'une bande du
Coran 1441. La conséquence n'était pas une erreur mais un silence : chaque image
réelle de l'archive aurait été **refusée**, et le seul symptôme aurait été « le
téléchargement ne se termine jamais ». Corrigé en lisant la taille de la bonne
source, et fixé par un test qui écrit `1440 × 232` **en clair** — le seul endroit
où la valeur ne dépend pas du code éprouvé.

**Le septième était une exigence que j'avais inventée.** J'avais écrit qu'un flux
`zlib` devait être **refusé** par le décodeur d'Apple. Le journal a dit
`XCTAssertThrowsError failed: did not throw an error` : le décodeur l'**accepte**.
Les assertions de taille et d'empreinte du test voisin passaient, ce qui prouvait
déjà que `COMPRESSION_ZLIB` est bien du DEFLATE brut. L'assertion négative a été
remplacée par une observation enregistrée, plus un test qui couvre le vrai chemin
d'erreur — un flux corrompu.

**La leçon.** Un échec de test nomme un symptôme, pas une cause. Compter les
lignes rouges aurait fait chercher sept problèmes, dont cinq inexistants.

### L'échec #30 : `flatMap` sur une chaîne n'est pas celui d'`Optional`

Le run #30 (`6d49506`) a échoué à la **compilation**, sur une ligne que j'avais
écrite :

```
AppViewModel.swift:114: error: cannot convert value of type 'QuranEdition?'
                                  to closure result type 'String?'
AppViewModel.swift:114: error: cannot convert value of type 'String.Element'
                                  (aka 'Character') to expected argument type 'String'
```

L'intention était d'écrire « décode la préférence, ou `nil` » :
`reader?.mushaf.flatMap { QuranEdition(rawValue: $0) }`. Mais sur une **chaîne**,
`flatMap` se résout sur `Sequence` — celle des `Character` — et non sur
`Optional`. Le compilateur recevait donc un `Character` là où il attendait un
`String` : le refus est correct, mais le message parle de types qui n'ont rien à
voir avec l'intention.

Écrit en deux temps, la même intention passe :

```swift
guard let stored = repository.state.reader?.mushaf else { return nil }
return QuranEdition(rawValue: stored)
```

**Ce que cet échec dit du dispositif.** Aucun contrôle local ne pouvait
l'attraper : il n'y a pas de compilateur Swift sur la machine de rédaction, et
`scripts/verifier-flux.mjs` vérifie le **flux**, pas le Swift. Le compilateur
distant est donc la seule barrière — et c'est pourquoi relire ligne à ligne avant
de pousser n'est pas un luxe, mais le seul filtre disponible.

### L'échec #34 : trois nombres écrits de mémoire, et le canal qui les cache

Le run #34 (`d5bc987`) a échoué sur l'étape des **tests**, avec **trois** tests
rouges — tous dans `Tests/MarginAnnotationsTests.swift`, **aucun** dans le code de
production. Les trois portaient le même défaut, et c'est le seul qui compte ici :
**un nombre écrit de mémoire au lieu d'être mesuré.**

```
error: testTheRegionsAreFractionsOfTheSourcePage : XCTAssertEqual failed: ("10") is not equal to ("7")
error: testTheDiameterIsClampedBetweenEightAndTwentyFour : XCTAssertEqualWithAccuracy failed: ("16.4") is not equal to ("20.0")
error: testALabelThatWrapsGrowsTheMarkerDownwards : XCTAssertEqualWithAccuracy failed: ("32.0") is not equal to ("17.45")
```

1. **Sept régions au lieu de dix.** J'avais écrit le nombre de **versets** de la
   Fâtiha — sept — là où le fichier de rectangles en décrit **dix** : les versets 6
   et 7 sont à cheval sur deux lignes, donc chacun y figure deux fois. Le nombre de
   **pastilles** est celui des groupes, cinq. Trois nombres distincts pour la même
   page, et je les avais confondus.
2. **Un diamètre de 20 au lieu de 16,4.** Le banc portait un cas « milieu » avec
   `x = 0.01`, d'où `edge = 24` ; le test, lui, utilise `x = 0.001`, d'où
   `edge = 20,4` et un diamètre de `16,4`. J'avais recopié le nombre d'un cas
   **approchant**, pas du cas joué. L'assertion voisine — `minX == 2` — passait
   déjà, et elle le disait : `2 + 16,4 + 2 = 20,4`.
3. **Une assertion qui se comparait à elle-même.** Le test du libellé replié
   passait une mesure constante de `30` pour **tous** les libellés, puis vérifiait
   que « les autres pastilles ne sont pas touchées ». Elles l'étaient toutes, donc
   la comparaison portait sur deux grandeurs identiques : elle ne pouvait pas
   échouer. La mesure ne se replie plus que pour le libellé `3·4`, et la boucle
   compare désormais des pastilles réellement distinctes.

**Le canal a caché la répétition.** La première lecture a été faite sur les
**annotations** du contrôle, qui n'en rendaient qu'**une** — `("10") is not equal
to ("7")`. Le test portait en réalité **deux** fois cette assertion, pour le 1441
et pour le Médine, et les deux lignes d'erreur étaient **textuellement
identiques** : mon `sort -u` les avait fusionnées. Le journal complet, lui, donne
les trois échecs. Lire les annotations ne suffit donc pas — il faut le journal.

**La réparation est dans le banc, pas seulement dans le test.**
`_banc/oracle-margin.mjs` mesurait des cas **approchants** de ceux du test ; il
mesure désormais les cas **exacts**, y compris les trois bornes du diamètre, et il
les **vérifie** au lieu de les imprimer : neuf comparaisons, zéro écart. Le
fichier de tests porte cette mesure dans son en-tête, pour que le prochain nombre
ajouté ait un endroit d'où venir. Run #35 (`d33ee11`) : vert, 179 tests, 1 ignoré.
Et la règle a servi au run suivant : les 22 tests du moteur de répétition audio
(#37, `694d622`) n'ont **aucun** nombre écrit de mémoire — ils viennent tous de
`_banc/oracle-audio.mjs`, et le banc vérifie que le portage porte bien les lignes
décisives qu'il mesure. Le run est vert du premier coup.

**La limite de cette règle, elle, a été trouvée par le run #40.** Le banc
vérifiait le portage et ses propres nombres, mais **rien ne relisait les listes
recopiées dans le fichier de test** — et deux valeurs y avaient été écrites de
mémoire : `1e3` rangé parmi les textes acceptés au lancement, alors qu'il vaut
1000 et doit être refusé, et un document censé retomber sur ses défauts alors que
le portage en **garde** un champ, à juste titre. La section 15 de
`_banc/oracle-audio.mjs` comble ce trou : elle relit les listes figées **du test**
et les confronte à la référence, si bien qu'une valeur écrite de mémoire fait
tomber le banc, et non le test.

### L'échec #45 : un acteur, et le `await` qui manquait

Le run #45 (`d383010`) n'a franchi aucune étape de compilation. **Une seule**
erreur, et elle nommait exactement sa cause :

```
ViewModels/AppViewModel.swift:64:40: error: call to actor-isolated instance
method 'loadAudioPreferences()' in a synchronous main actor-isolated context
```

`Storage/LocalStore.swift:24` déclare `public actor LocalStore`. Ses méthodes sont
donc **isolées** : un appel depuis le contexte `@MainActor` du modèle doit être
`await`é. Or je l'avais placé dans l'`init`, qui ne peut pas `await`. Trois
corrections en ont découlé — les valeurs par défaut dans `init`, la lecture dans
`start()`, et l'écriture dans une tâche **enchaînée** : des tâches non structurées
ne sont pas garanties de démarrer dans l'ordre de création, et deux pastilles
touchées coup sur coup auraient laissé sur disque la valeur la plus **ancienne**,
en silence, le fichier restant parfaitement lisible.

Ce que ce run dit de la méthode : **le défaut tenait dans un mot**, et le banc que
je venais d'écrire ne le voyait pas. Il exigeait que le modèle **écrive** les
réglages — `saveAudioPreferences` était bien là, à la bonne ligne — sans regarder
le `await`. Un contrôle qui cherche un nom de méthode ne dit rien de la façon dont
elle est appelée. Le banc exige désormais l'`await` des deux côtés **et** l'`actor`
du magasin, et le falsificateur rejoue le retrait du `await` des deux côtés. Il n'y
a pas de compilateur Swift sur la machine de rédaction : c'est le run qui trouve
cette classe de défaut, et c'est sa fonction.

### L'échec #49 : deux types distincts, et un banc qui ne peut pas le voir

Le run #49 (`f34737d`) a échoué en **55 s**, sur la première étape de compilation,
avec **deux** erreurs — toutes deux au même endroit :

```
Features/Settings/ProgramEditorView.swift:375:41: error: cannot convert value of
type '(Division) -> Bool' to expected argument type '(Surah) throws -> Bool'
Features/Settings/ProgramEditorView.swift:393:41: error: cannot call value of
non-function type 'Surah?'
```

`initialUnit(for:)` et `initialIndex(for:)` partageaient **une seule** fermeture,
`let matches: (Division) -> Bool`, pour interroger trois tables : `Quran.juzs` et
`Quran.hizbs` — qui sont des `[Division]` —, puis `Quran.surahs`, qui est un
`[Surah]`. Or `Surah` et `Division` sont deux structures **distinctes**
(`Core/Quran.swift:18` et `:29`), toutes deux porteuses de `start` et `end`, ce
qui les rend interchangeables à la lecture et **incompatibles** au compilateur.
Chaque table a désormais sa fermeture, typée sur son propre élément.

Ce que ce run dit de la méthode, et c'est plus grave que le défaut lui-même :
**les bancs ne pouvaient pas le voir, par construction.** `_banc/verifier-reglages.mjs`
lisait `Quran.surahs` et la fermeture, chacun de son côté, et les trouvait tous
les deux — sans jamais pouvoir dire qu'ils ne vont pas ensemble. Un contrôle qui
vérifie la **présence** de deux choses ne dit rien de leur **compatibilité de
type**. Et la cible de tests n'a pas aidé non plus : l'étape du run qui compile
l'application (`xcodebuild build`) ne compile **pas** la cible de tests — le run
#50 est donc le premier où `ProgramGoalTests.swift` est compilé, et il le confirme
vert.

La règle qui en sort, et qui complète celle de `SWIFT_MIGRATION.md` §9.18 :
**un banc vert ne prouve pas que le Swift compile.** Les bancs lisent le flux, les
textes et les noms ; la compilation est la seule à connaître les types. Sur une
machine sans compilateur Swift, c'est le run — et lui seul.

### L'écran d'apparence : huit défauts dans le banc, et un compte déduit

Le run #52 (`085a7f4`) est vert, et c'est **mesuré** : `success`, **16 / 16**
étapes, une annotation (la file d'attente macOS), IPA de **120 542 217** octets,
**6 min 1 s**. Deux choses de ce bloc méritent d'être racontées, et aucune n'est
dans le code Swift.

**Les huit défauts étaient dans le contrôle.** La première exécution de
`_banc/verifier-apparence.mjs` a donné **8 échecs sur 63** — aucun dans le portage.
Trois venaient d'une seule erreur, qui vaut d'être retenue :

> `bodyOf(source, marqueur, fin)` **inclut** son marqueur. Pour une déclaration
> Swift comme `accentOrder: [String] = ["prune", …]`, partir du marqueur
> `accentOrder: [String] = [` fait rencontrer le premier `]` du **type**
> `[String]`, pas celui de la **liste**. Le corps se réduisait à
> `accentOrder: [String`, qui ne contient aucune chaîne — et le banc annonçait
> « le portage ne déclare rien » sur **trois** listes parfaitement présentes.

Les autres : un motif qui exigeait `return` là où Swift l'omet (une fonction à
expression unique), et une ancre « aucune image » qui attrapait
`Image(systemName:)` — la **coche de sélection**, qui n'a rien à voir avec
l'illustration du thème. Un troisième type, plus insidieux, a été commis **hors
du banc** : la comparaison du sous-titre a d'abord été faite avec
`grep -o '· couleur d.accent'`, dont le `.` **joker** a matché un **commentaire**
du fichier — apostrophe ASCII dans ma propre prose —, et j'ai cru à une corruption
d'encodage. **Un motif qui contient un joker ne prouve rien sur un caractère.**

**Le compte de tests du run #52 est déduit, et c'est écrit comme tel.** Le
téléchargement de l'artefact rend **401** sans jeton, `gh` n'était pas authentifié
dans la session de mesure, et le résumé du contrôle de commit est vide. Le nombre
**306** ne vient donc pas de l'artefact : il vient de ce que les quinze fichiers
existants déclarent **286** méthodes, nombre que le run n° 50 a **exécuté** — la
correspondance « déclaré / exécuté » est établie par cette mesure, et 306 s'en
déduit pour seize groupes. Présenter ce nombre comme lu sur l'artefact aurait été
faux, et c'est exactement le défaut que le run #34 avait puni : **un nombre écrit
de mémoire au lieu d'être mesuré**.

**Le run #55 lève la déduction.** L'artefact publié reste l'**IPA seul** — aucun
résultat de tests n'y est joint —, mais le **journal** est lisible dès lors que
`gh` est authentifié, et l'étape « Jouer les tests » en publie la fin
(`tail -60 build-tests.log`). La ligne du coureur y est :

```
Executed 307 tests, with 1 test skipped and 0 failures (0 unexpected)
```

Le compte est donc **mesuré**, et il tombe exactement sur la déduction : 286 mesurés
au run #50, plus les **20** d'`AppearanceTests`, plus le cas `maxISO` ajouté par
`a5a25fd`. La **ventilation par groupe**, elle, reste **déduite** : `tail -60` ne
laisse passer que les derniers groupes, et aucun artefact ne la porte. La nuance est
écrite ici pour qu'elle ne se perde pas.

### L'échec #54 : une divergence sous la milliseconde, révélée par un test de forme

Le run n° 54 (`92874b3`) **ne porte que de la documentation** — la correction des
quatre défauts de forme de ce rapport et de `SWIFT_MIGRATION.md`. Il est pourtant
**rouge**, sur **un seul** test :

```
Tests/ProgramGoalTests.swift:455: error:
-[SwiftdeepseekTests.ProgramGoalTests testResetAdvancesTheTimestamp] :
XCTAssertGreaterThan failed: ("2026-10-04 21:50:16 +0000")
    is not greater than ("2026-10-04 21:50:16 +0000")
```

**La première lecture — « test instable » — est fausse, et la vérifier a changé le
diagnostic.** Le test affirme qu'une remise à zéro avance l'horodatage. Le portage
de cet horodatage est `DateKeys.maxISO`, qui doit reproduire `src/core/program.ts:93` :

```js
const now = Date.now();                                  // entier de millisecondes
const previousTime = Date.parse(previous.updatedAt);
updatedAt: new Date(Math.max(now, previousTime + 1)).toISOString()
```

Tout y est en millisecondes **entières**, et `toISOString()` n'écrit que trois
décimales. `Math.max(now, previousTime + 1)` est donc **toujours** strictement
supérieur à `previousTime` : la référence ne peut pas rendre une valeur égale.

Le portage, lui, comparait `previous` à une lecture d'horloge de précision
inférieure :

```swift
var latest = Date()
for value in values.compactMap({ $0 }) where value >= latest {
    latest = value.addingTimeInterval(0.001)
}
return iso(latest)
```

Dès que les deux lectures tombent dans la **même** milliseconde, la condition est
fausse, `latest` reste `now`, et `iso()` rend la milliseconde de `previous` — une
valeur **égale**. La fenêtre se mesure : elle vaut la fraction de milliseconde
restante au moment de la première lecture. C'est pourquoi le défaut a survécu à une
cinquantaine de runs verts avant de sortir — et pourquoi un test qui ne l'attrape
qu'une fois sur cent n'est pas un mauvais test, mais un bon test sur un défaut rare.

**Le défaut est donc dans le portage, et il est de compatibilité.** L'application
React Native garantit un horodatage strictement croissant ; le portage Swift ne le
garantissait pas. Or c'est cet horodatage qui fait reconnaître la remise à zéro
comme la version la plus récente lors d'une fusion. Les deux applications ne se
seraient pas comportées de la même façon — exactement ce que cette migration doit
empêcher.

**Correction.** `maxISO` calcule en millisecondes entières, comme le modèle JS, et
`now` devient **injectable** :

```swift
public static func maxISO(_ values: [Date?], now: Date = Date()) -> String {
    var latest = milliseconds(now)
    for value in values.compactMap({ $0 }) {
        let candidate = milliseconds(value)
        if candidate >= latest { latest = candidate + 1 }
    }
    return iso(Date(timeIntervalSince1970: Double(latest) / 1000))
}
```

L'injection n'est pas un ornement : c'est elle qui rend la fenêtre **déterministe**
au lieu d'attendre une coïncidence d'horloge.

**Deux contrôles, et un troisième corrigé.**

- `_banc/oracle-horodatage.mjs` **empaquette le vrai `program.ts`** avec `esbuild`,
  remplace `Date.now` par une valeur fixe, et confronte la référence au portage sur
  une grille de **15 cas** — cinq positions de `previous` (la même milliseconde, une
  et deux millisecondes avant, cinq cents millisecondes dans le futur, l'époque 0)
  croisées avec trois lectures d'horloge **fractionnaires**. **53 vérifications, 0
  écart.** Son **témoin** — l'ancienne formulation — diverge sur **6 cas sur 15** :
  sans ce témoin, la grille pourrait ne pas contenir le cas discriminant, et le banc
  serait vert sans rien prouver.
- `_banc/falsifier-horodatage.mjs` : **4 mutations, 4 détectées**, chaque source
  restaurée **à l'octet**, et un refus de continuer si le témoin est rouge.
- `_banc/verifier-reglages.mjs` étiquetait ce contrôle **« l'horodatage avance
  strictement »** alors qu'il ne fait qu'une recherche de motif sur `DateKeys.maxISO(`.
  Un test de forme ne peut pas prouver une sémantique : l'étiquette annonçait donc
  plus que le contrôle. Elle dit désormais ce qu'il fait.

Le test `ProgramGoalTests` gagne un cas qui **reproduit** le défaut à coup sûr, avec
les trois chaînes attendues **recopiées du banc** — `2027-01-15T08:00:00.001Z`,
`…000Z`, `…501Z` — et non écrites de mémoire. **307 tests déclarés** (306 avant).

Le défaut, raconté côté migration, est documenté en `SWIFT_MIGRATION.md` §9.20.

### Les illustrations de thème : deux clés trompeuses, et un contrôle qui ne pouvait pas mordre

Après la correction de `maxISO`, le dernier point ouvert de l'écran d'apparence était
l'illustration des cartes de thème. Cinq PNG, **10 199 065 octets**, copiés depuis
`assets/themes/` et vérifiés **par empreinte SHA-256** contre la référence.

Le piège n'est pas dans le code : il est dans la **table**. `src/ui/Premium.tsx:9` associe
`classic` à `emerald.png` et `feminine` à `rose.png`. Une recopie « évidente »
(`classic.png`, `feminine.png`) **compile**, **passe le contrôle des clés**, et laisse
**deux cartes vides** — le nom est simplement introuvable dans le paquet, et rien d'autre
ne le dit. Deux mutations du falsificateur sont dédiées à ces deux clés.

Second piège, mesuré : `white.png` est en **1613 × 975** et les quatre autres en
**1254 × 1254**. Un ajustement (`.fit`) aurait donc cadré juste quatre thèmes et laissé des
bandes sur le cinquième. C'est `.fill` + `.clipped()` qui est obligatoire.

Le contrôle des cinq fichiers passe par une **empreinte**, qu'aucune substitution de texte
ne peut atteindre. Le falsificateur porte donc une section **binaire**, qui écrase le
contenu de `rose.png` par celui de `white.png`, lance le banc, puis restaure **à l'octet**.

**Deux erreurs dans le banc lui-même**, trouvées en le lançant et non en le relisant : le
libellé Swift est `contentMode:`, pas `content:` — la première expression régulière ne
pouvait donc jamais mordre ; et `minHeight:Theme.Art.bannerMinHeight` se cherche sur le
texte **aplati**, où l'espace après le deux-points n'existe plus. Un contrôle qui ne peut
pas mordre est vert pour la mauvaise raison, et c'est exactement ce que la falsification
sert à voir.

`_banc/verifier-apparence.mjs` passe de **63** à **89** vérifications,
`_banc/falsifier-apparence.mjs` de **25** à **47** cas — tous détectés, aucun orphelin
laissé sur le disque.

Le portage, raconté côté migration, est documenté en `SWIFT_MIGRATION.md` §9.21.

### L'affichage du Coran : une liste qui n'était pas la bonne, et trois écritures qui n'écrivent pas la même chose

La carte « Affichage du Coran » (`src/App.tsx:330`) a été portée avec
`Core/QuranDisplayOptions.swift`, `Features/Quran/QuranEditionChooser.swift` et
`Features/Settings/QuranDisplaySettingsView.swift`. Deux choses valent d'être racontées.

**L'onglet Coran proposait la mauvaise liste.** Il parcourait `QuranEdition.allCases`,
donc affichait **cinq** éditions — dont « Moushaf Tajwid », une clé que l'original ne
laisse jamais choisir, `migrateReaderState` la réécrivant vers `coranTest` à chaque
chargement (`src/core/program.ts:60`). L'original n'en propose que **quatre**, dans un
autre ordre, et les deux endroits où il les propose — le sélecteur modal de l'onglet
Coran (`App.tsx:515`) et la carte de réglages (`App.tsx:330`) — s'accordent : Coran de
Médine, Coran avec règles de Tajwid, Lecture simplifiée, Coran 1441. Le défaut était
silencieux : la liste s'affichait, simplement ce n'était pas la bonne. Le banc exige
désormais l'**écart** avec `allCases`, de sorte que la confusion ne puisse pas revenir
sans le dire.

**Les trois écritures de la carte ne posent pas le même défaut.** Celles des éditions
écrivent la valeur choisie ; celles du fond et du suivi audio écrivent
`state.reader?.mushaf ?? 'coranTest'`. Un appui sur un fond, sur une installation
neuve, **enregistre donc `coranTest`** — surprenant, mais c'est le contrat que
l'application React Native relit. Et `followAudio` est comparé `!== false`, pas
`|| true` : un `false` stocké reste `false`.

Une correction de méthode, au passage : le résumé de la session précédente affirmait que
cette carte n'appelait **pas** `touch`, contrairement à `changeQuranSource`
(`App.tsx:458`). La mesure dit le contraire — les **six** `onPress` de la ligne 330 sont
enveloppés dans `touch(...)`. Les trois règles du portage restent donc **pures**, et
l'horodatage vient de `AppStateRepository.mutate` (`Program.touch(transform(state))`,
ligne 113). Le banc exige les **deux** côtés de cette décision : si l'un des deux
changeait seul, le document cesserait d'avancer — ou avancerait deux fois.

Deux ancres fautives ont été trouvées en écrivant le banc, dont une par le
falsificateur : la fenêtre de la carte commençait à sa phrase d'**explication**, qui
vient **après** son titre dans le JSX — le contrôle qui demandait d'y trouver
`>Affichage du Coran<` ne pouvait donc pas réussir, et il échouait sur un banc par
ailleurs juste. L'ancre encodait ce qu'on attendait lire, pas ce que le fichier dit.

`_banc/verifier-coran-affichage.mjs` compte **97** vérifications,
`_banc/falsifier-coran-affichage.mjs` **58** mutations plus un témoin — 59 cas, tous
détectés, aucun orphelin laissé sur le disque. Le portage est documenté en
`SWIFT_MIGRATION.md` §9.22.

### Les marque-pages : un écran, deux portes, et trois divergences que rien ne signalait

L'écran « Mes marques-pages » (`src/BookmarksScreen.tsx`, douze lignes) est porté par
`Core/BookmarkOptions.swift` — les onze textes — et `Features/Quran/BookmarksView.swift`.
Il s'ouvre depuis **une seule** porte : le lecteur (`ReaderView`, bouton de barre
d'outils) — comme l'original, qui ne l'ouvre que depuis `sessionPanel === 'bookmarks'`
(`App.tsx:512`). Le portage en avait ajouté une seconde dans l'onglet Coran ; elle a
disparu avec l'écran qui la portait (voir la section suivante). La porte présente
l'écran avec l'**édition affichée**, et la reprise passe par une règle unique,
`AppViewModel.resumeBookmark`, qui écrit `lastUsedAt` — la source du badge « Dernière
reprise ».

Trois divergences silencieuses ont été trouvées en comparant au **modèle**, pas en
relisant le code :

**1. `Bookmark.save` gardait deux champs qu'il devait effacer.** `bookmarks.ts:8`
construit un objet **neuf** à sept clés, qui ne porte ni `lastUsedAt` ni `deletedAt`. Le
portage, lui, repartait de l'entrée existante. Conséquence mesurable : réenregistrer une
marque-page déjà reprise la **déplaçait** dans la liste — puisque `visible` trie sur
`lastUsedAt ?? updatedAt` — et réenregistrer une marque-page supprimée ne la
ressuscitait pas. Le banc compare désormais les sept clés, une par une, à l'oracle
(`bookmarks.ts` exécuté par `esbuild`).

**2. La page de reprise pouvait ouvrir une page d'une autre pagination.** Le repli était
`item.page`, c'est-à-dire un numéro venu du Coran de Médine. Or `sourceVersePage`
(`sourceNavigation.ts:4`) valide la page connue : elle n'est retenue que si elle **porte**
le verset dans l'édition affichée, sinon on rend la **première** page du verset. L'écart
entre les deux paginations est mesuré : **56 versets sur 6 236** changent de première
page, le premier étant le verset **746** (Al Mâ'idah 77 — la page 121 des rectangles
s'ouvre bien sur `[5,77,…]`) : page **121** au Coran de Médine, **120** en Coran 1441. Le
défaut était donc réel et atteignable, sur 56 versets. Il est fermé par
`Core/QuranSourceNavigation.swift`, que les **deux** appelants — l'écran et la règle de
reprise — partagent.

**3. `visible` ne départageait pas les ex æquo comme JavaScript.** `Object.values` rend
les clés entières en ordre **croissant**, et `Array.prototype.sort` est **stable** : à
horodatage égal, l'ordre des versets est conservé. Swift n'offre ni l'un ni l'autre —
`Dictionary` n'est pas ordonné, `sorted(by:)` n'est pas stable. Un départage explicite
(`first.verseId < second.verseId`) rétablit la règle, et c'est lui qui décide quelle
entrée porte le badge quand deux marque-pages partagent la même seconde.

**Une ligne du tableau de migration mentait depuis le premier commit.** En écrivant cet
écran, la mesure a montré que l'onglet Coran de l'original — `QuranScreen`,
`MainScreens.tsx:28-33` — est une **liste de sourates** que ce portage n'avait jamais
construite, alors que §3 l'annonçait `✅` et pointait `QuranScreenView.swift`. Le fichier
n'en a jamais porté trace, pas même en `54b2674`. Deux lignes ont été corrigées, et
l'écran manquant est devenu le bloc suivant : il est construit, et raconté plus bas
(`SWIFT_MIGRATION.md` §9.28 et §9.29).

**Un mutant a survécu, et c'est le banc qui avait tort.** Le contrôle du titre lisait le
fichier **brut** (`read(optionsPath)`), et le commentaire d'en-tête de
`BookmarkOptions.swift` cite « Mes marques-pages » : la chaîne restait donc trouvable
alors que la **constante** avait dérivé. Le falsificateur l'a montré — M16 survivait — et
le contrôle porte maintenant sur le code commentaires retirés, chaînes gardées
(`codeSwift`). Un contrôle d'absence de littéral ne doit pas pouvoir être satisfait par un
commentaire.

`_banc/verifier-marques-pages.mjs` compte **106** vérifications — les dix bancs
antérieurs rejoués — et `_banc/falsifier-marques-pages.mjs` éprouve **21** mutations :
toutes tuées, arbre rendu intact. Tests : **422 → 454** (22 sur `Bookmark`, 10 sur
`QuranSourceNavigation`). Le portage, raconté côté migration, est en `SWIFT_MIGRATION.md`
§9.28.

### La liste des sourates : deux recherches, un filtre à moitié appliqué, et une porte en trop

`QuranScreen` (`src/ui/MainScreens.tsx:28-34`) — l'onglet « Coran » de l'original — est une
**liste** : 114 sourates, ou 30 Juz', ou 60 Hizb, avec une recherche, un filtre de lieu de
révélation, une carte de progression, une carte de pied vers le Coran de Tajwid et un bouton
flottant « Dernière lecture ». La section précédente a montré que le portage occupait cette
place avec autre chose. Elle est construite.

`Core/SurahListOptions.swift` porte tout ce qu'un écran ne doit pas décider : les trois vues,
le filtre, la dérivation des lignes, la pagination d'une division, la progression et les
textes. `Features/Quran/SurahListView.swift` ne décide de rien — mesuré, ses **sept** chaînes
littérales sont des noms de symboles SF et un nom d'illustration, donc **aucun** libellé n'y
est recopié.

**Il y a deux règles de recherche, et elles ne portent pas sur les mêmes champs.**
`MainScreens.tsx:31` cherche une **sourate** sur `` `${s.number} ${s.name} ${s.meaning}
${s.arabic}` `` et une **division** sur `` `${d.number} ${view} ${surahs[verseAt(d.start).surah-1].name}` ``.
Les unifier — le réflexe « propre » — compilerait, et afficherait une liste plausible :
simplement, huit nombres changeraient. Tous recomptés sur les fichiers livrés :

| Recherche | Ce qu'elle trouve, et pourquoi |
|---|---|
| `"1"` sur les sourates | **34** — le numéro se cherche en `contains` : 1, 10 à 19, 21, 31, … 114 |
| `"ouverture"` sur les sourates | **2** — la sourate 1 et la 94 partagent la signification « L'ouverture » |
| `"yâsîn"` sur les sourates | **0** — le nom s'écrit « Yâ Sîn », en **deux mots** ; `"yâ sîn"` en trouve une |
| `"juz"` sur les Juz' | **30** — c'est un **préfixe** de « Juz’ », donc l'ASCII suffit |
| `"juz'"` (apostrophe droite) | **0** — le libellé porte U+2019, et `contains` ne l'ignore pas |
| `"baqarah"` sur les Juz' | **2** — Al Baqarah ouvre les Juz' 2 **et** 3 |
| `"pages"` sur les Juz' | **0** — la signification n'est pas cherchée |
| `"naba"` sur les Juz' | **1** — le Juz' 30 ouvre sur An Naba', pas sur An Nâs |

**Le filtre ne s'applique qu'à une vue sur trois.** Il est testé après la recherche, et
seulement dans la branche des sourates. La branche des divisions ne le regarde pas du tout, et
le bouton qui l'ouvre n'est rendu que dans la vue « Liste ». Le portage le tient par
construction : `rows(mode:query:filter:edition:)` ne **transmet** `filter` qu'à la branche des
sourates. Un test le vérifie des deux façons — par la forme du code, et par un compte : 30 Juz'
et 60 Hizb quel que soit le filtre.

**La page d'une division n'est pas une arithmétique locale.** « Pages X – Y » vient de
`studyPage` (`studyProgress.ts:8`), qui est exactement `QuranSourceNavigation.versePage`
**sans** page connue — la fonction que la reprise d'une marque-page emploie déjà. Le portage
**délègue** au lieu d'en écrire une seconde, parce que deux copies d'une même règle divergent
en silence : c'est précisément le défaut que la section précédente venait de fermer. Le
séparateur est un cadratin (U+2013), pas un trait d'union — un œil ne fait pas la différence
dans un écran, un `grep` la fait. Et les **56** versets dont la première page diffère selon
l'édition sont tous à l'intérieur d'un Juz' ou d'un Hizb : **aucune** division ne change de
plage, ce qui est mesuré plutôt que supposé.

**Une porte en trop, que le portage avait inventée.** En recalibrant les bancs, une mesure a
montré que l'onglet Coran du portage portait une **seconde** porte vers « Mes marques-pages ».
L'original n'en a qu'**une** — `App.tsx:512`, un panneau du lecteur — et `QuranScreen`
n'ouvre jamais `BookmarksScreen`. C'était donc une entrée que l'application React Native ne
connaît pas, et une seconde liste à tenir d'accord. Elle a disparu, et le banc l'épingle
désormais par un contrôle **négatif**. Trois contrôles et trois mutations ont été repointés en
conséquence dans `verifier-marques-pages.mjs` et son falsificateur ; `verifier-coran-affichage.mjs`
a vu trois de ses contrôles suivre le sélecteur d'édition jusqu'au lecteur.

**« J'ai appris jusqu'à » prend le plus grand verset, pas le plus récent.**
`const known=memorizedIds(state),last=known.length?Math.max(...known):null`. `memorizedIds`
retient `perfect` et `review` (`program.ts:138`), jamais `learning`, et c'est le **plus grand
identifiant** qui est nommé — pas la date de validation. Un test le vérifie par la négative :
un petit verset validé plus récemment ne gagne pas.

**Deux pièges d'ancre, trouvés en écrivant le banc.** Trois contrôles exigeaient un `return`
devant le corps d'une fonction dont le Swift rend la valeur **implicitement** (`"\\(count)
versets"` en dernière ligne) : l'ancre encodait ce qu'on attendait lire, pas ce que le fichier
dit. Et un contrôle des points de code comparait deux littéraux **du banc lui-même** — il
passait quoi qu'écrive le modèle. Il lit maintenant le corps de la propriété. Le falsificateur
éprouve les deux, par deux mutations distinctes.

**Le premier passage du flux a échoué, et il avait raison.** Le run n° 67 est tombé sur
treize tests : en JavaScript `''.includes('')` vaut `true`, en Swift
`"abc".contains("")` vaut **false** — et la recherche part toujours vide, donc l'onglet
Coran s'ouvrait sur une liste **vide**. Le banc ne pouvait pas le voir : il relit le source
et rejoue les règles en JavaScript. Un banc qui rejoue l'original ne prouve rien du
portage ; ce qu'il fallait, c'était exécuter le langage, et c'est le rôle du flux. Deux
contrôles et deux mutations le font désormais tomber **en local**, en quelques secondes.

`_banc/verifier-liste-sourates.mjs` compte **135** vérifications — les onze bancs antérieurs
rejoués, le compte global des tests ayant quitté ce banc pour le plus récent — et
`_banc/falsifier-liste-sourates.mjs` éprouve **30** mutations : toutes tuées, arbre rendu
intact. Tests : **454 → 502**, dont **48** pour `Tests/SurahListTests.swift`. Le portage,
raconté côté migration, est en `SWIFT_MIGRATION.md` §9.29.

### Le Tajweed : une unité de comptage qui n'est pas celle de Swift

`src/core/readerData.ts` tient trois fonctions et `MushafPage.tsx:34-43` le rendu qui les
emploie. L'édition `tajweed` — « Lecture simplifiée » — n'est pas une page : l'original la
fait passer par le rendu **verset par verset**. Ses données étaient **déjà** dans le dépôt
(1,46 Mo de texte, 2,63 Mo de règles, 1,45 Mo de traduction) et **aucun** code Swift ne les
lisait. Le **modèle** a été porté d'abord ; le **rendu** l'a suivi au bloc suivant, et les
deux moitiés forment **un seul** changement : ni l'une ni l'autre n'a de sens seule, et
c'est ce que le paragraphe suivant montre.

**Le seul point où le portage pouvait planter est l'unité de comptage.** Les `start`/`end`
des annotations indexent le texte. En JavaScript, `[...text]` découpe en **points de code** ;
en Swift, `Array(text)` découpe en **graphèmes**. Mesuré sur les 6 236 versets : les deux
découpages diffèrent **6 236 fois sur 6 236**. Le verset 2:282 porte **1 173** points de code
pour **680** graphèmes, et sa plus grande fin d'annotation vaut **1 171** — donc indexer en
`Character` sortirait du tableau et **planterait**, sur le plus long verset du Coran,
précisément celui qu'on ouvre pour vérifier. Un test épingle les trois nombres, et le 680
vient d'`Intl.Segmenter` (ICU, UAX #29) : une implémentation **indépendante** de Swift, donc
une contre-mesure et non une reformulation.

**Un second piège, de la même famille que le run n° 67, mais dans une donnée.**
`translation-fr-rashid.json` porte la clé `footnotes` sur les 6 236 lignes, et elle vaut
`""` sur **4 906** d'entre elles. L'original teste la **vérité** — une chaîne vide est fausse
— donc ces notes ne s'affichent pas ; un `String?` décodé rendrait `Optional("")`, et un
`if let` aurait affiché 4 906 notes vides. La leçon du n° 67 — **vérité** contre **présence** —
valait donc aussi pour les données, et elle est désormais écrite dans le modèle, éprouvée par
un test et par une mutation.

Trois règles silencieuses de plus sont figées : la fusion se fait sur l'**égalité de la
règle** et non sur l'identité de l'annotation (42:2 : trois annotations `madd_6` → un
fragment) ; un verset sans annotation rend **un** fragment nu, pas zéro (63 versets) ; et
« un fragment » ne veut pas dire « sans règle » — **un seul** verset (4274) rend un fragment
unique *coloré*, et ce contre-exemple est épinglé à côté du cas nu pour qu'un raccourci casse
au lieu de passer. L'ordre des six branches de `tajweedColor` est vérifié **source à source**
contre `readerData.ts`, préfixes compris.

`QuranSourceNavigation` n'a **pas** été touché : `.tajweed` reste rangé avec les éditions
paginées, et c'est **fidèle** — `isZipSource` ne vaut que pour `coran_1441`
(`quranSources.ts:6`), donc l'original retombe aussi sur `pageOf(id)`. Un contrôle du banc
compare les deux sources pour figer cet accord, plutôt que de « corriger » un portage juste.

**Un rendu qu'aucun écran ne pouvait atteindre.** `ReaderView` reçoit son édition **fixée à
la construction**, et cette valeur vient de `QuranEdition.displayed(stored:)`, qui rend
l'édition **seulement si** `isAvailable`. Tant que `.tajweed.isAvailable` valait `false`, le
lecteur ne pouvait **jamais** recevoir `.tajweed` : la liste n'aurait été dessinée nulle part.
Écrire le rendu sans retourner l'offre aurait produit du code **inatteignable** ; retourner
l'offre sans écrire le rendu aurait ouvert des cartes vides — le défaut de §9.28. Les
deux moitiés sont donc **un seul bloc**.

**L'offre ne peut pas être une constante.** `case .tajweed: return true` serait faux, et du
même défaut que `coranTest` : une constante ne dit rien de la **présence des données**. La
condition **lit** donc les ressources — `hasArabic && hasTranslation`, c'est-à-dire les trois
JSON du Tajweed présents dans le paquet —, et l'édition disparaîtrait d'elle-même si l'un
manquait. Un contrôle exige cette **forme**, un autre la conjonction, et une mutation retire
le second terme pour vérifier que le contrôle le voit.

**Le rendu n'est pas une page, et le défilement est structurel.** `MushafPage.tsx:34-43` a sa
branche propre : un fond arrondi, un en-tête doré centré, puis **une carte par verset**. Une
page du moushaf porte une image ; le Tajweed porte du texte, et une page peut compter **286
versets**. `App.tsx:499` le dit — `scrollEnabled={mushaf==='tajweed'}`,
`height={mushaf==='tajweed'?readerViewport.height:fit.height}`. Sans défilement la page serait
**coupée**, et c'est pourquoi cette liste **ne peut pas** vivre dans le `UIPageViewController` :
le lecteur a gagné une **troisième forme de corps**, un simple `if edition == .tajweed { liste }
else { page }` — plat, et non un nouveau `@ViewBuilder`, car au-delà de dix enfants Swift cesse
de type-vérifier le surplus.

**Quatre décisions, dont une qui change un type.** Les couleurs des cartes sont des littéraux
et **ne sont pas** celles de la page : `#FCE8E8` et `#D97878` pour un verset difficile, là où
le surlignage de page emploie `#E85B5B` — deux rouges, deux usages, et un test les oppose.
`color(of:textColor:)` est passée de `(Span, String) -> String` à `(Span, Color) -> Color`,
parce qu'**aucune table de cette application ne porte la couleur de texte d'un thème en
hexadécimal** (`Palette.text` est une `Color`) : prendre une chaîne aurait obligé la vue à
**fabriquer** un hexadécimal que rien ne vérifie. La table des règles, elle, reste une chaîne,
pour que le banc puisse la comparer au fichier de référence. Le `lineHeight` de l'original est
**absolu**, le `lineSpacing` de SwiftUI est **additif** : la traduction est
`max(0, lineHeight − UIFont.systemFont(ofSize: fontSize).lineHeight)`, et son invariant
`UIFont.lineHeight + lineSpacing == lineHeight` est mesuré. Enfin le rail de séance de la liste
**n'est pas** celui de la marge — `MushafPage.tsx:41` lit la position de **chaque carte** et pose
un point par verset actif, là où `MarginAnnotations` regroupe par proximité ; les confondre
donne un rail plausible et faux.

**Deux contrôles retournés, et six assertions qui les suivaient.** Retourner l'offre a fait
tomber **huit** affirmations, pas deux : les deux contrôles du banc, et **six** assertions de
tests qui disaient la même chose dans quatre fichiers. C'est la trace que laisse une migration
bloquée — les assertions de l'ancienne application continuent d'affirmer ses contraintes.
Elles ont été **retournées**, pas supprimées. Le contrôle des appelants, lui, ne testait qu'une
**longueur** et jamais la **valeur** : il ne pouvait donc pas distinguer « aucun appelant » de
« un mauvais appelant ». Il exige maintenant **exactement un** appelant, et le nomme — ce qui a
révélé un défaut du contrôle lui-même, `path.relative` rendant des **antislashs** sous Windows,
invisible tant que le contrôle ne comparait qu'un nombre.

**Le run n° 71 est tombé, et sur une règle que le banc POUVAIT voir.** L'erreur unique —
`extra argument 'minHeight' in call`, à `TajweedVerseListView.swift:294` — venait d'un
appel `.frame(width:minHeight:alignment:)`, **surcharge qui n'existe pas** : `frame` en a
deux, `width`/`height` et la famille `minWidth`…`maxHeight`, et jamais un mélange. C'est une
faute d'**API**, et sa règle est purement **syntaxique** : un appel qui porte `width:` *et*
`minHeight:` ne peut pas compiler, et cela se **lit**. Le banc porte donc désormais ce
contrôle, sur **tout le projet** — 90 appels `frame(…)` analysés. La frontière tracée au
n° 69 se précise : ce n'est pas « le texte ne peut rien dire de la compilation », c'est
« le texte dit ce qui a une **signature** textuelle ». Un type n'en a pas ; une surcharge, si.

`_banc/verifier-tajweed.mjs` compte **139** vérifications — les douze bancs antérieurs
rejoués — et `_banc/falsifier-tajweed.mjs` éprouve **36** mutations : toutes tuées, arbre
rendu intact. Tests : **502 → 527 → 542**, dont **25** pour `Tests/TajweedTests.swift` et
**15** pour `Tests/TajweedListTests.swift`. Ce banc **ne prouve pas** le comportement du portage —
il rejoue l'original en JavaScript —, et son en-tête le dit : ce qui reste au flux, c'est
l'exécution des 40 tests. Récit complet en `SWIFT_MIGRATION.md` §9.30 et §9.31.

Le premier run de ce bloc, le n° **69**, est d'ailleurs tombé — non sur un test rouge, mais
sur une **erreur de type** que rien en local ne pouvait voir : `Tests/TajweedTests.swift`
lisait `verse?.surah` sur le tuple de `TajweedOptions.verse(_:)`, qui ne porte que `text` et
`annotations`. C'est le pendant de §9.29 : un banc qui rejoue l'original ne prouve rien du
portage, et **un banc qui lit du texte ne prouve rien de la compilation**. Le run n° 69 est
donc aussi la démonstration que la seule autorité sur la compilation reste
`.github/workflows/ios.yml`.

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
3. **`swiftdeepseek://auth` — fait par le propriétaire du projet.** Le schéma est
   autorisé dans *Authentication* → *URL Configuration* → *Redirect URLs*. Le
   projet porte `mailer_autoconfirm: false` (mesuré), donc la confirmation
   d'inscription est **obligatoire** : c'est ce schéma qui fait revenir le lien
   dans l'application au lieu de le laisser sur une page web. Détaillé dans
   `SUPABASE_COMPATIBILITY.md` §1.1.

   **Ce geste n'est pas vérifiable depuis l'extérieur**, et c'est mesuré :
   `/auth/v1/settings` ne rend **aucune** URL de redirection (611 octets de
   réponse, aucune clé `redirect`, `uri_allow` ni `site_url`), et la sonde
   `/auth/v1/authorize` ne peut pas servir de contrôle — aucun fournisseur OAuth
   n'est actif sur ce projet, seul `email` l'est. La vérification se fera donc
   **sur appareil**, par un lien de confirmation réel.

**Le plus gros manque de l'onglet le plus utilisé est comblé.** `QuranScreen`
(`MainScreens.tsx:28-33`) — la **liste des sourates**, avec sa recherche sur quatre
champs, son filtre Mecquoise/Médinoise, son sélecteur `Liste / Juz' / Hizb`, sa carte
« J'ai appris jusqu'à », sa carte de pied vers le Coran de Tajwid et son bouton
flottant « Dernière lecture » — n'existait pas ; il existe. `Core/SurahListOptions.swift`
porte les décisions, `Features/Quran/SurahListView.swift` les rend, et les blocs qui
occupaient la place sont partis au lecteur. Détail et preuve : `SWIFT_MIGRATION.md`
§9.29.

**Puis, par ordre d'importance fonctionnelle** (détaillé dans `SWIFT_MIGRATION.md` §9) :

> **Le téléchargement du Coran 1441 ne figure plus dans cette liste : il est
> fait.** Voir `SWIFT_MIGRATION.md` §9.4 — l'archive de 102 608 011 octets est
> téléchargée de façon reprisable, extraite **hors du fil principal**, et les
> 9 060 images sont exigées avant que l'installation soit déclarée prête. Ce que
> ce rapport appelait « le seul manque du lecteur » est donc comblé. Ce qui reste
> pour cette édition est la vérification sur appareil, comme pour le reste (§7).
4. **Les trois éditions non reprises** (`SWIFT_MIGRATION.md` §9.3), et la
   décision qui reste.

   **Le lecteur n'ouvre plus sur une édition qu'il ne sait pas rendre** : c'est
   corrigé, et c'est ce qui rendait ce point urgent (§10). Ce qui reste est le
   choix, pour le propriétaire, de reprendre — ou non — le contenu de ces trois
   éditions.

   **Les noms de la version précédente de ce rapport étaient trompeurs, et c'est
   mesuré.** « Tawjeed test 2 » et « Medine Test » ne sont pas des éditions : ce
   sont d'anciennes clés, que `migrateReaderState` réécrit vers `coran_1441`
   (`program.ts:60`). Le mode `tajweedPages`, lui, est réécrit vers `coranTest` à
   **chaque** chargement (`program.ts:62`) : personne ne peut l'atteindre, et ses
   604 pages (132,13 Mo) sont du poids mort dans le dépôt de référence — comme
   `assets/tajweed` (122,25 Mo), que **rien** ne référence.

   Les trois éditions réellement distinctes :

   | Édition | Ce qu'elle est | Ressources manquantes | Portable ici |
   | --- | --- | --- | --- |
   | `coranTest` — « Coran avec règles de Tajwid » | HTML dans un WebView (`coranTest/html.ts`) | 607 `.woff2` (48,88 Mo) + 606 JSON de page (4,25 Mo) | **non** : la chaîne de rendu est à écrire (`WKWebView`) |
   | `tajweed` — « Lecture simplifiée » | texte arabe coloré par règle | **aucune** : ses trois fichiers sont **déjà dans ce dépôt** | **portée** : modèle (§9.30) et rendu verset par verset (§9.31) |
   | `tajweedPages` — « Moushaf Tajwid » | pages coloriées | 604 PNG (132,13 Mo) | **sans objet** : mode inatteignable |

   **`coranTest` est le cas qui compte** : c'est le défaut des deux applications,
   donc l'édition de tout utilisateur qui n'a jamais touché au choix d'affichage.
   **`tajweed` n'est plus à faire** : son **modèle** *et* son **rendu** sont portés
   et prouvés (§9.30 et §9.31 — les règles, les six couleurs, les gardes, l'unité de
   comptage en points de code, la liste de cartes de verset de `MushafPage.tsx:34-43`
   avec le défilement de `App.tsx:499`, et l'édition désormais **proposée** parce
   que ses données sont là). Il ne reste à décider que `coranTest`, dont la
   chaîne de rendu (`WKWebView`) est à écrire. Ni l'une ni l'autre des deux
   éditions ne demande de copier les 185 Mo que la version précédente annonçait.
5. Assistant d'objectif hebdomadaire, messagerie, groupes, quiz,
   récitations, mini-lecteur — et l'**envoi** des notifications push, dont la carte
   des préférences est en revanche portée (`SWIFT_MIGRATION.md` §9.23).

*Déjà faites depuis la rédaction de la première version de ce rapport, et donc
retirées de cette liste : la notation des révisions dans l'interface (§10, barre
d'action), l'affichage rouge des versets difficiles (§10, `VerseBounds`), la
consommation de `ReaderRequest.reviewTask` et `.consolidation` par le lecteur,
les **pastilles de numéro de verset du Coran 1441** (§10, `SWIFT_MIGRATION.md`
§9.11), et les **repères de progression de séance dans la marge** (§10,
`SWIFT_MIGRATION.md` §9.12) — dont la version précédente de ce rapport disait
qu'ils dépendaient d'un suivi de séance « non porté », alors que
`StudyProgress.through`, `Program.studyKey` et `ReaderRequest.sessionID`
existaient déjà —, les **réglages** du programme et des connaissances
(`SWIFT_MIGRATION.md` §9.18), et l'**écran d'apparence** — le thème, la couleur
d'accent (§9.19) et les **cinq illustrations de thème** (§9.21), copiées à l'octet
et vérifiées par empreinte contre la référence —, et la carte **« Affichage du
Coran »** (§9.22), avec les quatre éditions de l'original, la décision à trois
issues et les quatre fonds, la carte **« Sources du Coran »** (§9.24), avec ses cinq chaînes et son lien recopiés au caractère près, le **modèle du profil** (§9.25) — quarante-sept textes, les quatre conditions d'activation dont l'asymétrie volontaire de « Se connecter », et le comptage en unités UTF-16 — et son **écran** (§9.26), qui ouvre le prénom, le compte et la déconnexion, et auquel il a fallu rendre le **canal des avis** : `notice` était posé par six écrans et lu par un seul, faute d'avoir porté le toast global de l'original, et les **trois cartes** de la
branche `profile` (§9.27) — « Connaissances », « Objectif et rythme » et
« Apprentissage », avec les trois décisions de `setReviewsEnabled` : le retour
anticipé qui ne touche pas le document, la durée **conservée** quand on éteint, la
reprise datée à l'allumage **seul** —, retournées à l'écran du profil après avoir été
rangées dans l'écran des réglages « tant que la page Profil n'existe pas ». Le **fond** et le **suivi audio** que cette carte
porte sont, eux, stockés, affichés et vérifiés mais **pas encore appliqués** :
leurs seuls consommateurs dans l'original vivent dans l'édition rendue en WebView,
absente de ce portage.*

**Côté Apple** (README §« Ce qu'il reste à faire côté Apple ») : compte de
développeur, identifiant de paquet enregistré, profil de provisionnement et
certificat, pour passer de l'IPA non signé à une installation normale.

---

## Règle non négociable, pour mémoire

> Le dépôt de référence est en **LECTURE SEULE**. Le seul dépôt modifiable est
> **`Swiftdeepseek`**. En cas de doute : **s'arrêter et demander.**

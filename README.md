# Swiftdeepseek

Application iOS native (Swift / SwiftUI) de mémorisation du Coran, reprise de
l'application React Native **`Msoumaya2019/coran-memoire`**.

Les deux applications fonctionnent **en parallèle**, sur le **même projet
Supabase** : mêmes comptes, mêmes `user_id`, mêmes données. Une action faite dans
l'une apparaît dans l'autre.

---

## Règles de travail — à lire avant toute modification

| | |
|---|---|
| `SOURCE_REPOSITORY` | `Msoumaya2019/coran-memoire` |
| `SOURCE_MODE` | **READ_ONLY** — aucun commit, aucune branche, aucune poussée, aucune modification de fichier, aucune migration Supabase |
| `TARGET_REPOSITORY` | `Msoumaya2019/Swiftdeepseek` |
| `TARGET_MODE` | **READ_WRITE** — le seul dépôt modifiable |

Avant toute poussée : `make guard`. Cette cible lit `git remote get-url origin`
et **refuse de continuer** si la destination n'est pas exactement
`Msoumaya2019/Swiftdeepseek` — en particulier si elle pointe vers le dépôt de
référence.

Le dépôt de référence n'est **pas** une dépendance de celui-ci : ni sous-module,
ni dossier imbriqué, ni lien physique. Supprimer l'un ne casse pas l'autre.

**En cas de doute, s'arrêter et demander.** Les changements Supabase suivent la
procédure de `SUPABASE_COMPATIBILITY.md` §4.

---

## Démarrage rapide

### 1. Configurer l'accès à Supabase

```bash
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
```

Renseigner ensuite les deux valeurs (voir le fichier, il contient les
avertissements) :

- `SUPABASE_URL` — l'adresse du projet **existant**, le même que l'application
  React Native ;
- `SUPABASE_ANON_KEY` — la clé **publiable** (`anon` / `publishable`).

> **Ne jamais mettre la clé `service_role`.** Elle contourne RLS et ne doit
> jamais quitter le serveur. La sécurité repose sur Supabase Auth + RLS, pas sur
> le secret de la clé publiable — qui est publique par nature.
>
> **Piège des `xcconfig`** : `//` commence un commentaire, même au milieu d'une
> valeur. Une URL s'écrit donc `https:$(SLASH)$(SLASH)…`. Détail dans
> `Config/Base.xcconfig`.
>
> **Second piège, plus sournois** : dans un `xcconfig`, la **dernière affectation
> gagne**. Les valeurs de repli vides de `Base.xcconfig` doivent donc être
> écrites **avant** le `#include?`, sinon elles écrasent `Secrets.xcconfig` sans
> rien dire. C'est arrivé : l'application construite portait
> `SUPABASE_URL = ''` alors que le fichier de secrets était correct — et les deux
> tests qui l'auraient signalé se sautaient, précisément parce que la
> configuration paraissait absente. Mesure et correctif dans
> `Config/Base.xcconfig`, section « ORDRE DES LIGNES ».

`Config/Secrets.xcconfig` est ignoré par Git. Sans lui, la compilation passe
quand même : l'application affiche un écran qui explique ce qui manque, au lieu
de se fermer sans rien dire.

### 2. Générer le projet Xcode

Le fichier `.xcodeproj` est **généré** à partir de `project.yml` :

```bash
brew install xcodegen
make project          # ou : xcodegen generate --spec project.yml
open Swiftdeepseek.xcodeproj
```

**Pourquoi ne pas committer le `.xcodeproj` ?** Ce dépôt a été écrit sans Mac.
Un `project.pbxproj` contient des centaines d'identifiants internes ; l'écrire à
la main sans pouvoir ouvrir Xcode reviendrait à livrer un fichier non
vérifiable. `project.yml` est court, relisible, et c'est lui la source de vérité.
Voir l'en-tête de `project.yml`.

### 3. Compiler, tester

```bash
make build     # compile pour le simulateur
make test      # joue les tests
make ipa       # IPA non signé dans build/
```

---

## Intégration continue

`.github/workflows/ios.yml` s'exécute sur un runner macOS et fait quatre choses :

1. **garde-fou** — refuse de s'exécuter ailleurs que dans
   `Msoumaya2019/Swiftdeepseek` ;
2. **compile** pour le simulateur ;
3. **joue les tests** ;
4. **produit un IPA non signé** et vérifie que les ressources coraniques sont
   bien dans le paquet (`verses.json`, dossier `Mushaf`) — un paquet sans ses
   données se lance et se ferme aussitôt.

Les runners macOS sont gratuits pour un dépôt **public** (c'est le cas). Si le
dépôt passe en privé, ce flux consommera le quota macOS, facturé environ dix fois
le tarif Linux.

Les secrets `SUPABASE_URL` et `SUPABASE_ANON_KEY` sont **facultatifs** : sans eux,
la compilation passe et l'application affiche l'écran de configuration.

### Lire un échec sans jeton

Le journal complet exige une session GitHub (HTTP 403 sans jeton). Les
**annotations**, elles, sont publiques — et le flux réémet lui-même les erreurs du
compilateur et des tests en annotations (`::error::`), précisément pour qu'un échec
soit diagnosticable sans ouvrir la page Actions :

```bash
curl -sL "https://github.com/Msoumaya2019/Swiftdeepseek/actions/runs/<run>/job/<job>" \
  | tr '\n' '\f' \
  | sed 's/<annotation-message/\n<annotation-message/g' \
  | grep '^<annotation-message' \
  | sed 's|</annotation-message>.*||; s/<[^>]*>//g; s/\f/ /g' \
  | sed 's/  */ /g; s/^ *//; s/ *Show more Show less *$//'
```

> Le texte d'une annotation est **imbriqué** dans des éléments : `grep -o '<annotation-message[^>]*>[^<]*'`
> ne rend rien du tout, et un `grep -c` sur le nom de classe annonce sept fois trop d'annotations
> (91 occurrences pour 13 blocs, sur un run réel). Éprouver l'extraction sur un run **en échec**
> avant de s'y fier : sur un run vert, une commande cassée rend un résultat plausible.

Trois pièges, mesurés :

- **`GET /actions/jobs/{id}` renvoie `annotations: []` même sur un job en échec**
  qui en porte treize dans le HTML. Le HTML est la source complète pour la cause ;
  l'API ne sert qu'au détail des étapes (`steps[].conclusion`).
- une étape qui capture un code de sortie doit faire **`set +e`** : le shell par
  défaut d'un `run:` est `bash -e`, donc l'échec tue le script avant `code=$?`.
- **les annotations sont PARTIELLES, et ne le disent pas.** Sur le run #34, les
  annotations du contrôle ne portaient qu'**un** des **trois** tests en échec. Le
  seul moyen de les connaître tous est le journal : avec un `gh` authentifié,
  `gh run view <run> --repo … --log-failed` le donne, et l'artefact porte
  `build-tests.log` **complet**. Corollaire mesuré : deux tests rouges distincts
  peuvent produire deux lignes d'erreur **textuellement identiques** — un `sort -u`
  distrait en fusionne une, et l'on croit à un seul échec.

### État mesuré

Run de référence — celui qui porte l'**écran d'apparence** (le thème et la couleur
d'accent) : **#52** (`085a7f4`), **6 min 1 s**, les **16 étapes en `success`** et
**une annotation** — le message de file d'attente macOS, qui va et vient d'un run à
l'autre. L'IPA pèse **120 542 217 octets** — les 604 pages sont donc bien
embarquées. Le numéro est **ancré sur un commit**, et non « le dernier » : une
poussée de documentation ajoute un run, si bien qu'une formule au superlatif serait
périmée dès son écriture.

Un run n° **53** (`f1517a1`), **documentation seule**, est vert ensuite : **16 / 16**
étapes en `success`, **5 min 26 s**, **une** annotation — le message de file d'attente
macOS. Il ne porte **aucun fait**, et c'est le n° 52 qui reste la référence.

Un run n° **54** (`92874b3`), **documentation seule** lui aussi, est en revanche
**ROUGE** — et il vaut d'être lu. Un seul test échoue,
`testResetAdvancesTheTimestamp` : le portage de l'horodatage d'une remise à zéro
comparait `previous` à une lecture d'horloge de précision **inférieure**, si bien
que les deux pouvaient tomber dans la **même milliseconde** et rendre une valeur
**égale**. L'original, lui, calcule en millisecondes entières et rend donc toujours
une valeur strictement supérieure. C'est une **divergence de compatibilité**, pas
un test instable — et le défaut a survécu à une cinquantaine de runs verts. Corrigé
par `a5a25fd`, avec `_banc/oracle-horodatage.mjs` (53 vérifications sur le vrai
`program.ts` empaqueté) et son falsificateur (4 mutations, 4 détectées).

Un run n° **55** (`a5a25fd`), qui porte **le correctif de `maxISO`**, est **vert** :
**16 / 16** étapes en `success`, **6 min 31 s** (le job, lui, 6 min 18 s). Et il apporte la mesure qui manquait.
Le journal complet est lisible dès lors que `gh` est **authentifié**, et il porte la
ligne du coureur :

```
Executed 307 tests, with 1 test skipped and 0 failures (0 unexpected)
```

Le compte n'est donc **plus déduit** : il est **mesuré**, et il vaut exactement la
somme attendue — **286** mesurés au run n° 50, plus les **20** d'`AppearanceTests`,
plus le cas `maxISO` ajouté.

Un run n° **56** (`e26c817`), **documentation seule**, **re-mesure** ce même compte —
**16 / 16** étapes, **4 min 40 s**, `Executed 307 tests, with 1 test skipped and 0 failures`.
Deux runs indépendants disent donc **307**, ce qui vaut mieux qu'une déduction, même juste.

**307 tests** sont déclarés, répartis sur **seize groupes**, et **un seul** est
ignoré : celui de la traversée du changement d'heure, qui n'a rien à éprouver dans
un fuseau sans heure d'été. Le groupe **`AppearanceTests`** en porte **20**, et
**`ProgramGoalTests`** **34** à lui seul — les six objectifs préréglés, leurs bornes,
le filtrage, la validation et la remise à zéro.

Depuis, le compte a été **mesuré à chaque run**, et il a grandi avec les blocs :
**328** au n° 59, **371** au n° 60 — le seul run **rouge** de la série, et pour deux
tests fautifs, jamais pour le portage —, **373** au n° 61, **384** au n° 62, **415**
au n° 63 et **416** au n° 64, le run qui porte l'**écran du profil**. L'arbre en
déclare aujourd'hui **585**, répartis sur **vingt-six** fichiers. Le bloc des trois
cartes du profil en a ajouté **six** (416 → 422), mesurés au run n° 65 ; celui des
marque-pages **trente-deux** (422 → 454) — vingt-deux sur le modèle et l'écran, dix sur
la traduction d'un verset en page ; celui de la **liste des sourates** **quarante-huit**
(454 → 502) — les deux règles de recherche, le filtre qui ne s'applique qu'à une vue,
la garde de la requête vide — trouvée par l'intégration continue, pas par le banc —
la pagination d'une division, la progression et les libellés ; celui du **Tajweed**
**vingt-cinq** (502 → 527) — l'unité de comptage en points de code et non en graphèmes,
la fusion par égalité de règle, le contre-exemple du fragment unique *coloré*, les six
branches de couleur, et la note de bas de verset qui vaut `""` sur 4 906 lignes ; et
celui du **rendu de la Lecture simplifiée**, **quinze** de plus (527 → 542) — les deux
rouges distincts de la carte, l'ordre des états de fond, la traduction du `lineHeight`
absolu en `lineSpacing` additif, le rail de séance d'une liste qui n'est pas celui de la
marge, et l'édition enfin **offerte** parce que ses données sont là. Le run n° **72** les a
mesurés — **542** — et a trouvé, dans le même souffle, la **septième** assertion que le
retournement avait manquée : un invariant **dérivé** qui exigeait des rectangles de toute
édition affichée. Il ne nommait pas `.tajweed`, et il est devenu faux sans qu'aucune de ses
lignes n'ait changé. L'arbre en déclare **543** depuis.

Et celui de la **réconciliation** — `Core/Reconcile.swift` — **quarante-deux** de plus
(543 → 585) : la fonction qui décide **laquelle des deux applications gagne** sur le
document partagé, écrite en **JSON brut** parce que sept de ses règles testent
`=== undefined` là où une structure Swift ne sait dire que `nil` ; le ternaire de
`reviewCycle`, seul membre de sa famille à **garder** un `null` distant ; la clé qu'un
`undefined` **retire** du document écrit, quand un `null` l'y ajouterait ; les deux
retours anticipés, dont un seul refuse de pousser ; et le défaut latent que le test
d'accord a trouvé dans `Program.migrateReaderState`.

Et le run n° **69** a rappelé à quoi sert ce compte : il est **tombé**, non sur un test
rouge mais sur une **erreur de type** — `Tests/TajweedTests.swift` lisait `verse?.surah`
sur le tuple de `TajweedOptions.verse(_:)`, qui ne porte que `text` et `annotations`. Les
quatre outils locaux — équilibre des délimiteurs, cohérence des types, banc, falsificateur —
lisent tous du **texte** et n'en pouvaient rien dire : **un banc qui lit du texte ne prouve
rien de la compilation**. Le compte de 527 annoncé plus haut n'a donc pas été *mesuré* au
n° 69, seulement *prédit*.

Le run n° **70** (`baa294e`), qui porte le correctif de cette erreur de type, l'a ensuite
**mesuré** : `Executed 527 tests, with 1 test skipped and 0 failures`. La prédiction se
vérifie — mais c'est la **mesure** qui compte, et elle est venue d'un run, pas d'un
raisonnement.

Le run n° 52, lui, ne portait qu'un compte **déduit** : l'artefact publié est
l'**IPA seul** — aucun résultat de tests — et `gh` n'était alors pas authentifié dans
la session de mesure. La déduction s'adossait à une **mesure** — le run n° 50 a mesuré
**286** tests exécutés, exactement le nombre de méthodes déclarées par les quinze
fichiers qui existaient alors. La correspondance « déclaré / exécuté » est donc
établie, et non supposée ; le run n° 55 l'a confirmée sur les seize groupes.

Plusieurs runs voisins disent ce que ce chiffre ne dit pas. **#39** (`6f502a3`) a
échoué à la compilation : quatre références à un membre statique depuis un
contexte d'instance, qu'il fallait qualifier de `Self.`. **#40** (`6c3a7b0`) a
compilé puis rendu **deux échecs** — non dans le portage, mais dans le fichier de
test lui-même, où deux valeurs avaient été écrites de mémoire au lieu d'être
recopiées du banc. C'est ce run qui a motivé la section 15 de
`_banc/oracle-audio.mjs` : elle **relit** les listes figées du test et les
confronte à la référence, si bien que cette classe de défaut ne peut plus passer
en silence. Et **#45** (`d383010`) s'est arrêté sur une **seule** erreur de
compilation — « call to actor-isolated instance method … in a synchronous main
actor-isolated context » : `LocalStore` est un **acteur**, donc sa lecture ne peut
pas se faire dans un `init`, qui ne peut pas `await`. Le défaut tenait dans un mot
— le `await` —, et aucun banc ne le voyait ; il est corrigé par `ba1c091`, et le
banc exige désormais l'`await` des deux côtés. Et **#49** (`f34737d`) s'est arrêté
en **55 s** sur **deux** erreurs de compilation, toutes deux dans
`ProgramEditorView.swift` : une seule fermeture `(Division) -> Bool` y servait à
interroger `Quran.surahs`, qui est un tableau de `Surah` — deux types
**distincts**, tous deux porteurs de `start` et `end`. Le banc lisait bien
`Quran.surahs` et la fermeture, chacun de son côté, sans pouvoir dire qu'ils ne
vont pas ensemble ; et l'étape qui compile l'application ne compile pas la cible
de tests. Un banc vert ne prouve donc pas que le Swift compile — seule la
compilation le dit.

Deux autres (`AppWiringTests`) ne s'exécutent que si la configuration Supabase est
présente : ils vérifient que l'URL arrive **intacte** dans l'application — non
tronquée par un `//` pris pour un commentaire — et que la clé embarquée n'est
**jamais** une clé `service_role`. Les secrets du dépôt étant désormais posés, ils
s'exécutent ; c'est en les réactivant qu'a été trouvé le défaut d'ordre des
`#include?` décrit plus haut.

Les actions sont épinglées à `checkout@v5` et `upload-artifact@v6`, les plus
petites versions qui déclarent `node24` (v5 de `upload-artifact` déclare encore
`node20`).

### Installation de l'IPA sur un appareil

L'IPA est **non signé**. Il s'installe par un outil de sideloading (AltStore,
Sideloadly, TrollStore…), **pas** par l'App Store, qui exige une signature Apple.

---

## Ce qu'il reste à faire côté Apple

Rien de tout cela ne bloque le développement. À faire quand une distribution
réelle devient nécessaire.

1. **Compte Apple Developer** — nécessaire pour installer durablement sur un
   appareil et pour TestFlight.

2. **App ID** — dans le portail Apple Developer, créer un identifiant d'application :
   - *Identifier* : `fr.swiftdeepseek.app` (celui du `project.yml`) ;
   - ne **pas** réutiliser `fr.coranmemoire.app` : les deux applications doivent
     coexister, y compris sur le même appareil.

3. **Notifications push (APNs)** — si les notifications sont souhaitées :
   - créer une **clé APNs** (`.p8`) dans *Certificates, Identifiers & Profiles* →
     *Keys*, avec le service *Apple Push Notifications* ;
   - **conserver le fichier `.p8` hors du dépôt** et hors de toute application
     compilée. Il ne doit jamais être committé ;
   - noter le *Key ID* et le *Team ID* ;
   - côté Supabase, c'est **le projet existant** qui doit être configuré avec
     cette clé — et cette configuration est **partagée** avec l'application
     React Native. À faire avec précaution, et après accord : elle touche un
     système en service.

4. **Certificat et profil de provisionnement** — en signature automatique, Xcode
   s'en charge ; sinon, créer un certificat *Apple Development* et un profil de
   provisionnement pour `fr.swiftdeepseek.app`.

5. **TestFlight** — nécessite une compilation **signée** (donc une équipe de
   développement renseignée dans `project.yml`, champ `DEVELOPMENT_TEAM`, ou dans
   Xcode → *Signing & Capabilities*). Le flux actuel produit une compilation non
   signée : il faudra l'étendre, ou archiver depuis Xcode.

6. **Entitlements** — `App/Swiftdeepseek.entitlements` déclare déjà
   `aps-environment`. Passer à `production` pour TestFlight et l'App Store.

---

## Architecture

```
App/            Point d'entrée, porte d'authentification, Info.plist, icône
Core/           Logique métier partagée — le contrat avec React Native
  AppState.swift      Le document user_state.data, typé
  JSONValue.swift     Valeur JSON opaque (clé inconnue préservée)
  OfflineMerge.swift  Fusion à trois voies — le fichier le plus critique
  Program.swift       Programme d'apprentissage
  Review.swift        Cycles, consolidations, versets difficiles
  WeeklyProgress.swift Objectif hebdomadaire, statistiques, régularité
  Quran.swift         Sourates, juz’, hizb, pages, versets
  VerseBounds.swift   Rectangles des versets sur les pages (bounds.json)
  Bookmark.swift      Marque-pages
  BookmarkOptions.swift  Les textes de « Mes marques-pages »
  QuranSourceNavigation.swift  Un verset, en page de l'édition affichée
  SurahListOptions.swift  La liste des sourates, des Juz' et des Hizb
  DateKeys.swift      Dates « AAAA-MM-JJ » à midi local
  AppConfig.swift     Configuration publique
Networking/     Client Supabase (REST, Foundation uniquement)
Storage/        Trousseau (session), stockage local (état, file d'attente)
Services/       Auth, synchronisation, connectivité, audio, sources, social
Repositories/   Accès à l'état, écriture qui préserve les clés inconnues
Theme/          Les 5 palettes et 4 accents de l'application actuelle
ViewModels/     AppViewModel — les vues ne parlent jamais à Supabase
Features/       Navigation, Accueil, Coran, Programme, Progrès, Amis, Révisions
Models/         Réservé (voir Models/README.md)
Resources/      Données coraniques, 604 pages, 5 illustrations de thème
Tests/          Tests de parité
Config/         xcconfig (dont le modèle de Secrets)
```

**MVVM.** Les vues observent `AppViewModel` ; elles ne touchent ni Supabase ni le
stockage. Toute modification passe par `AppViewModel.update { … }` : écriture
locale immédiate, puis synchronisation en tâche de fond — c'est ce qui rend
l'application utilisable sans réseau.

`UIKit` est utilisé là où il apporte quelque chose : `UIPageViewController` pour
la pagination du lecteur, intégré à SwiftUI par
`UIViewControllerRepresentable`.

Les **cinq illustrations de thème** sont embarquées dans `Resources/Themes`, déclaré
`type: folder` : `Bundle.main.url(forResource:withExtension:subdirectory:)` les trouve
dans un sous-dossier du paquet, et non à la racine — où `white.png` et `night.png`
entreraient en collision avec toute autre ressource de même nom. Deux clés ne portent
pas le nom de leur fichier : `classic` lit `emerald.png`, `feminine` lit `rose.png`.
Et les cinq images n'ont pas le même format — `white.png` est en 1613 × 975, les quatre
autres en 1254 × 1254 — d'où un recadrage (`.fill`) et non un ajustement.

**L'onglet Coran porte désormais ce que l'original y met.** `QuranScreen`
(`MainScreens.tsx:28-33`) est une **liste de sourates** — recherche, filtre
Mecquoise/Médinoise, sélecteur `Liste / Juz' / Hizb`, médaillon de numéro, carte
« J'ai appris jusqu'à », carte de pied « Coran avec règles de Tajwid », bouton
flottant « Dernière lecture ». `Core/SurahListOptions.swift` tient les trois vues, le
filtre, la dérivation des lignes, la pagination d'une division, la progression et les
textes ; `Features/Quran/SurahListView.swift` ne décide de rien et ne porte **aucun**
libellé — ses sept chaînes littérales sont des noms de symboles SF et un nom
d'illustration. Deux règles de recherche y cohabitent sans se confondre : une sourate
se cherche sur quatre champs, une division sur trois autres, et le filtre de lieu de
révélation ne s'applique **qu'à la vue « Liste »**. Les blocs qui occupaient la place
sont partis là où l'original les met : le sélecteur d'édition et l'installation du
Coran 1441 au lecteur, la reprise au bouton flottant, et la porte vers les
marque-pages — que l'original n'a jamais eue dans cet onglet — a disparu. Voir
`SWIFT_MIGRATION.md` §9.29.

Le **choix d'édition du Coran** n'est décidé qu'une fois. La liste des quatre
éditions, leur ordre, la décision d'un appui et le texte du refus vivent dans
`Core/QuranDisplayOptions.swift`, et `Features/Quran/QuranEditionChooser.swift` les
rend pour le **lecteur** et pour la carte « Affichage du Coran » des réglages.
L'écran qui les proposait parcourait auparavant `QuranEdition.allCases` : il en
affichait cinq, dans un autre ordre, dont « Moushaf Tajwid » — une clé que l'original
ne laisse jamais choisir, `migrateReaderState` la réécrivant vers `coranTest` à chaque
chargement. Les trois écritures de la carte ne posent pas non plus le même défaut sur
`reader.mushaf` : celles du fond et du suivi audio écrivent `coranTest` quand il n'y a
pas encore de lecteur. C'est surprenant, mais c'est le contrat que l'application React
Native relit.

La **carte des notifications** ne décide pas non plus de ses textes. Les sept
interrupteurs et leur ordre, leur valeur de repli, la porte de permission, le pied de
carte et les deux vérifications locales vivent dans `Core/NotificationOptions.swift`.
Trois choses y sont plus subtiles qu'elles n'en ont l'air. Un appui écrit le défaut
**matérialisé** : sur une installation neuve, toucher un interrupteur écrit aussi
`messages:true` et `learning:false` — c'est le contrat que l'application React Native
relit. Les deux prédicats de permission **divergent** : la carte autorise sur
`granted || PROVISIONAL`, le service et l'effet automatique en plus sur `EPHEMERAL`,
si bien qu'un statut EPHEMERAL laisse le service envoyer pendant que la carte montre
encore la porte. Et `sameChat` compare en égalité **stricte** : un message de groupe
porte `linkId: null`, donc sans conversation ouverte `null === null` est vrai et la
notification est supprimée au premier plan. Le type `NotificationPreferences` déclare
huit clés, mais aucune des deux cartes de l'original n'en propose `revision` : elle est
écrite par le service, et l'ajouter « par symétrie » afficherait un huitième
interrupteur que l'application actuelle n'a pas.

La **carte « Sources du Coran »** est le seul écran de réglages qui ne propose
rien : cinq chaînes et un lien, portés par `Core/QuranSourcesCard.swift`. Deux
détails y sont recopiés au caractère près, parce qu'un test les épingle : `juz’`
porte une apostrophe courbe **fermante** (U+2019) et `rub‘` une **ouvrante**
(U+2018) — probablement une coquille de l'original, mais la corriger ferait
diverger les deux applications à l'écran. Le titre est volontairement plus discret
que celui des autres cartes (14, `semibold`, `muted`) : c'est une note de bas de
page. Et le lien emploie `green2`, qui diffère de `green` sur deux thèmes.

La **carte du profil** — `App.tsx:322`, la plus longue de l'application — a son
modèle dans `Core/ProfileOptions.swift` et son écran dans
`Features/Profile/ProfileView.swift`, ouvert par le bouton de profil de la barre
de titre — celui qui porte l'**initiale** du prénom, ou un bonhomme à défaut.
Quarante-sept textes y sont portés, dont quatre conditions d'activation qui **ne
sont pas les mêmes** : « Se connecter » n'exige qu'un champ non vide, là où les
trois autres boutons exigent une arobase ou six caractères. Et le prénom se mesure
en **unités UTF-16** (`value.length`), pas en graphèmes : un prénom d'un seul emoji
est accepté ici comme dans l'original, alors qu'un `count` de Swift l'aurait
refusé. L'écran ne monte **pas** les boutons de photo : ils demandent le bucket
`friend-avatars` et une vérification serveur que cette version ne fait pas.

Le **canal des avis** mérite une ligne à lui. `notice` était posé par six écrans et
lu par **un seul** — l'écran de connexion, qui le traite comme une erreur. L'avis
global de l'original (`App.tsx:256`, un toast en bas d'écran, cadre doré) n'avait
pas été porté, si bien que l'application enregistrait, synchronisait et se
déconnectait **en silence**. Il l'est désormais (`NoticeToast`), monté **au-dessus**
de la porte d'authentification et non dans les onglets — sinon « Déconnecté. »
disparaîtrait avec eux.

### Ce que les tests verrouillent

| Fichier | Ce qu'il empêche de casser |
| --- | --- |
| `OfflineMergeTests` | La fusion à trois voies : un client ne doit jamais écraser les données de l'autre. |
| `ReconcileTests` | La réconciliation du document à la connexion : les deux retours anticipés de `reconcileState`, dont un seul refuse de pousser ; le ternaire de `reviewCycle`, qui **garde** un `null` distant là où ses six voisins se replient sur `??` ; la clé qu'un `undefined` **retire** du document écrit ; les quatre branches de `accountState` ; l'ordre **UTF-16** de deux horodatages (`"9" > "10"`) ; et deux tests d'**accord** entre le portage brut et le portage typé, chacun avec son témoin de non-vacuité. |
| `ProgramTests` | Les cycles 7/14/21/30, les quantités 1 Nisf / 1 Hizb / 1 Juz / 2 Juz, et le rythme **affiché** — le libellé d'un rythme connu, la chaîne **stockée** pour un rythme inconnu. |
| `ReviewTests` | Les consolidations J+1 / J+3 / J+7, la notation des révisions, le marquage « difficile », et les trois décisions de `setReviewsEnabled` — le retour anticipé qui ne touche pas le document, la durée **conservée** quand on éteint, la reprise datée à l'allumage **seul**. |
| `PassageAudioTests` | Les trois règles silencieuses de la répétition d'un passage — la répétition conservée en mode « passage », `continuous` qui ne change jamais de verset, la normalisation du nombre — et l'attente avant de rejouer, dont la marge de 200 ms est un plancher. |
| `AudioRepeatPreferencesTests` | Les six réglages de répétition : le `Number()` de JavaScript sur le champ libre (soixante-dix textes figés), le nombre normalisé qui n'est pas le nombre validé (un « Autre » de 5000 compte 5000 **et** refuse de lancer), la relecture champ par champ en égalité stricte, et les deux affichages — la case qui se décoche et le `∞` — qui ne se déduisent pas du réglage. |
| `PassageAudioEngineTests` | La boucle de répétition : on ne conclut que sur `nil`, le silence choisi ne s'applique qu'au redémarrage ou au verset répété, un verset qui suit dans la même piste se **reprend** au lieu d'être rechargé, et une pause pendant l'attente mémorise le temps restant. Chaque transition est comparée à la séquence d'effets que le banc **calcule** sur le vrai `src/core/audio.ts`. |
| `JSONValueTests` | La conservation des clés JSON inconnues — la condition de la compatibilité. |
| `QuranDisplayTests` | L'affichage du Coran : les quatre éditions de l'original (et l'écart avec `allCases`), la décision à trois issues — installer, sélectionner, refuser —, les quatre fonds et le repli sur le **premier**, et les trois règles d'écriture, dont le défaut `coranTest` que deux d'entre elles posent sur un lecteur absent. |
| `NotificationTests` | Les sept interrupteurs et leurs replis, le défaut **matérialisé** qu'un appui écrit sur une installation neuve, la divergence des deux prédicats de permission sur EPHEMERAL, l'égalité **stricte** de `sameChat` — un `linkId` nul sans conversation ouverte supprime la notification —, le registre qui se vide **entier** au-delà de 200 entrées, les deux formules des drapeaux d'affichage, et l'ordre du programmateur : annuler d'abord, programmer ensuite. |
| `QuranSourcesTests` | La carte des sources : les cinq chaînes au caractère près, les deux apostrophes typographiques distinctes (`juz’` U+2019, `rub‘` U+2018) et le tiret demi-cadratin du copyright, les six sources nommées, les deux licences citées, et la réserve sur les toumoun. |
| `ProfileTests` | Le profil : les cinquante-cinq constantes publiques du modèle au caractère près, les quatre conditions d'activation — dont celle de « Se connecter », qui n'exige **pas** d'arobase —, le comptage du prénom et du mot de passe en unités **UTF-16** (un emoji vaut deux), les deux bornes de photo qui sont deux nombres différents pour un seul message, le chemin d'avatar toujours en `.jpg`, la frontière entre `settingFirstName` qui écrit et `savingFirstName` qui garde, et l'initiale du bouton de profil — `nil` sur un prénom vide, pour que le bonhomme de repli apparaisse au lieu d'un rond vide. |
| `DateKeysTests` | Les dates « AAAA-MM-JJ » à midi local (jamais de décalage de fuseau). |
| `VerseBoundsTests` | L'ordre des colonnes de `bounds.json` et la projection des rectangles. |
| `AppWiringTests` | Le relais des services observables, l'URL Supabase non tronquée par `//`, et l'absence de clé `service_role` embarquée. |

Le chargement d'une ressource embarquée est possible dans les tests parce que la
cible de tests est **hébergée** dans l'application (`TEST_HOST` dans
`project.yml`) : `Bundle.main` y est donc le paquet de l'application.

---

## Documentation

| Fichier | Contenu |
|---|---|
| `docs/RAPPORT_FINAL.md` | Rapport de la première mission : ce qui est fait, ce qui est vérifié, ce qui ne l'est pas |
| `SWIFT_MIGRATION.md` | État de la reprise, fonction par fonction, avec les problèmes connus |
| `SUPABASE_COMPATIBILITY.md` | Le contrat avec la base partagée : ce qui est interdit, autorisé, et la procédure d'arrêt-demande |
| `LOCAL_DATA_MIGRATION.md` | Ce qui vit uniquement sur l'appareil dans l'application React Native, et ce qui se passe au passage |
| `Models/README.md` | Pourquoi ce dossier est vide |
| `Config/Secrets.xcconfig.example` | Modèle de configuration, avec les avertissements de sécurité |

---

## Licence et attribution

Le texte coranique embarqué provient de la source Tanzil. L'attribution est
**juridiquement obligatoire** : `Resources/Data/TANZIL-LICENSE.txt` doit rester
dans le paquet livré.

Les autres ressources proviennent du dépôt de référence. Celles dont
l'autorisation de redistribution n'était pas établie **n'ont pas été copiées** —
le détail et les raisons sont dans `SWIFT_MIGRATION.md` §8.

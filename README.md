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
Resources/      Données coraniques et 604 pages du Coran de Médine
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

### Ce que les tests verrouillent

| Fichier | Ce qu'il empêche de casser |
| --- | --- |
| `OfflineMergeTests` | La fusion à trois voies : un client ne doit jamais écraser les données de l'autre. |
| `ProgramTests` | Les cycles 7/14/21/30, les quantités 1 Nisf / 1 Hizb / 1 Juz / 2 Juz. |
| `ReviewTests` | Les consolidations J+1 / J+3 / J+7, la notation des révisions, le marquage « difficile ». |
| `PassageAudioTests` | Les trois règles silencieuses de la répétition d'un passage — la répétition conservée en mode « passage », `continuous` qui ne change jamais de verset, la normalisation du nombre — et l'attente avant de rejouer, dont la marge de 200 ms est un plancher. |
| `AudioRepeatPreferencesTests` | Les six réglages de répétition : le `Number()` de JavaScript sur le champ libre (soixante-dix textes figés), le nombre normalisé qui n'est pas le nombre validé (un « Autre » de 5000 compte 5000 **et** refuse de lancer), la relecture champ par champ en égalité stricte, et les deux affichages — la case qui se décoche et le `∞` — qui ne se déduisent pas du réglage. |
| `PassageAudioEngineTests` | La boucle de répétition : on ne conclut que sur `nil`, le silence choisi ne s'applique qu'au redémarrage ou au verset répété, un verset qui suit dans la même piste se **reprend** au lieu d'être rechargé, et une pause pendant l'attente mémorise le temps restant. Chaque transition est comparée à la séquence d'effets que le banc **calcule** sur le vrai `src/core/audio.ts`. |
| `JSONValueTests` | La conservation des clés JSON inconnues — la condition de la compatibilité. |
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

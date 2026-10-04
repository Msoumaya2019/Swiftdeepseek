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

Deux pièges, mesurés :

- **`GET /actions/jobs/{id}` renvoie `annotations: []` même sur un job en échec**
  qui en porte treize dans le HTML. Le HTML est la source complète pour la cause ;
  l'API ne sert qu'au détail des étapes (`steps[].conclusion`).
- une étape qui capture un code de sortie doit faire **`set +e`** : le shell par
  défaut d'un `run:` est `bash -e`, donc l'échec tue le script avant `code=$?`.

### État mesuré

Dernier run vert : **6 min 46 s**, 13 étapes en `success`, un artefact
`Swiftdeepseek-unsigned-ipa` de **120 242 542 octets** — les 604 pages sont donc
bien embarquées. Les actions sont épinglées à `checkout@v5` et
`upload-artifact@v6`, les plus petites versions qui déclarent `node24` (v5 de
`upload-artifact` déclare encore `node20`).

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
| `JSONValueTests` | La conservation des clés JSON inconnues — la condition de la compatibilité. |
| `DateKeysTests` | Les dates « AAAA-MM-JJ » à midi local (jamais de décalage de fuseau). |
| `VerseBoundsTests` | L'ordre des colonnes de `bounds.json` et la projection des rectangles. |
| `AppWiringTests` | Le relais des services observables, et l'URL Supabase non tronquée par `//`. |

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

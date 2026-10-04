# SWIFT_MIGRATION.md

État de la reprise, fonction par fonction, de l'application React Native
(`Msoumaya2019/coran-memoire`) dans l'application Swift (`Msoumaya2019/Swiftdeepseek`).

**Légende de l'état Swift**

| Symbole | Sens |
|---|---|
| ✅ | Repris et fonctionnel |
| 🟡 | Repris partiellement — voir la colonne « Problèmes » |
| ⬜ | Pas encore commencé |

---

## 1. Socle et compatibilité

| Fonctionnalité | État RN | État Swift | Tables Supabase | Fichiers Swift | Problèmes |
|---|---|---|---|---|---|
| Connexion avec un compte existant | ✅ | ✅ | `auth.users` (GoTrue) | `Services/AuthService.swift`, `Networking/SupabaseRESTClient.swift` | Mêmes identifiants → même `user_id`. |
| Création de compte | ✅ | 🟡 | `auth.users` | `Services/AuthService.swift` | Existe, mais à n'utiliser que pour un compte réellement nouveau — sinon doublon. |
| Réinitialisation du mot de passe | ✅ | ✅ | GoTrue | `Services/AuthService.swift` | |
| Renvoi du courriel de confirmation | ✅ | ✅ | GoTrue | `Services/AuthService.swift` | |
| Changement de mot de passe | ✅ | ✅ | GoTrue | `Services/AuthService.swift` | |
| Lien reçu par courriel (`…://auth`) | ✅ | ✅ | GoTrue | `Services/AuthService.swift` | Schéma propre : `swiftdeepseek://` (l'application RN garde `coranmemoire://`). |
| Session conservée entre deux ouvertures | ✅ | ✅ | — | `Storage/KeychainStore.swift` | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. |
| Ouverture sans réseau | ✅ | ✅ | — | `Services/AuthService.swift` | `restore()` ne consulte pas le serveur pour laisser entrer. |
| Document d'état typé | ✅ | ✅ | `user_state.data` | `Core/AppState.swift` | Clés identiques à celles du document existant. |
| Valeur JSON opaque (clé inconnue préservée) | ✅ | ✅ | `user_state.data` | `Core/JSONValue.swift` | Indispensable pour ne rien détruire d'une clé ajoutée plus tard par le RN. |
| Fusion à trois voies hors ligne | ✅ | ✅ | `user_state.data` | `Core/OfflineMerge.swift` | Port fidèle. 15 cas couverts dans `Tests/OfflineMergeTests.swift`. |
| Écriture qui préserve les clés inconnues | ✅ | ✅ | `user_state.data` | `Repositories/AppStateRepository.swift` | `patch(raw:with:)` ne remplace que les clés connues. |
| File d'attente hors ligne | ✅ | ✅ | — (locale) | `Storage/LocalStore.swift`, `Services/StateSyncService.swift` | Écritures atomiques (`.part`), cache exclu des sauvegardes iCloud. |
| Détection du retour du réseau | ✅ | ✅ | — | `Services/ConnectivityService.swift` | `NWPathMonitor`. |
| Thèmes (5) et accents (4) | ✅ | ✅ | `user_state.theme`, `.accent` | `Theme/Theme.swift` | Mêmes codes couleur que `src/theme/tokens.ts`. |
| Écran de choix de l'apparence | ✅ | ⬜ | `user_state.theme`, `.accent` | — | Le thème s'applique, mais n'est pas encore modifiable depuis l'interface. |

## 2. Navigation et accueil

| Fonctionnalité | État RN | État Swift | Tables Supabase | Fichiers Swift | Problèmes |
|---|---|---|---|---|---|
| Cinq onglets, même ordre | ✅ | ✅ | — | `Features/Navigation/MainTabView.swift` | Accueil · Coran · Programme · Progrès · Amis. |
| Accueil : objectif, reprise, séances du jour | ✅ | ✅ | `user_state` | `Features/Home/HomeView.swift` | |
| Accueil : programme des 10 prochains jours | ✅ | ✅ | `user_state` | `Features/Home/HomeView.swift`, `Core/WeeklyProgress.swift` | Plafonné à 10 jours, sans jamais purger le reste. |
| Accueil : question du jour et quiz | ✅ | ⬜ | `quiz_*` (RPC) | — | Étape suivante. |
| Contenus quotidiens | ✅ | ⬜ | `daily_contents`, `content_favorites`, RPC `daily_content_for_date` | — | Étape suivante. |
| Signalement de problème | ✅ | ⬜ | `app_problem_reports` | — | Étape suivante. |

## 3. Coran

| Fonctionnalité | État RN | État Swift | Tables Supabase | Fichiers Swift | Problèmes |
|---|---|---|---|---|---|
| Liste des sourates (recherche, filtre) | ✅ | ✅ | — (données embarquées) | `Core/Quran.swift`, `Features/Quran/QuranScreenView.swift` | |
| Liste des Juz’ et des Hizb | ✅ | 🟡 | — | `Core/Quran.swift` | Données prêtes (`juzs`, `hizbs`), l'interface liste seulement les sourates pour l'instant. |
| Lecteur « Coran de Médine » (604 pages) | ✅ | ✅ | — | `Features/Quran/Reader/ReaderView.swift`, `MushafPageViewController.swift`, `Resources/Mushaf` | 604 PNG embarquées. |
| Lecteur « Coran 1441 » | ✅ | 🟡 | — | `Services/QuranSourceService.swift` | Lit les pages si elles sont présentes ; **le téléchargement et l'installation sont implémentés** — voir §9.4. |
| Pagination native au doigt | ✅ | ✅ | — | `MushafPageViewController.swift` | `UIPageViewController`, comme prévu. |
| Préchargement page précédente / courante / suivante | ✅ | ✅ | — | `MushafPageViewController.swift` | Trois pages, jamais 604. Cache LRU. |
| Centrage vertical sans marge fixe | ✅ | ✅ | — | `ReaderView.swift`, `MushafPageViewController.swift` | Zone de page = tout l'espace restant, `scaleAspectFit`, contraintes centrées. Aucun `marginTop`. |
| Reprise à la dernière page lue | ✅ | ✅ | `user_state.lastRead` | `Features/Home/HomeView.swift`, `ViewModels/AppViewModel.swift` | |
| Marque-pages | ✅ | 🟡 | `user_state.bookmarks` | `Core/Bookmark.swift` | Poser/retirer dans le lecteur et lister dans l'onglet Coran : fait. Fusion : faite. |
| Choix de l'édition | ✅ | ✅ | `user_state.reader.mushaf` | `Features/Quran/Reader/ReaderView.swift` | Les cinq éditions, et les trois non reprises : voir §9.3. |
| Coran avec règles de Tajwid | ✅ | ⬜ | — | — | Ressources non copiées, voir §7. |
| Mode lecture continue | ✅ | ⬜ | — | — | |

## 4. Audio

| Fonctionnalité | État RN | État Swift | Tables Supabase | Fichiers Swift | Problèmes |
|---|---|---|---|---|---|
| Sept récitateurs, même liste | ✅ | ✅ | `user_state.audioPreferences` | `Services/AudioService.swift` | |
| Lecture, pause, verset suivant / précédent | ✅ | ✅ | — | `Services/AudioService.swift` | `AVFoundation`, session `.playback`. |
| Préchargement des versets suivants | ✅ | ✅ | — | `Services/AudioService.swift` | Trois versets d'avance. |
| Mini-lecteur persistant | ✅ | ⬜ | — | — | La barre audio du lecteur existe ; le mini-lecteur global reste à faire. |
| Répétition (passage / verset, nombre, silence, vitesse) | ✅ | ⬜ | — | — | Réglages locaux côté RN — voir `LOCAL_DATA_MIGRATION.md` §4a. |
| Lecture d'une sourate entière (fichier complet + horodatages) | ✅ | ⬜ | — | — | |
| Cache audio des versets | ✅ | 🟡 | — | `Services/AudioService.swift` | Cache en mémoire (`VerseAudioCache`) ; pas encore de cache sur disque. |

## 5. Programme, apprentissage, révisions

| Fonctionnalité | État RN | État Swift | Tables Supabase | Fichiers Swift | Problèmes |
|---|---|---|---|---|---|
| Génération du programme selon l'objectif | ✅ | ✅ | `user_state.sessions` | `Core/Program.swift` | |
| Séance du jour, reprise possible | ✅ | ✅ | `user_state.sessions`, `.studyProgress` | `Features/Program/ProgramView.swift` | Clé `learning:<id>` via `Program.studyKey`. |
| Une séance faite en avance ne change pas sa date prévue | ✅ | ✅ | `user_state.sessions` | `Core/Program.swift` | Couvert par `Tests/ProgramTests.swift`. |
| Séances en retard (« À rattraper ») | ✅ | ✅ | `user_state.sessions` | `Features/Program/ProgramView.swift` | |
| Historique des séances | ✅ | ✅ | `user_state.sessions` | `Features/Program/ProgramView.swift` | 20 dernières, terminées ou reportées. |
| Objectif et rythme | ✅ | 🟡 | `user_state.goal`, `.pace` | `Features/Progress/ProgressScreenView.swift` | Affiché ; **la modification de l'objectif n'est pas encore possible**. |
| Assistant de choix d'objectif | ✅ | ⬜ | `user_state.goal` | — | Régénère le programme : à faire avec ses propres tests de parité. |
| Versets connus / à revoir (marquage manuel) | ✅ | 🟡 | `user_state.knowledge` | `Core/Program.swift` | Fonctions prêtes (`markKnowledge`, `toggleKnownRange`), interface à faire. |
| Cycles de révision 7 / 14 / 21 / 30 jours | ✅ | ✅ | `user_state.reviewSettings`, `.reviewCycle` | `Core/Review.swift` | Changer de durée conserve l'historique. |
| Quantités : 1 Nisf / 1 Hizb / 1 Juz / 2 Juz | ✅ | ✅ | `user_state.reviewSettings.dailyQuantity` | `Core/Review.swift` | |
| Consolidations J+1 / J+3 / J+7 | ✅ | ✅ | `user_state.reviewConsolidations` | `Core/Review.swift` | Échéances ancrées à la date d'apprentissage, même si la consolidation est faite en avance. |
| Tableau de bord des révisions | ✅ | ✅ | `user_state.reviewCycle`, `.reviewHistory` | `Features/Review/ReviewDashboardView.swift` | |
| Versets difficiles (rouge léger) | ✅ | 🟡 | `user_state.difficultyMarkers`, `.reviewPriorityDue` | `Core/Review.swift` | Marquer / démarquer et lister : faits. **L'affichage rouge dans le lecteur n'est pas encore fait.** |
| Notation d'une tâche de révision | ✅ | 🟡 | `user_state.reviewHistory` | `Core/Review.swift` | `gradeReviewTask` est écrit ; **l'écran de notation n'est pas branché**. La demande d'ouverture porte déjà `reviewTask` et `consolidation`. |
| Objectif hebdomadaire (lundi 00:01) | ✅ | ✅ | `user_state.sessions` | `Core/WeeklyProgress.swift` | Semaine calendaire locale, heure d'été comprise. Historique conservé. |

## 6. Progrès

| Fonctionnalité | État RN | État Swift | Tables Supabase | Fichiers Swift | Problèmes |
|---|---|---|---|---|---|
| Pourcentage du Coran mémorisé | ✅ | ✅ | `user_state.knowledge` | `Core/AppState.swift`, `Core/Quran.swift` | Pondéré par le volume de texte arabe, pas par le nombre de versets. |
| Versets appris (jour / semaine / mois) | ✅ | ✅ | `user_state` | `Core/WeeklyProgress.swift` | |
| Régularité (jours d'affilée) | ✅ | ✅ | `user_state` | `Core/WeeklyProgress.swift` | |
| Pages et Juz’ mémorisés | ✅ | ✅ | `user_state.knowledge` | `Core/WeeklyProgress.swift` | |
| Graphique de la période | ✅ | ✅ | `user_state` | `Features/Progress/ProgressScreenView.swift` | |
| Statistiques détaillées | ✅ | ✅ | `user_state` | `Features/Progress/ProgressScreenView.swift` | |

## 7. Social, quiz, notifications, récitations

| Fonctionnalité | État RN | État Swift | Tables Supabase | Fichiers Swift | Problèmes |
|---|---|---|---|---|---|
| Profil social et code d'invitation | ✅ | ✅ | `friend_profiles`, RPC `ensure_social_profile` | `Services/SocialService.swift`, `Features/Friends/FriendsView.swift` | |
| Liste d'amis, demandes reçues / envoyées | ✅ | ✅ | `friend_links`, `friend_profiles` | `Services/SocialService.swift`, `Features/Friends/FriendsView.swift` | |
| Ajouter un ami par code, accepter, refuser | ✅ | ✅ | RPC `request_friend`, `accept_friend`, `decline_friend` | `Services/SocialService.swift` | |
| Boîte de réception (dernier message, non-lus, présence) | ✅ | ✅ | RPC `friend_inbox` | `Services/SocialService.swift` | |
| Messagerie (temps réel, saisie, lectures, pièces jointes) | ✅ | ⬜ | `friend_messages`, `friend_message_reads`, `friend_message_hidden` | — | Le plus gros bloc restant. |
| Groupes | ✅ | ⬜ | `friend_groups`, `friend_group_members` | — | |
| Objectifs partagés | ✅ | ⬜ | `friend_shared_goals` | — | |
| Rendez-vous de révision | ✅ | ⬜ | `friend_review_appointments` | — | |
| Récitations partagées | ✅ | ⬜ | `recitations`, bucket `recitations` | — | |
| Modération (signalements, suspensions, blocage) | ✅ | ⬜ | `friend_message_reports`, `social_suspensions`, RPC `block_friend`… | — | `blockFriend`/`unblockFriend` existent dans `SocialService`, sans interface. |
| Quiz : question du jour | ✅ | ⬜ | `quiz_*` (RPC) | — | |
| Quiz entre amis | ✅ | ⬜ | `quiz_*` (RPC) | — | |
| Notifications push | ✅ | ⬜ | `push_devices`, `notification_preferences`, RPC `register_push_device` | — | Jeton APNs propre, même `user_id` — voir §7 et `README.md`. |
| Enregistrement de récitation | ✅ | ⬜ | `recitations`, bucket | — | |
| Corrections de récitation | ✅ | ⬜ | `recitation_corrections`, RPC `finalize_recitation_correction` | — | |
| Écrans d'administration | ✅ | ⬜ | `app_admins`, RPC `admin_*` | — | |

## 8. Ressources embarquées

| Ressource | Décision | Détail |
|---|---|---|
| `Resources/Data/*.json` (15 fichiers, 8,9 Mo) | ✅ Copiée | `verses`, `meta`, `pages`, `bounds`, `tajweed-text`, `tajweed-rules`, `translation-fr-rashid`, `ipa-audio-source`, `mushaf-tajweed-*`, `coran_1441-*`. Copie vérifiée par empreinte SHA-256. |
| `Resources/Mushaf/` (604 PNG, 112,73 Mo) | ✅ Copiée | Coran de Médine, dossier conservé tel quel (le lecteur les cherche dans `Mushaf/`). |
| `TANZIL-LICENSE.txt` | ✅ Copiée | Attribution **juridiquement obligatoire** pour le texte coranique. Ne pas la retirer. |
| `assets/tajweed/` (122,25 Mo) | ⬜ Non copiée | Aucune référence dans le code de l'application RN : ressource orpheline, et **aucun mode ne peut la réclamer** — « Tawjeed test 2 » n'est pas une édition mais une ancienne clé (§9.3). |
| `assets/mushaf-tajweed/` (132,13 Mo) | ⬜ Non copiée | **Autorisation de redistribution absente du dépôt de référence.** Copier une ressource dont les droits ne sont pas établis n'est pas un choix technique. À trancher avec le propriétaire. De plus, le mode qui l'utiliserait (`tajweedPages`) est **inatteignable** (§9.3). |
| `assets/coran-test/` (607 polices `.woff2`, 48,88 Mo) | ⬜ Non copiée | Licence de la police non établie dans le dépôt. Sert à l'édition par défaut, rendue dans un **WebView** — voir §9.3 et §9.10. |
| `toumoun.json` | ⬜ Non copiée | Toutes les entrées sont des valeurs de remplacement (`missing_hafs_reference`) : aucune donnée exploitable. `Program.verifiedToumouns` reste donc `nil`, et le rythme « toumoun » ne propose rien plutôt que de proposer un découpage faux. |

## 9. Problèmes et points en suspens

### 9.1 Aucun compilateur Swift sur la machine de rédaction

Le dépôt a été écrit **sans Mac**. Rien ne prouve qu'un code Swift compile avant
qu'un compilateur ne l'ait vu. C'est pourquoi :

- l'intégration continue (`.github/workflows/ios.yml`) **compile réellement**,
  joue les tests et produit un IPA non signé ;
- le projet Xcode est **décrit** dans `project.yml` (XcodeGen) au lieu d'être un
  `project.pbxproj` écrit à la main — un tel fichier, non vérifiable, aurait été
  le point de fragilité le plus probable du dépôt.

**Première chose à faire :** pousser et **vérifier que le flux passe**. Les
corrections qui en découleront sont normales à ce stade.

#### Lire un échec sans jeton d'accès

Le journal d'un job n'est lisible qu'authentifié (403), mais **les annotations
d'un contrôle sont publiques** dans le HTML du job. Deux pièges, tous deux vécus :

- `GET /repos/{o}/{r}/actions/jobs/{id}` renvoie `annotations: []` **même sur un
  job en échec**. Le HTML est la source pour la cause ; l'API, seulement pour
  savoir quelle étape a échoué.
- Compter les occurrences du mot `annotation-message` **surestime** : 91
  occurrences pour 13 blocs sur un même job. Ce sont les **ouvreurs** de balise
  qu'il faut compter.

#### Les `note:` suffisent souvent à diagnostiquer

L'échec #14 ne montrait, dans ses annotations, que des lignes `note:` — pas la
ligne `error:` qui les avait produites. Cela n'a pas empêché le diagnostic, parce
que la nature de la note dit de quoi il s'agit :

| Note du compilateur | Ce qu'elle signifie |
| --- | --- |
| `add 'if #available' version check` | Le symbole existe, mais pas à partir de la cible de déploiement (ici iOS 16). C'était `CGRect: Hashable` — un `Set<CGRect>` dans un test. |
| `add @available attribute to enclosing class/method` | Même cause, vue depuis chacun des englobants : la note la plus externe désigne la portée à annoter. |

**Corollaire utile :** l'absence d'annotation sur un fichier **prouve** qu'il a
compilé. Un échec de compilation se signale toujours, donc un fichier muet est un
fichier accepté — c'est ainsi qu'on sait, sans jeton, que le reste du lot tient.

### 9.2 Contradiction entre la documentation et le code du dépôt de référence

`LECTURE_MARQUES_PAGES.md:11` affirme que **Mishary Rashid Alafasy** est le
récitateur initial. Or `src/core/audio.ts:13` définit
`defaultReciter = reciters[3]`, et `reciters[3]` est **`ar.shaatree`**
(Abu Bakr Shatri) — Alafasy est `reciters[1]`.

Cette application a suivi **le code** (donc Shatri), puisque c'est le
comportement réel des utilisateurs. **Le dépôt de référence n'a pas été
modifié**, conformément à la règle de lecture seule. À trancher par le
propriétaire : corriger la documentation, ou corriger l'index.

### 9.3 Les trois éditions non reprises

**Ce que cette section disait était faux, et c'est mesuré.** Elle annonçait que
« Tawjeed test 2 » et « Medine Test » n'avaient **aucune** ressource dans le
dépôt de référence. Ces deux noms ne sont pourtant pas des éditions : ce sont
d'**anciennes clés**, que `migrateReaderState` réécrit vers `coran_1441`
(`src/core/program.ts:60`). Elles ne sont proposées nulle part.

L'énumération `QuranEdition` porte les cinq valeurs réelles — `traditional`,
`coran_1441`, `tajweed`, `tajweedPages`, `coranTest` — et `isAvailable` n'en
déclare que **deux** lisibles : le Coran de Médine et le Coran 1441.

Les trois autres, mesurées sur le dépôt de référence :

| Édition | Ce qu'elle est | Ressources manquantes | Portable ici |
| --- | --- | --- | --- |
| `coranTest` — « Coran avec règles de Tajwid » | HTML dans un WebView (`src/coranTest/html.ts`) | 607 `.woff2` (48,88 Mo) + 606 JSON de page (4,25 Mo) | **non** : la chaîne de rendu est à écrire (`WKWebView`) |
| `tajweed` — « Lecture simplifiée » | texte arabe coloré par règle | **aucune** : `tajweed-text.json` (1,46 Mo) et `tajweed-rules.json` (2,63 Mo) sont **déjà dans ce dépôt** | oui, en natif |
| `tajweedPages` — « Moushaf Tajwid » | pages coloriées | 604 PNG (132,13 Mo) | **sans objet** : mode inatteignable |

**`tajweedPages` n'est atteignable par personne** : `migrateReaderState` le
réécrit vers `coranTest` à **chaque** chargement (`src/core/program.ts:62`). Ses
604 pages sont donc du poids mort dans le dépôt de référence — comme
`assets/tajweed` (122,25 Mo), que **rien** ne référence. Ne pas les reprendre.

**Le cas qui compte est `coranTest`** : c'est le défaut **des deux**
applications (`src/core/program.ts:57`), donc l'édition de tout utilisateur qui
n'a jamais touché au choix d'affichage. Depuis la correction décrite en §9.10, ces
utilisateurs lisent le Coran de Médine, et le lecteur le dit.

**`tajweed` est le meilleur rapport effort/résultat** : ses deux fichiers de
données sont déjà embarqués et ne sont lus par **aucun** code Swift. Il reste à
écrire le rendu du texte coloré.

### 9.4 Coran 1441 : téléchargement implémenté

La lecture **et** l'installation fonctionnent. Les pages vivent dans
`Documents/quran/coran_1441/`, sous la forme de 9 060 bandes (`001-01.png` …
`604-15.png`) plus le marqueur `ready-v1.json`.

| Fichier | Rôle |
| --- | --- |
| `Services/Coran1441Archive.swift` | Lit un ZIP sans dépendance externe : répertoire central, en-têtes locaux, méthodes 0 et 8 |
| `Services/Coran1441Install.swift` | Les règles : nom dans l'archive, bornes, nom installé, validité d'une image, marqueur |
| `Services/Coran1441DownloadService.swift` | Le déroulement : télécharger (reprisable), vérifier, extraire, exiger 9 060 images, marquer |

L'archive est celle de l'application React Native
(`https://files.quran.app/hafs/madani_1441/zips/images_1440.zip`, 102 608 011
octets) : les deux applications installent donc **les mêmes images, sous les
mêmes noms**, et peuvent se relire l'une l'autre.

Trois points méritent d'être notés.

- **La constante `COMPRESSION_ZLIB` d'Apple désigne le DEFLATE brut**, celui d'un
  ZIP, et non un flux enveloppé d'un en-tête zlib. Ce n'était pas supposable :
  deux tests s'y opposent — le flux brut doit être décodé jusqu'à une empreinte
  SHA-256 exacte, le flux enveloppé doit être **refusé**. Un aller-retour avec le
  seul framework serait vert quelle que soit sa sémantique, puisque les deux
  côtés se tromperaient ensemble.
- **Le ZIP n'est jamais chargé en mémoire.** La lecture passe par une closure :
  le service lui donne un `FileHandle`, les tests un `Data` en mémoire. C'est
  donc le code de production qui est éprouvé, et l'application ne tient jamais
  102 Mo.
- **L'extraction se fait hors du fil principal** (`Task.detached`) : 9 060
  décompressions sur le fil principal figeraient l'écran pendant toute
  l'installation, et l'application paraîtrait plantée alors qu'elle travaille.

Le fichier de reprise s'appelle `resume.bin` ici, et non `resume.json` comme dans
l'original : le contenu est le jeton binaire rendu par `URLSession`. Ce fichier
est interne à une application et n'est jamais relu par l'autre ; seuls le nom des
images et le marqueur doivent coïncider.

L'installation n'est déclarée prête qu'après les 9 060 images. Le marqueur est
écrit **en dernier**, et une interruption laisse donc un dossier qu'on peut
reprendre, jamais un dossier faussement complet.

### 9.5 Identifiant de paquet et signature

`fr.swiftdeepseek.app` est **distinct** de `fr.coranmemoire.app`. Aucune
signature Apple n'est configurée : les compilations de l'intégration continue
sont **non signées**. Voir `README.md` § « Ce qu'il reste à faire côté Apple ».

### 9.6 Notation des révisions : branchée, et testée depuis peu

**Correction d'une affirmation fausse de ce document.** Une version précédente
annonçait `Review.gradeReviewTask` « écrit et testé ». Il était écrit, mais
**aucun test ne le couvrait** — la vérification a été faite en cherchant les
appels dans `Tests/` : zéro. Cinq tests ont été ajoutés (`ReviewTests.swift`) :
le report à J+1 après « à retravailler » contre J+2 après « hésitant », la
levée du marquage difficile par « parfait », le marquage par toute autre note,
la conservation de la date prévue quand la révision est faite en avance, et la
consommation de la première consolidation due.

La notation est désormais **branchée dans le lecteur** (`ReaderView`) :

- la barre de notation n'apparaît que pour une **tâche de révision**
  (`reviewTask != nil`) et jamais pendant une consolidation — `App.tsx:476` et
  `App.tsx:511` ;
- trois notes, avec les mêmes icônes, libellés et ordre que
  `RevisionBottomActionBar.tsx:7` : `check` « Parfait », `signal` « Quelques
  hésitations », `refresh` « À retravailler », puis une barre de séparation, puis
  `play` « Écouter » ;
- pour une **consolidation**, l'action de droite devient
  « Valider la consolidation · J+n », le décalage `n` étant celui de la première
  consolidation due — `App.tsx:474` et `App.tsx:511`.

**Deux vocabulaires de notes coexistent dans l'application d'origine, et il ne
faut pas les confondre** : `perfect | hesitant | rework` pour les *tâches de
révision* (`program.ts:23`), et `perfect | hesitant | errors | relearn` pour les
*révisions de verset* (`program.ts:11`). Le lecteur utilise le premier.

Reste à faire : le cinquième bouton de l'original, « Ma voix » (`onRecord`).
L'enregistrement des récitations n'est pas implémenté côté Swift ; un bouton sans
effet aurait été pire que son absence, il n'est donc pas repris.

### 9.7 Versets difficiles : affichage rouge en place

Le marquage et le stockage (`difficultyMarkers`, `reviewPriorityDue`,
`difficultyHistory`) étaient en place et partagés ; l'affichage, lui, manquait, et
`Resources/Data/bounds.json` — 604 pages, 13 766 rectangles — **n'était lu par
aucun code Swift**. C'est fait, en trois pièces :

| Fichier | Rôle |
| --- | --- |
| `Core/VerseBounds.swift` | lit `bounds.json`, rend les rectangles en coordonnées d'image, et les projette à l'écran |
| `Features/Quran/Reader/VerseHighlightView.swift` | dessine les rectangles et l'icône de signet |
| `Features/Quran/Reader/MushafPageViewController.swift` | porte la vue de mise en évidence, par-dessus l'image |

Sont repris de `MushafPage.tsx:51-52` : le rouge `#E85B5B` du verset difficile
(opacité 0,18), le vert du signet (0,18), la surbrillance du verset en lecture
(0,42), les coins arrondis à 4, et l'icône de signet sur le bord droit.

**Deux points de vigilance, tous deux couverts par des tests :**

1. **L'ordre des colonnes de `bounds.json` est `x1, x2, y1, y2`** — et non
   `x1, y1, x2, y2`. Lu dans le mauvais ordre, 6 425 lignes sur 13 766 ont une
   taille négative : elles seraient écartées en silence, et le défaut
   ressemblerait à une erreur de projection.
2. **La projection tient compte des bandes vides de `scaleAspectFit`.** Utiliser
   la boîte de la vue au lieu de la boîte de l'image dessinée décale la mise en
   évidence vers le haut — d'environ 400 pt sur une vue 1200 × 3000.

Les **repères de progression de séance** dans la marge ne figurent plus dans cette
liste : ils sont portés, voir §9.12. Ce qui reste ici est ce que
`VerseHighlightView` ne fait toujours pas — les libellés d'accessibilité **par
verset mis en évidence** : l'image de page est un élément d'accessibilité unique,
donc ses sous-vues sont ignorées. La marge, elle, expose désormais un élément par
pastille.

### 9.8 Objets observables imbriqués : un défaut silencieux, corrigé

`AppViewModel` expose `audio`, `sync` et `connectivity` comme des objets
observables **séparés** de lui-même. SwiftUI ne réévalue une vue que pour les
objets qu'elle observe : une vue qui lit `model.audio.isPlaying` s'affichait donc
correctement une fois, puis **ne se mettait plus jamais à jour**. Le bouton
lecture/pause du mini-lecteur restait figé, et la mise en évidence du verset en
cours de récitation ne pouvait pas suivre.

Corrigé dans `AppViewModel.init` : les trois `objectWillChange` sont relayés vers
celui du modèle. Un test le verrouille (`Tests/AppWiringTests.swift`), et il est
falsifiable — retirer le relais le fait échouer.

Le défaut mérite d'être noté parce qu'il est **invisible** : l'écran s'affiche, la
compilation est verte, rien ne signale l'absence de mise à jour. La règle à
retenir : tout service observable exposé par le modèle doit être relayé.

### 9.9 Poids des ressources

Le paquet embarque **121,51 Mo** de ressources, mesurés : **112,73 Mo** pour les
604 pages du Coran de Médine et **8,78 Mo** pour 15 fichiers JSON. C'est le
prix de la lecture hors ligne immédiate : aucune première ouverture n'attend un
téléchargement.

**Cinq de ces JSON ne sont lus par aucun code Swift**, et ils n'ont pas tous la
même raison :

| Fichier | Lu par l'original ? | Pourquoi il est là |
| --- | --- | --- |
| `tajweed-text.json`, `tajweed-rules.json` | oui, mode `tajweed` | serviraient à l'édition « Lecture simplifiée » (§9.3) |
| `mushaf-tajweed-bounds.json`, `mushaf-tajweed-dimensions.json` | oui, mode `tajweedPages` | mode **inatteignable** (§9.3) |
| `coran_1441-headers.json` | **non, par personne** | poids mort |

`coran_1441-markers.json` n'est plus dans cette liste : il est lu depuis §9.11.

Si la taille devient un problème, la
voie est de télécharger aussi le Coran de Médine, comme le Coran 1441 — au prix
d'une première ouverture sans image.

### 9.10 Le lecteur ouvrait sur une édition qu'il ne sait pas rendre

**Le défaut.** `defaultState()` enregistre `reader.mushaf == "coranTest"`
(`Core/Program.swift:94`, d'après `src/core/program.ts:57`) — la valeur par défaut
de l'application d'origine, donc celle de **tout** utilisateur qui n'a jamais
touché au choix d'affichage. Or `coranTest` n'est pas rendu par une image :
l'original le dessine dans une page HTML chargée dans un WebView
(`src/coranTest/html.ts`), avec 607 polices `.woff2`.

`AppViewModel.edition` résolvait la préférence telle quelle. Le lecteur s'ouvrait
donc sur une édition dont `imageURLs` rend une liste **vide**, et
`MushafPageViewController.load()` affichait « Cette page n'est pas encore
disponible hors ligne » — sur **chaque** page, pour **tout** utilisateur, dès la
première ouverture. Le message était de surcroît faux : il annonçait la page
comme indisponible alors que c'est l'édition qui n'est pas rendue.

Aucun test ne couvrait la résolution de l'édition. Le défaut n'avait donc rien
pour le signaler, et un lecteur muet ne se distingue pas d'un lecteur qui marche.

**La correction.** `QuranEdition.displayed(stored:)` rend l'édition **affichée**,
qui est toujours lisible, et `ReaderView` dit laquelle il substitue. La
préférence enregistrée n'est **pas** réécrite : elle reste `coranTest` dans le
document synchronisé, donc l'application React Native retrouve son édition de
Tajwid.

**Ce que la correction ne casse pas.** `ReaderView.toggleBookmark` enregistre
`source: edition.rawValue`, et `Bookmark.save` écrit `sourcePages[source] = page` :
la clé et la valeur doivent désigner **la même édition**. Avant la correction,
l'application écrivait `sourcePages["coranTest"] = <page du Coran de Médine>` — un
numéro de page venu d'une autre édition. C'était **cela**, la divergence de
données ; le repli écrit `sourcePages["traditional"] = <page du Coran de Médine>`,
soit exactement ce que l'application React Native écrit quand l'utilisateur
regarde le Coran de Médine.

**Une imprécision mesurée, qui reste.** `reader.testPage` continue d'être écrit
quand la préférence vaut `coranTest` (`AppViewModel.recordReading`, comme
`App.tsx:212`), et ce numéro vient de `Quran.pageOf`, donc de la pagination du
Coran de Médine. Les deux paginations **ne coïncident pas partout** : sur 604
pages, **568** portent le même intervalle de versets et **36** en diffèrent d'une
frontière (page 120 : `740` à `746` contre `740` à `745`). Le repère de reprise de
l'édition de Tajwid peut donc tomber une page à côté — ce n'est pas une
régression, l'application écrivait déjà cette valeur, mais c'est mesuré.

**L'épreuve.** `Tests/QuranEditionTests.swift` (10 tests) fixe l'invariant qui
manquait — quelle que soit la préférence enregistrée, l'édition affichée est
lisible, sait où sont ses versets, et rend des pages — et montre la cause plutôt
que de la raconter : `imageURLs(for: .coranTest, page: 1)` est vide.

**Ce que la compilation a appris.** La correction est passée une fois par une
erreur de compilation, et le message ne parlait pas de l'intention : sur une
chaîne, `reader?.mushaf.flatMap { … }` résout `flatMap` sur `Sequence` — celle des
`Character` — et non sur `Optional`. Le compilateur refusait un `Character` reçu
là où un `String` était attendu. Écrit en deux temps (`guard let`, puis
`QuranEdition(rawValue:)`), la même intention passe. Aucun contrôle local ne
pouvait l'attraper : `scripts/verifier-flux.mjs` vérifie le flux, pas le Swift.

### 9.11 Les pastilles de numéro de verset du Coran 1441 — implémentées

`Resources/Data/coran_1441-markers.json` était embarqué — **6 236** marqueurs, un
par verset, sur les **604** pages — et **aucun code Swift ne le lisait**. Le
lecteur affichait donc les quinze bandes du Coran 1441 sans aucun repère de
verset : lisible, mais muet.

L'original s'en sert dans la branche `coran_1441` (`MushafPage.tsx:4` pour
l'import, `:49` pour le rendu) : pour chaque verset, une pastille de fond
`#ECFDF5`, de bordure `#047857`, portant le numéro du verset en chiffres arabes
orientaux (`٠١٢٣٤٥٦٧٨٩`), posée au début du verset.

**Format, mesuré.** `{ "<page>": [[sourate, verset, ligne, x, y], …] }`. La
`ligne` est **0-basée** (`0` à `14`) — la convention des bandes du 1441, et non
celle, 1-basée, de `bounds.json` ; `x` est une fraction de la largeur de page
(`0,042` à `0,892`) et `y` une fraction de la hauteur de **bande** (`0,435` à
`0,669`). Les deux dénominateurs ne sont pas les mêmes, et rien ne le signale à la
lecture. Fichier vérifié à l'octet près contre
`src/data/quran-tests/coran_1441-markers.json` : **200 110** octets, md5
`552b038299ae128131ffbe8d94cd7704`.

**Où c'est écrit.** `Core/VerseMarkers.swift` porte le modèle, le chargement
paresseux et la géométrie ; `Features/Quran/Reader/VerseMedallionView.swift`
dessine ; `MushafPageViewController` ajoute la couche **avant** les mises en
évidence, comme l'original place les pastilles dans le conteneur des bandes.

**Le point qui évite la dérive.** La boîte d'une pastille passe par
`VerseBounds.bandRect` — la **même** fonction qui place les quinze bandes. La
pastille est donc solidaire de la bande qu'elle annote, et les deux ne peuvent pas
diverger. C'est aussi ce qui la rend juste quand la vue n'a pas le ratio de la
page : la formule de l'original (`(height - width * 232 / 1440) / 14 * line`)
suppose ce ratio, et dérive sinon.

**Les mesures reprises.** Diamètre `largeur × 0,05`, bordure `× 0,003`, police
`× 0,025` — trois fractions de la **largeur de page**, calculées depuis la taille
réelle de la vue pour que la pastille suive la rotation et le mini-lecteur.
**Non repris** : le resserrement de ligne (`lineHeight: diameter * .8`,
`includeFontPadding: false`), qui est un réglage de mise en page de React Native
sans équivalent ici ; le glyphe est centré sur sa propre boîte.

**La source compte.** `markers(page:source:)` rend une liste vide pour toute
source autre que le 1441. Ces fractions se rapportent à la page du 1441 et leur
`ligne` est l'indice d'une de ses quinze bandes : les projeter sur une page du
Coran de Médine donnerait des pastilles à des endroits **plausibles** sur une
image qui n'est pas la même — ce qui est pire que rien.

**L'épreuve.** `Tests/VerseMarkersTests.swift` (12 tests) fixe la couverture
(**604** pages, **6 236** marqueurs, 7 sur la page 1, 15 sur la 604), l'ordre des
colonnes, la convention 0-basée vérifiée sur **tout** le fichier, la conversion
des chiffres comparée à l'expression de l'original, deux boîtes mesurées hors du
dépôt, et l'invariant « chaque pastille est dans sa bande » vérifié sur les
**6 236** marqueurs, dans une vue dont le ratio **diffère** de celui de la page.

**Une limite connue.** Le centrage vertical du chiffre se fait sur la boîte du
glyphe, alors que l'original resserre la hauteur de ligne. Les deux donnent le
même résultat à l'œil ; aucun test ne peut le trancher, faute de pouvoir dessiner
sur cette machine.

### 9.12 Les repères de progression de séance dans la marge — implémentés

C'était le dernier repère de `MushafPage.tsx` qui manquait. Quand une séance est
ouverte — apprentissage ou révision — l'original affiche, dans la marge gauche de
la page, un rail vertical et une pastille par **ligne** de la page, portant le ou
les numéros de verset de cette ligne. Une pastille pleine marque une ligne dont
tous les versets sont validés, une pastille creuse une ligne qui reste à faire.

Ce n'était pas un manque de données : `StudyProgress.through` existait déjà
(`Core/AppState.swift`), `Program.studyKey(_:_:)` aussi, et `ReaderRequest`
portait déjà `range` et `sessionID`. Ce qui manquait était la **dérivation** qui
les relie (`App.tsx:477-481`) et la géométrie.

**Trois règles silencieuses de `marginAnnotations.ts`**, reproduites à la lettre :

1. **Un verset à cheval sur deux lignes n'est retenu qu'une fois**, sur sa
   première ligne dans l'ordre (ligne, puis `y`). Prendre la seconde place le
   numéro une ligne trop bas.
2. **`bottom` se calcule sur TOUTES les régions du verset**, pas seulement sur
   la ligne retenue. Mesuré sur la page 1 du 1441 : le groupe « 5·6 » tient la
   ligne à `y = 0,514286` d'une hauteur de `0,1`, donc `y + height = 0,614286` —
   mais le verset 6 continue, et le rail va jusqu'à `0,678571`. Lire `bottom` sur
   le seul groupe retenu raccourcirait le rail sans lever la moindre erreur.
3. **Le tri des groupes est rendu stable.** `Array.prototype.sort` est stable
   depuis ES2019, `Array.sorted` ne l'est pas : à `y` égal, deux lignes
   pourraient s'ordonner autrement qu'en React Native. Le départage se fait par
   l'ordre d'apparition.

**Où c'est écrit.** `Core/MarginAnnotations.swift` porte le regroupement, la
géométrie et la dérivation de la séance ;
`Features/Quran/Reader/VerseMarginView.swift` dessine ; `MushafPageViewController`
ajoute la couche **en dernier**, donc au-dessus des mises en évidence — l'original
la place après `</Pressable>`.

**La vue se trace dans la vue ENTIÈRE, et non dans la boîte de page.** C'est la
différence avec `VerseHighlightView`, et elle est nécessaire : le diamètre d'une
pastille vaut `min(24, max(8, bordGaucheDeLaPage - 4))`, donc il dépend de la
place libre **à gauche** de la page. Une vue posée sur la boîte de page aurait
perdu cette place et le diamètre serait faux.

**Une seule différence de forme avec l'original, et elle est vérifiée.** L'original
calcule `edge` dans le repère de sa `Pressable` — qui commence à `marginGutter`
dans la vue — puis ajoute `marginGutter` pour obtenir le diamètre. Ici la boîte de
page est déjà mesurée dans la vue entière, donc `marginGutter` est **contenu** dans
`pageBox.minX` et disparaît de la formule. `_banc/oracle-margin.mjs` charge le
**vrai** `src/core/marginAnnotations.ts` du dépôt de référence — en retirant
mécaniquement ses annotations de type — et le fait tourner sur les vrais fichiers
de rectangles, page par page ; il compare ensuite les deux formulations à trois
valeurs de `marginGutter` près, dont deux qui donnent des diamètres **différents**
(`16,9`, `18,9`, `24` sur la page 1 du 1441). Neuf comparaisons, zéro écart : les
six de l'équivalence des formulations, plus les **trois bornes du diamètre** que le
test fige — le banc mesure désormais les cas exacts du fichier de tests, et non des
cas approchants. C'est précisément l'écart entre les deux qui avait laissé passer un
diamètre de `20` là où le test devait lire `16,4`.

**La dérivation de la séance, et ses trois points exacts** (`App.tsx:477-481`) :

- en **apprentissage**, la séance **enregistrée** prime sur la plage demandée. Le
  lecteur peut être ouvert sur une plage rétrécie — « Reprendre au verset N » —
  alors que l'original affiche la plage entière de la séance ;
- la **clé de suivi dépend du mode** : `learning:<id>` ou `revision:<id>`. La
  fabriquer à la main une fois de travers rend le suivi invisible ;
- **`through` retombe sur `start - 1`** quand aucun suivi n'existe : aucun verset
  n'est marqué fait, ce qui est le bon défaut pour une séance jamais ouverte.

**L'épreuve.** `Tests/MarginAnnotationsTests.swift` (27 tests) fige les nombres
mesurés par l'oracle : le regroupement (7 versets → 5 pastilles, « 3·4 » et
« 5·6 »), les trois règles ci-dessus, les positions du rail et des pastilles sur
un téléphone de 390 × 700 pour les **deux** éditions, la même chose sur une vue
1200 × 3000 dont le ratio **n'est pas** celui de la page, les bornes du diamètre
(8 et 24, plus une valeur intermédiaire), la croissance vers le bas d'un libellé
replié, et les sept cas de la dérivation de la séance. La couverture est
vérifiée page par page : **604** pages par édition, **13 273** et **13 766**
régions, aucune page vide, **aucune ligne écartée**.

**Une limite connue, et elle n'est pas dans ce code.** Sur une page du Coran 1441,
`MushafPageViewController` fait de la vue de page entière un élément
d'accessibilité, donc les enfants ne sont pas parcourus et les pastilles de
séance ne sont pas atteignables au lecteur d'écran. Le défaut vaut aussi pour les
mises en évidence et les pastilles de numéro ; il est antérieur à ce travail. Sur
le Coran de Médine, l'élément est l'image et non le conteneur, donc ces pastilles
*devraient* être parcourues — cela n'a pas été vérifié sur un appareil.

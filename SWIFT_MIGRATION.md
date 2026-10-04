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
| Lecteur « Coran 1441 » | ✅ | 🟡 | — | `Services/QuranSourceService.swift` | Lit les pages si elles sont présentes ; **le téléchargement n'est pas encore implémenté**. |
| Pagination native au doigt | ✅ | ✅ | — | `MushafPageViewController.swift` | `UIPageViewController`, comme prévu. |
| Préchargement page précédente / courante / suivante | ✅ | ✅ | — | `MushafPageViewController.swift` | Trois pages, jamais 604. Cache LRU. |
| Centrage vertical sans marge fixe | ✅ | ✅ | — | `ReaderView.swift`, `MushafPageViewController.swift` | Zone de page = tout l'espace restant, `scaleAspectFit`, contraintes centrées. Aucun `marginTop`. |
| Reprise à la dernière page lue | ✅ | ✅ | `user_state.lastRead` | `Features/Home/HomeView.swift`, `ViewModels/AppViewModel.swift` | |
| Marque-pages | ✅ | 🟡 | `user_state.bookmarks` | `Core/Bookmark.swift` | Poser/retirer dans le lecteur et lister dans l'onglet Coran : fait. Fusion : faite. |
| Choix de l'édition | ✅ | ✅ | `user_state.reader.mushaf` | `Features/Quran/Reader/ReaderView.swift` | « Tawjeed test 2 » et « Medine Test » : voir §7. |
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
| `Resources/Mushaf/` (604 PNG, 114 Mo) | ✅ Copiée | Coran de Médine, dossier conservé tel quel (le lecteur les cherche dans `Mushaf/`). |
| `TANZIL-LICENSE.txt` | ✅ Copiée | Attribution **juridiquement obligatoire** pour le texte coranique. Ne pas la retirer. |
| `assets/tajweed/` (124 Mo) | ⬜ Non copiée | Aucune référence dans le code de l'application RN : ressource orpheline. À réévaluer si « Tawjeed test 2 » la réclame. |
| `assets/mushaf-tajweed/` | ⬜ Non copiée | **Autorisation de redistribution absente du dépôt de référence.** Copier une ressource dont les droits ne sont pas établis n'est pas un choix technique. À trancher avec le propriétaire. |
| `assets/coran-test/` (police) | ⬜ Non copiée | Licence de la police non établie dans le dépôt. |
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

### 9.3 « Tawjeed test 2 » et « Medine Test »

Ces deux sources ne sont **pas** dans le dépôt de référence. L'énumération
`QuranEdition` est prête à les accueillir, mais aucune ressource ne correspond
aujourd'hui. Rien n'a été inventé.

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

Reste à faire : les **repères de progression de séance** dans la marge
(`MushafPage.tsx:53`, `marginAnnotations`), qui dépendent du suivi de séance
(`sessionThrough`) — non porté. Et les libellés d'accessibilité par verset mis en
évidence : l'image de page est un élément d'accessibilité unique, ses sous-vues
sont donc ignorées.

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

Le paquet embarque environ **123 Mo** de ressources (604 pages + JSON). C'est le
prix de la lecture hors ligne immédiate. Si la taille devient un problème, la
voie est de télécharger aussi le Coran de Médine, comme le Coran 1441 — au prix
d'une première ouverture sans image.

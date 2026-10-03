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

### 9.4 Coran 1441 : téléchargement non implémenté

La lecture fonctionne si les pages sont présentes sur l'appareil
(`Documents/quran/coran_1441/`). Le téléchargement de l'archive
(`https://files.quran.app/hafs/madani_1441/zips/images_1440.zip`), la reprise
après interruption et l'extraction restent à faire — l'URL de la source est
relevée dans `QuranSourceService.coran1441ArchiveURL`.

### 9.5 Identifiant de paquet et signature

`fr.swiftdeepseek.app` est **distinct** de `fr.coranmemoire.app`. Aucune
signature Apple n'est configurée : les compilations de l'intégration continue
sont **non signées**. Voir `README.md` § « Ce qu'il reste à faire côté Apple ».

### 9.6 Notation des révisions non branchée

`Review.gradeReviewTask` est écrit et testé, et la demande d'ouverture du lecteur
porte bien `reviewTask` et `consolidation`. Mais l'écran qui permet de choisir
« parfait / hésitant / erreurs / à réapprendre » n'existe pas encore : depuis le
lecteur, une séance d'apprentissage se termine (`completeSession`), une tâche de
révision ne se note pas encore.

### 9.7 Versets difficiles : affichage rouge à faire

Le marquage et le stockage (`difficultyMarkers`, `reviewPriorityDue`,
`difficultyHistory`) sont en place et partagés. L'affichage en rouge léger dans
le lecteur — apprentissage, révision, consolidation — reste à faire.

### 9.8 Poids des ressources

Le paquet embarque environ **123 Mo** de ressources (604 pages + JSON). C'est le
prix de la lecture hors ligne immédiate. Si la taille devient un problème, la
voie est de télécharger aussi le Coran de Médine, comme le Coran 1441 — au prix
d'une première ouverture sans image.

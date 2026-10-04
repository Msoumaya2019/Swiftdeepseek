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
| Écran de choix de l'apparence | ✅ | ✅ | `user_state.theme`, `.accent` | `Core/AppearanceOptions.swift`, `Theme/Theme.swift`, `Features/Settings/AppearanceView.swift` | Le thème ET l'accent sont modifiables — §9.19. La section « Police de l'interface » de l'original n'est **pas** portée : elle écrirait un réglage que rien ne lit ici (voir §9.19). |

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
| Mini-lecteur persistant | ✅ | ⬜ | — | `Features/Quran/Reader/ReaderView.swift` | La barre audio du lecteur existe (`audioBar` : lecture/pause, récitateur, verset courant, et l'accès aux réglages de §9.16). Il manque le **mini-lecteur global** — celui qui survit au changement d'onglet. |
| Répétition (passage / verset, nombre, silence, vitesse) | ✅ | ✅ | — | `Core/PassageAudio.swift`, `Core/AudioRepeatPreferences.swift`, `Core/PassageAudioEngine.swift`, `Services/PassageAudioExecutor.swift`, `Core/ChapterAudioCache.swift`, `Features/Quran/AudioRepeatSettingsView.swift`, `ViewModels/AppViewModel.swift`, `Storage/LocalStore.swift` | Le **moteur**, les **six réglages**, la **machine d'état**, l'**écran** et l'**exécuteur AVFoundation** sont portés, et la boucle est branchée de bout en bout — `_banc/oracle-audio.mjs`, `_banc/oracle-engine.mjs`, `_banc/verifier-ecran-audio.mjs` et `_banc/verifier-executeur-audio.mjs`. Ce qui reste n'est **pas du code** : l'éprouver **sur un appareil** — reprise sans coupure audible entre deux versets d'une même piste, coupure avant le mot suivant, session audio en arrière-plan. Réglages **locaux**, écrits par `AppViewModel`, voir §9.13 à §9.17 et `LOCAL_DATA_MIGRATION.md` §4 a). |
| Lecture d'une sourate entière (fichier complet + horodatages) | ✅ | ✅ | — | `Core/PassageAudio.swift`, `Services/PassageAudioExecutor.swift`, `Core/ChapterAudioCache.swift`, `Storage/LocalStore.swift` | La chronologie est demandée à quran.com, **validée** (`isUsableCachedChapter`) puis gardée sur disque ; un échec n'est pas redemandé pendant cinq minutes, et une seule requête est en vol par sourate. Un récitateur sans identifiant de sourate retombe sur les fichiers par verset, comme dans l'original. |
| Cache audio des versets | ✅ | ✅ | — | `Services/AudioService.swift` | `VerseAudioCache` écrit sur **disque** (`.cachesDirectory`), avec téléchargement dans un fichier temporaire puis déplacement — et non « en mémoire », comme l'annonçait une version précédente de ce tableau. |

## 5. Programme, apprentissage, révisions

| Fonctionnalité | État RN | État Swift | Tables Supabase | Fichiers Swift | Problèmes |
|---|---|---|---|---|---|
| Génération du programme selon l'objectif | ✅ | ✅ | `user_state.sessions` | `Core/Program.swift` | |
| Séance du jour, reprise possible | ✅ | ✅ | `user_state.sessions`, `.studyProgress` | `Features/Program/ProgramView.swift` | Clé `learning:<id>` via `Program.studyKey`. |
| Une séance faite en avance ne change pas sa date prévue | ✅ | ✅ | `user_state.sessions` | `Core/Program.swift` | Couvert par `Tests/ProgramTests.swift`. |
| Séances en retard (« À rattraper ») | ✅ | ✅ | `user_state.sessions` | `Features/Program/ProgramView.swift` | |
| Historique des séances | ✅ | ✅ | `user_state.sessions` | `Features/Program/ProgramView.swift` | 20 dernières, terminées ou reportées. |
| Objectif et rythme | ✅ | ✅ | `user_state.goal`, `.pace` | `Core/ProgramGoal.swift`, `Features/Settings/ProgramEditorView.swift`, `Features/Settings/SettingsView.swift` | Affiché **et modifiable** : unité + index (« Finir le Juz’ 12 »), rythme par groupe, échéance, aperçu du programme. Voir §9.18. |
| Assistant de choix d'objectif | ✅ | 🟡 | `user_state.goal` | `Core/ProgramGoal.swift`, `Features/Settings/ProgramEditorView.swift` | Les étapes **objectif / rythme / jours** sont portées (`AdvancedProgramView`) : objectifs préréglés filtrés par `goalIsAlreadyKnown`, objectif personnalisé validé par `validGoal`, et les jours d'apprentissage. Ce qui manque est l'**entrée** de l'assistant — l'écran d'accueil (`step === -1`) qui demande le sexe et le prénom, et le drapeau `onboardingDone` qui en dépend. |
| Versets connus / à revoir (marquage manuel) | ✅ | ✅ | `user_state.knowledge` | `Core/ProgramGoal.swift`, `Features/Settings/KnowledgeEditorView.swift` | Interface faite : passages partiels (ajout et retrait), sourates, juz’, hizb. `markKnowledge` et `toggleKnownRange` étaient déjà écrits ; voir §9.18. |
| Cycles de révision 7 / 14 / 21 / 30 jours | ✅ | ✅ | `user_state.reviewSettings`, `.reviewCycle` | `Core/Review.swift` | Changer de durée conserve l'historique. |
| Quantités : 1 Nisf / 1 Hizb / 1 Juz / 2 Juz | ✅ | ✅ | `user_state.reviewSettings.dailyQuantity` | `Core/Review.swift` | |
| Consolidations J+1 / J+3 / J+7 | ✅ | ✅ | `user_state.reviewConsolidations` | `Core/Review.swift` | Échéances ancrées à la date d'apprentissage, même si la consolidation est faite en avance. |
| Tableau de bord des révisions | ✅ | ✅ | `user_state.reviewCycle`, `.reviewHistory` | `Features/Review/ReviewDashboardView.swift` | |
| Versets difficiles (rouge léger) | ✅ | ✅ | `user_state.difficultyMarkers`, `.reviewPriorityDue` | `Core/Review.swift`, `Core/VerseBounds.swift`, `Features/Quran/Reader/VerseHighlightView.swift` | Marquer, démarquer, lister, **et l'affichage rouge dans le lecteur** — voir §9.7. |
| Notation d'une tâche de révision | ✅ | ✅ | `user_state.reviewHistory` | `Core/Review.swift`, `Features/Quran/Reader/ReaderView.swift` | `gradeReviewTask` est écrit, testé, et **branché dans le lecteur** — voir §9.6. La demande d'ouverture porte déjà `reviewTask` et `consolidation`. |
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

### 9.13 Le moteur de répétition audio — porté, et éprouvé hors de l'application

C'étaient les deux dernières lignes ⬜ de la section 4. `src/core/audio.ts` tient la
répétition d'un passage dans une fonction de **quinze lignes**
(`nextAudioPosition`), et la lecture d'une sourate entière dans un parseur
d'horodatages de trente lignes. Aucune des deux ne demande AVFoundation : ce sont
des **décisions**, et c'est ce qui les rend portables et éprouvables sans Mac.

**Trois règles silencieuses**, et s'y tromper ne lève aucune erreur — cela répète
seulement un passage une fois de trop, ou l'arrête une fois trop tôt :

1. **Le nombre de répétitions est normalisé AILLEURS.** `PassageAudioPlayer.tsx:79`
   le ramène à `'continuous'`, ou à un entier strictement positif, ou à `1`. Le
   `Math.max(1, Math.floor(count))` de `nextAudioPosition` est donc **inatteignable
   depuis l'application** : il ne protège que l'appel direct. Les deux sont portés —
   la normalisation comme fonction (`normalizedCount`), le plancher comme garde.
2. **En mode « passage », avancer d'un verset CONSERVE le compteur.** Une répétition
   compte donc des **passages entiers**, pas des versets. À la position `{v1, r2}`
   sur la plage `1…3`, le suivant est `{v2, r2}` — et non `{v2, r1}`.
3. **En mode « verset par verset », `count == .continuous` ne fait JAMAIS avancer le
   verset.** `{v2, r40}` donne `{v2, r41}`, indéfiniment.

**Et une quatrième, hors du même fichier.** L'attente avant de rejouer
(`PassageAudioPlayer.tsx:194-196`) fait de la marge technique de 200 ms un
**plancher**, et le silence choisi par l'utilisateur ne s'y ajoute que sur un
**redémarrage** de passage (`next.verseID == range.start && current.verseID ==
range.end`) ou sur un **verset répété** (`each-verse` et `next.repetition >
current.repetition`). Entre deux versets qui s'enchaînent, l'attente reste à
200 ms — quel que soit le silence demandé. C'est le point qu'on ne devine pas :
avec un silence de 10 s, on lit `200` ms sur un enchaînement et `10 000` ms sur un
redémarrage.

**Où c'est écrit.** `Core/PassageAudio.swift` — la partie pure, sans AVFoundation.
Il porte `range`, `normalizedCount`, `next`, `waitMilliseconds`, `parse`,
`continuous`, `isUsableCachedChapter`, `label` et `chapterResourceID`. Le type
`RepeatCount` **restreint à l'entier** ce que l'original accepte en `number` :
puisque `normalizedCount` rend cet espace inatteignable depuis l'interface, un type
qui ne peut pas porter une valeur impossible vaut mieux qu'une garde qu'on peut
oublier.

**Deux divergences, mesurées et voulues.**

| Cas | L'original | Le portage | Pourquoi |
| --- | --- | --- | --- |
| Clé de verset **fractionnaire** (`'1:1.5'`) | **accepté** — `Number('1.5')` vaut 1,5, `verseId(1, 1.5)` rend 1,5, et la clé `1.5` compte comme un verset | refusé, `Timestamps audio invalides.` | Le type est `Int` : un verset fractionnaire ne désigne rien. L'original produit un fichier dont une entrée n'est joignable par aucun verset. |
| Libellé **hors bornes** (`label(6237)`) | `sourate undefined, verset undefined` | `nil` | Un libellé qui ment est pire qu'un libellé absent. |

**L'épreuve, et pourquoi elle ne se contente pas d'un banc vert.** Les 22 tests de
`Tests/PassageAudioTests.swift` ne tirent aucun nombre de la tête.
`_banc/oracle-audio.mjs` ne réécrit pas l'original : il l'**empaquette** avec
`esbuild` — résolution des imports comprise, `quran.ts` et les fichiers JSON
inclus — et il le fait tourner. C'est plus solide que le retrait mécanique des
annotations de type : il n'y a plus aucune transformation à garder juste. Le banc
compare ensuite, cas par cas, la formulation du portage à celle de l'original :
**560** cas pour la table de décision, **96** pour l'attente, **90** pour l'avance
d'affichage, plus l'acceptation et les **treize** refus du parseur, les **huit**
plages et les **sept** cas de validité du cache. Les deux règles qui vivent hors de
`core/audio.ts` sont extraites **textuellement** du TSX, avec un garde-fou qui
refuse de compter si la forme change.

**Le banc est relié au portage par un contrôle explicite.** La table de décision
compare une *translittération* du Swift à l'original : si la translittération se
trompait **comme** le Swift, le banc serait vert et ne prouverait rien — les deux
sources ne peuvent pas se lire l'une l'autre. Le banc vérifie donc que les **28
lignes décisives** du portage s'y trouvent, **et dans l'ordre**, réparties en six
fonctions. Un réordonnancement des branches est vu.

**Et le banc est falsifié, sans quoi son vert ne voudrait rien dire.**
`_banc/falsifier-audio.mjs` le fait rougir sur **neuf mutations** — cinq du Swift
(la conservation de la répétition, le cas `continuous`, le facteur 1000 de
l'attente, le plancher de 200 ms, un message de refus) et trois de sa
translittération — plus un témoin non muté qui doit rester vert. Il prouve la
restauration par **empreinte SHA-256**, relevée avant et après. Une première
version du banc laissait passer la mutation de la borne de plage : ses cas ne
distinguaient pas « le verset suivant manque » de « la plage est finie ». Une
troisième chronologie, **plus large que la plage**, a été ajoutée pour les séparer.

**Ce qui reste, et qui n'est pas dans ce fichier.** L'écran de réglages (nombre,
mode, silence, vitesse, arrêt automatique) et la boucle AVFoundation qui consomme
ces décisions. Les préférences restent **locales** : `LOCAL_DATA_MIGRATION.md` §4 a)
a tranché « ne rien faire », donc aucune clé n'est ajoutée à `user_state` et les
deux applications ne partagent pas ces réglages.

### 9.14 Les six réglages de répétition — ce qui est stocké n'est pas ce qui décide

Le moteur de 9.13 reçoit un nombre de répétitions. Ce nombre ne vient pas de ce que
l'utilisateur voit : il vient de `PassageAudioPlayer.tsx:78-79`, qui le **dérive** de
six réglages persistés sous `audio-repeat-preferences`. Cette dérivation tient en
deux lignes, et trois de ses règles sont silencieuses.

1. **`Number(customCount)` est le `Number()` de JavaScript**, pas un entier Swift.
   `'0x10'` vaut 16, `'1e3'` vaut 1000, `'.5'` vaut 0,5, `'1.e3'` vaut 1000, `''`
   vaut **0**, `'1,5'` ne vaut rien. Et tout ce qui n'est pas un entier strictement
   positif retombe sur **1**, sans erreur. Le champ est un pavé numérique, mais le
   fichier relu, lui, n'est pas forcément ce que le pavé produit.
2. **Le nombre normalisé n'est pas le nombre validé.** `:79` accepte tout entier
   strictement positif ; `:176` refuse de **lancer** au-delà de 999. Un « Autre » de
   `5000` produit donc les deux à la fois : un compte de 5000 dans les réglages, et
   un refus de lancement. Un « Autre » de `1.5` est ramené à 1 **et** refusé.
3. **La validation au chargement est champ par champ, en égalité stricte.** `"3"`
   n'est pas `3`, `4` n'est pas dans la liste, et un champ invalide garde sa valeur
   par défaut **sans invalider les autres**. Un document qui n'est pas un objet —
   `null`, un nombre, une chaîne, un tableau — rend les six défauts : l'original y
   lit `prefs.countChoice`, qui vaut `undefined`, ce que `counts.includes` refuse.

**Ce qui est stocké n'est pas ce qui est affiché.** `autoStop` reste **vrai** quand
on choisit « en continu » ; c'est la case qui se **décoche** (`:248`, `:268` :
`selected={autoStop&&countChoice!=='continuous'}`). Et le dénominateur `∞` apparaît
pour **deux causes distinctes** (`:256`, `:258` : `countChoice==='continuous'||!autoStop`)
— « en continu », ou l'arrêt automatique décoché — alors que la pastille de cycle
rapide (`:241`) ne regarde que le compte. Trois expressions voisines, trois règles
différentes. Ne jamais réécrire le réglage pour se simplifier l'affichage.

**Une quatrième règle, dans le cycle rapide.** `:241` cycle sur
`[1,2,3,5,10,'continuous']` — **six** valeurs, alors que la liste des pastilles en
compte **sept** : « Autre » en est absent. Et un compte **hors liste** — un « Autre »
de 4, de 20 ou de 5000 — donne `indexOf` = -1, donc `(0)%6` = 0, donc **1**. Ce n'est
pas devinable, et c'est mesuré.

**Où c'est écrit.** `Core/AudioRepeatPreferences.swift` pour la partie pure
(`jsNumber`, `count`, `launchError`, `decode`, `encoded`, les trois expressions
d'affichage, le cycle rapide), et `Storage/LocalStore.swift` pour le fichier
`audio-repeat-preferences.json` — même forme que l'original, mêmes six clés, mais
**local** : rien n'entre dans `user_state` (voir `LOCAL_DATA_MIGRATION.md` §4 a).
Un fichier absent, illisible ou corrompu rend les défauts, jamais une erreur.

**Trois divergences, mesurées et déclarées.**

| Cas | L'original | Le portage | Pourquoi |
| --- | --- | --- | --- |
| `customCount` dont la valeur dépasse **2^53** | compte de cette valeur | compte de 1 | Un `Double` ne porte plus les entiers un à un au-delà, donc `Int` ne peut pas les recevoir. Le **lancement est refusé des deux côtés**, donc aucune lecture ne démarre avec ce compte. `2^53` lui-même est encore exact, et accepté. |
| `1e999` et `1e-999` : la valeur **brute** | `Infinity`, `0` | dépend de `Double(_:)` | Le banc ne peut pas exercer le débordement de Foundation. Le **compte** est le même dans les trois cas (infini, zéro ou `nil`) : c'est donc la seule chose que le test y affirme. |

**L'épreuve.** La section 13 de `_banc/oracle-audio.mjs` extrait **textuellement** du
TSX la liste des répétitions, les six valeurs par défaut, la dérivation du compte,
sa normalisation, le refus de lancement, la relecture, la forme écrite, le cycle
rapide et les deux conditions d'affichage — et **refuse de compter si l'une de ces
formes a changé**. Elle compare ensuite la formulation du portage à celle de
l'original : **70** textes pour `Number()`, **84** états pour le compte et le refus,
**56** documents pour la relecture, **2016** combinaisons pour l'aller-retour,
**14** états d'affichage. Le tout avec **69 vérifications, 0 écart**.

**Et la section 15 relit les listes figées DU TEST.** Le vert de la section 13 ne dit
rien de ce que `Tests/AudioRepeatPreferencesTests.swift` porte **en dur** : ses deux
boucles du refus de lancement, sa liste de documents « inchangés », sa table de
`Number()` (70 lignes) et sa table d'affichage (14 états). La section 15 **lit ce
fichier** — par comptage d'accolades, chaînes et commentaires ignorés, car ces listes
portent des `{` et des `}` **dans** leurs chaînes — et confronte chaque entrée à la
référence. Elle **refuse de conclure** si une forme a changé, si une boucle a disparu
ou si une liste est vide. Un test de complétude ferme la table de `Number()` : ses
textes doivent être **exactement** ceux du banc, ni un de moins ni un de plus.

**Ce que la CI a trouvé, et que le banc ne voyait pas.** Le run n° **40** a rendu
**228 tests, 1 ignoré, 2 échecs** — et les deux venaient de ce fichier de test, pas du
portage : `1e3` rangé parmi les textes **acceptés** au lancement (il vaut 1000, donc
refusé), et `customCount: "abc"` attendu comme retombant sur le défaut — or la règle de
l'original est `typeof prefs.customCount === 'string'`, donc une chaîne est **gardée**,
quelle qu'elle soit. Le banc, lui, avait les deux bonnes réponses : il les calcule. Ce
qui manquait était un contrôle qui relise les listes **recopiées** dans le test. C'est
la section 15 — et six mutations du fichier de test éprouvent qu'elle les voit.

**Ce que le banc a trouvé, et qu'il ne cherchait pas.** La table de `Number()` a
montré un texte dont la valeur dépasse 2^53 (`'99999999999999999999'`) : les 84
états du compte n'allaient pas jusque-là, donc la divergence du portage y était
**invisible**. Elle est désormais mesurée et déclarée, plutôt que laissée hors du
banc. Et une mutation de la translittération — la chaîne vide qui ne vaut plus zéro
— est restée **non détectée** : le banc comparait les deux décisions qui dérivent de
la valeur, pas la valeur elle-même, et `0` comme `NaN` ramènent le compte à 1. La
comparaison de la valeur brute a donc été promue en verdict.

**Et le banc est falsifié.** `_banc/falsifier-audio.mjs` compte désormais **41
mutations** : 5 sur `Core/PassageAudio.swift`, **16 sur `Core/AudioRepeatPreferences.swift`**
(le cycle rapide qui inclut « Autre », la borne 999, le message, la chaîne vide, les
littéraux `0x`, la forme canonique, la grammaire décimale, les deux affichages, le
libellé, la clé écrite, la relecture, la borne 2^53…), **6 sur
`Tests/AudioRepeatPreferencesTests.swift`** (un texte du mauvais côté du refus, un
document déclaré inchangé qui garde en fait un champ, le compte et la valeur brute d'une
ligne de la table, une ligne **retirée** pour éprouver la complétude, un état
d'affichage faux), et 13 sur les translittérations du banc. **0 non détectée**, et les
**trois** fichiers restaurés octet pour octet, empreinte SHA-256 à l'appui.

**Ce qui reste.** L'écran de réglages et la **couche AVFoundation** — les deux
parties qui ne se prouvent pas sans appareil. La **décision** de la boucle, elle,
est désormais portée : §9.15.

### 9.15 La boucle de répétition : une machine d'état, pour que l'indicible se teste

`Core/PassageAudio.swift` décide **quelle** position vient ensuite et **combien de
temps** attendre. Il restait à décider **ce qu'on en fait** : charger, reprendre,
mettre en pause, planifier, s'arrêter. Cette décision vivait dans
`src/PassageAudioPlayer.tsx`, mêlée aux appels AVFoundation — donc inéprouvable
sans appareil.

`Core/PassageAudioEngine.swift` l'en sépare. La machine rend la liste des
**effets** à exécuter (`.load`, `.resume`, `.pause`, `.stop`, `.scheduleWait`,
`.cancelWait`, `.setRate`, `.announceVerse`, `.fail`) et laisse l'objet dans son
nouvel état. Aucun appel audio : un exécuteur traduit les effets.

Quatre règles silencieuses y sont figées, et s'y tromper ne lève rien :

1. **On ne conclut que sur `nil`.** Tant que `PassageAudio.next` rend une
   position, on enchaîne — même si elle est identique à la courante.
2. **Le silence choisi ne s'applique que sur un redémarrage de passage ou un
   verset répété.** Ailleurs, la marge de 200 ms est seule.
3. **Un verset qui suit immédiatement le courant, dans la même piste horodatée,
   se reprend** au lieu d'être rechargé.
4. **Mettre en pause pendant l'attente mémorise le temps restant** ; reprendre ne
   rejoue pas l'attente entière.

Le refus de lancer n'est pas réécrit : la machine emploie `launchError` de
`AudioRepeatPreferences`, déjà éprouvé, et il est **plus étroit** que la
normalisation de `:79` — `'1.5'` et `'5000'` sont refusés au lancement, alors que
la normalisation en ferait 1 et 5000.

**Le banc calcule les séquences, le test les recopie.** `_banc/oracle-engine.mjs`
empaquette le vrai `src/core/audio.ts` — il n'en recalcule rien — et **extrait du
TSX** les trois lignes qui décident de l'attente (`restart`, `repeatedVerse`,
`wait`) ainsi que la ligne de continuation. Il les évalue telles quelles, puis
joue **dix-huit scénarios** et imprime la séquence d'effets de chacun. Ces
séquences sont celles que recopie `Tests/PassageAudioEngineTests.swift` : une
valeur écrite de mémoire serait vue ici, et non au run — c'est exactement ce que
le run #40 a coûté.

La confrontation est **d'un seul tenant** : le banc exige la séquence entière, mise
en forme retirée des deux côtés. Chercher chaque effet séparément ne dirait rien de
l'ordre, et une séquence dont on retire un `pause` resterait « trouvée » parce que
`pause` figure ailleurs dans le fichier.

**Falsifié, et la falsification a trouvé un défaut dans le banc lui-même.** Sept
mutations — quatre du moteur, trois du test — sont toutes détectées, les deux
fichiers restaurés octet pour octet. Mais la **première** version du contrôle
laissait passer le retrait d'un `pause` : la séquence cherchée figurait aussi dans
un `XCTAssertNotEqual` de garde. La garde a été réécrite en contrôle d'**état**, et
la raison est notée dans le test.

**Ce que ces tests ne prouvent pas.** Qu'AVFoundation joue, ni que la minuterie de
borne se déclenche à la bonne milliseconde sur un appareil. Ce sont les deux
parties qui restent à écrire, et elles sont isolées dans l'exécuteur d'effets, qui
ne contient aucune décision.

### 9.16 L'écran des réglages : une vue qui ne décide de rien

`Features/Quran/AudioRepeatSettingsView.swift` est la vue de
`PassageAudioPlayer.tsx:236-271`. Elle n'est prouvable ni par un test — il n'y a
rien à exécuter —, ni par la compilation, qui ne dit rien du comportement. Ce qui
est vérifiable, c'est une **forme** : que tous les libellés, toutes les listes et
tous les états viennent du modèle.

**Aucune valeur n'est recopiée.** Les pastilles prennent leur libellé de
`countLabel`, le compte affiché de `countText`, la coche de
`showsAutoStopSelected`, le `∞` de `displaysUnlimitedRepetition`, les trois listes
de `countChoices`, `speedChoices` et `gapChoices`, la marge technique de
`defaultAyahGapMilliseconds`, et la lecture des nombres de `jsNumber` et
`customInteger`. La règle vaut parce qu'un écran qui recopie une liste diverge en
silence : l'original porte **sept** répétitions, **six** dans la pastille de cycle
rapide, **trois** vitesses, **quatre** pauses.

**Deux pièges d'affichage, respectés sans être recopiés.** La case de l'arrêt
automatique est un **bouton**, jamais un `Toggle` lié à `autoStop` : un `Toggle`
afficherait l'état **stocké** et resterait cochée en mode « en continu », alors que
l'original la décoche — et décocher pour de vrai est un geste **distinct**, qui
survit au retour en arrière. Et le refus de lancement n'est pas ré-implémenté dans
la vue : il est décidé par `AppViewModel.launchAudioPassage`, dans l'ordre de
`:176` — la **plage** d'abord, le **compte** ensuite.

**Un défaut silencieux fermé.** `Storage/LocalStore.swift` déclarait
`loadAudioPreferences` et `saveAudioPreferences` depuis le début, et **aucun
appelant n'existait** : les réglages n'étaient persistés nulle part, et les six
aides d'affichage du modèle n'étaient lues que par leurs propres tests.
`AppViewModel` les lit dans `start()` et les écrit à chaque changement — dans une
tâche **enchaînée**, parce que des tâches non structurées ne sont pas garanties de
démarrer dans l'ordre de création, et que deux pastilles touchées coup sur coup
laisseraient sur disque la valeur la **plus ancienne**, en silence, le fichier
restant parfaitement lisible.

`LocalStore` est un **acteur** : la lecture ne peut pas se faire dans un `init`,
qui ne peut pas `await`. Le run #45 s'est arrêté là, sur une seule erreur de
compilation — « call to actor-isolated instance method in a synchronous main actor
isolated context ». Le défaut tenait dans un mot, et le banc ne le voyait pas : il
exigeait que le modèle **écrive** — `saveAudioPreferences` était bien là —, sans
regarder le `await`. Trois vérifications de plus exigent désormais l'`await` des
deux côtés et l'`actor` du magasin.

**Le banc, et son falsificateur.** `_banc/verifier-ecran-audio.mjs` — **24
vérifications, 0 échec** — lit l'écran **sans ses commentaires** : l'en-tête
*cite* `countLabel` et la vitesse `0.75x` pour expliquer ses règles, et chercher
dans le texte brut aurait déclaré vert un écran qui ne les appelle pas.
`_banc/falsifier-ecran-audio.mjs` — **11 cas, 0 non conforme** — rejoue le retrait
de chaque appel, la recopie de chaque liste, l'introduction d'un `Toggle`, la
ré-implémentation du refus, la suppression de l'écriture et le retrait des deux
`await`. Les mutations remplacent **toutes** les occurrences :
`showsAutoStopSelected` apparaît deux fois, et n'en muter qu'une aurait laissé le
contrôle vert.

**Le témoin a servi.** Le banc exige que le nombre de contrôles **exécutés** soit
celui qu'il annonce. Il en attendait 19, il en a exécuté 21, et il a **refusé de
conclure** en désignant l'écart.

**Ce que cet écran ne prouve pas.** Qu'il s'affiche comme prévu sur un appareil, ni
que les six réglages **changent** la lecture — cela ne se voit qu'à l'oreille, sur un
appareil. Ce que la vue **ne décidait** pas, en revanche, est désormais exécuté : la
couche AVFoundation qui manquait est écrite, et c'est §9.17.

### 9.17 L'exécuteur audio : traduire, et ne rien décider

`Core/PassageAudioEngine.swift` rendait des `[PassageAudioEffect]` que **personne**
ne consommait : le moteur n'avait aucun appelant hors de ses tests, et « Lancer ce
passage » démarrait le premier verset de la plage, sans répétition, sans silence et
sans jamais conclure — un verset arrivé à son terme laissait `isPlaying` à vrai.

**La règle de ce fichier.** `Services/PassageAudioExecutor.swift` traduit chaque
effet en appels au lecteur, et **rien de plus**. Aucune de ses conditions ne regarde
un compte de répétitions, un mode, une durée d'attente ou une borne de plage : la
seule valeur de réglage qu'il lise est la **vitesse**, et uniquement pour diviser
l'échéance de la coupure sur segment. Tout le reste est décidé par le moteur, couvert
par `Tests/PassageAudioTests.swift` et `Tests/PassageAudioEngineTests.swift`.

**Un `switch` sans `default`, et c'est délibéré.** Le jour où un effet est ajouté à
l'énumération, la compilation s'arrête dans l'exécuteur. Un `default` l'avalerait en
silence, et l'effet ne serait exécuté nulle part — sans erreur, sans journal, sans
autre symptôme qu'un lecteur qui ne fait pas ce qu'on attend.

**Les trois fins de lecture.** L'original conclut sur **trois** signaux distincts, et
s'y tromper ne lève aucune erreur : la notification de fin d'un `AVPlayerItem`
(`didJustFinish`), la fin du **segment horodaté**, coupée net avant le mot suivant, et
la position qui atteint la durée sans que la notification soit venue (`fileFinished` —
certains fichiers rendus par le réseau rapportent seulement la dernière position). Les
trois aboutissent à la même conclusion, et c'est le **même** garde qui les rend
inoffensives quand deux se déclenchent à quelques millisecondes d'écart : la machine
n'avance que si elle est encore en train de jouer.

**Trois pièges, dont deux ne se devinent pas.**

1. *La fin de segment se recale en même temps que le verset affiché.* Quand la machine
   enchaîne deux versets d'une **même** piste horodatée, elle émet `resume` — **sans
   position**. La source ne change pas, la lecture reprend après la pause, et rien
   d'autre ne viendrait dire que le segment à surveiller a changé. Ne pas recaler la
   borne ferait disparaître la fin du verset suivant : la piste courrait jusqu'au bout
   du fichier de la sourate, et le passage ne s'arrêterait jamais. C'est ce que fait
   `resumeContinuous` (`PassageAudioPlayer.tsx:106`).
2. *Corollaire, et c'est un second piège :* la minuterie de segment ne doit **pas**
   être réarmée sur `resume`. Dans l'enchaînement, `resume` **précède** `announceVerse`,
   donc la borne encore en place est celle du verset **précédent** — déjà dépassée.
   L'armer là conclurait immédiatement sur une fin qui a déjà eu lieu, et le passage
   avancerait de deux versets. C'est `announceVerse` qui arme, après avoir recalé la
   borne ; `tick` réarme seulement si une pause a annulé la minuterie.
3. *La chronologie n'est pas retenue quand elle n'est pas utilisée.* Si la source
   réellement jouée est un fichier par verset — récitateur sans horodatages, ou
   chronologie inutilisable —, garder la chronologie en mémoire ferait poser une fin de
   segment d'horodatage de **sourate** sur un fichier d'**un seul** verset, et la
   coupure tomberait au mauvais endroit.

**La chronologie d'une sourate.** Elle est demandée à
`api.quran.com/api/v4/chapter_recitations/<resource>/<sourate>?segments=true`, avec le
délai de dix secondes de l'original, **validée** (`PassageAudio.isUsableCachedChapter` :
un cache dont une seule borne est fausse est jeté et rechargé) puis gardée sur disque.
Trois précautions : une seule requête est en vol par sourate — trois versets préchargés
ne doivent pas produire trois téléchargements du même document —, un échec n'est pas
redemandé pendant **cinq minutes**, et un échec n'est jamais visible : la lecture
continue avec les fichiers par verset, exactement comme dans l'original.

**La forme sur disque est celle de l'original, à la lettre.**
`Core/ChapterAudioCache.swift` écrit `{"url": …, "verses": {"<verseId>": {"start": …,
"end": …}}}`. Ce n'est pas du style : `[Int: Span]` confié à `JSONEncoder` produit un
**tableau** alternant clés et valeurs — relisible ici, mais illisible par l'autre
application et par un humain qui ouvrirait le fichier.

**La façade ne joue plus.** `Services/AudioService.swift` publie ce que les vues
observent et délègue. Sa surface publique n'a pas bougé, donc **aucune vue n'a été
modifiée** — et le défaut qu'elle portait disparaît : un verset terminé laissait
`isPlaying` à vrai, faute de conclusion. « Écouter ce verset » passe désormais par la
boucle, avec `count = 1`, mode « passage », arrêt automatique armé : c'est
`action === 'listen'` de l'original. Le choix est forcé sur `.times(1)` et **non** sur
`.custom`, parce que `launchError` ne refuse que le champ **libre** — un « Autre »
invalide resté dans les réglages aurait refusé ce lancement alors qu'aucun champ libre
n'y est utilisé.

**Ce qui n'est pas branché, et pourquoi.** `continuousAudioPosition`
(`src/core/audio.ts:32`) n'est appelée **nulle part** dans l'original : elle est définie
et jamais utilisée. Le portage la porte donc sans appelant, et
`PassageAudioEngine.followContinuously(_:)` reste sans appelant pour la même raison. Lui
inventer ici un appel aurait ajouté au portage un comportement que l'application
d'origine n'a pas.

**Le banc, et ce qu'il a trouvé.** `_banc/verifier-executeur-audio.mjs` — **46
vérifications, 0 échec** — exige un **accord entre deux sources** : chaque cas déclaré
dans `enum PassageAudioEffect` doit être traité par l'exécuteur. C'est le cœur du banc,
parce qu'un effet ajouté au moteur et oublié dans l'exécuteur ne produit **aucune**
erreur visible. Deux défauts du banc lui-même ont été trouvés en l'écrivant : son motif
d'extraction des cas exigeait une parenthèse ou un deux-points, et ne trouvait donc que
**cinq** des **neuf** effets — `resume`, `pause`, `stop` et `cancelWait` n'en portent
pas ; et son contrôle « aucune décision n'est recopiée » interdisait ce que `listen`
**doit** écrire. Il vérifie désormais que le seul réglage **lu** est la vitesse, sur une
copie locale pour le reste.

`_banc/falsifier-executeur-audio.mjs` — **29 cas, 0 non conforme** — rejoue le retrait
d'un effet traité, l'ajout d'un `default` dans le `switch` **et ailleurs**, le
réarmement de la minuterie sur `resume`, la recopie de la position suivante et du délai
d'attente, la lecture d'un réglage de décision, le retrait de chaque appel, la
réintroduction du `import AVFoundation` dans la façade, et le retour du commentaire qui
annonçait la boucle non branchée. La première mutation — **ajouter un dixième effet au
moteur** — est la plus importante : c'est exactement le défaut que le banc existe pour
attraper, et il ne compile pas, donc il ne se voit pas autrement.

**Ce qui reste à éprouver sur un appareil.** Que la lecture reprenne **sans coupure
audible** entre deux versets d'une même piste, que la coupure sur segment tombe **avant
le mot suivant**, et que la session audio tienne en arrière-plan. Aucun de ces trois
points ne se mesure sans appareil ; le reste de l'exécuteur se lit.


### 9.18 Modifier son programme et ses connaissances : une couche qui manquait

**Ce qui était demandé, et ce que c'est dans l'original.** « Dans réglages, mets la
possibilité de modifier son programme et ses connaissances » correspond, dans
`src/App.tsx`, à deux cartes de `ProfileScreen` (`:325` et `:326`) :

    « Connaissances »       → openKnowledge → assistant, étape 0
    « Objectif et rythme »  → openGoal      → GoalScreen

La seconde affiche `{state.goal.label} · {paceLabels[state.pace]}` et ouvre
`src/ui/GoalScreen.tsx` ; la première ouvre l'étape 0 de l'assistant
(`src/App.tsx:399-402`), celle qui coche les sourates, les juz’ et les hizbs.

**Ce qui manquait réellement.** Pas les écrans : la **couche du modèle**. `Program`
portait déjà `markKnowledge`, `toggleKnownRange`, `partialKnownRanges`,
`generateProgram` et `seedInitialRevisions`. Il lui manquait tout ce que les écrans
consomment pour *choisir* :

| Fonction de `src/core/program.ts` | Ligne | Portée dans |
|---|---|---|
| `goalPresetLabels` | 43 | `Core/ProgramGoal.swift` |
| `goalFromPreset` | 46 | `Core/ProgramGoal.swift` |
| `goalIsAlreadyKnown` | 114 | `Core/ProgramGoal.swift` |
| `validGoal` | 147 | `Core/ProgramGoal.swift` |
| `resetAllProgress` | 90 | `Core/ProgramGoal.swift` |
| `pacePresets` | 34 | `Core/ProgramGoal.swift` |
| `weekdays` | 42 | déjà dans `Core/Program.swift` |

**Deux pièges, et ils sont silencieux tous les deux.**

*La division du seuil.* `validGoal` accepte un objectif qui contient un hizb entier,
**ou** qui atteint un soixantième du Coran :

    return volume(ids) >= totalVolume / 60;      // program.ts:150

En JavaScript, `/` est une division **flottante**. En Swift, `Quran.volume(ids) >=
Quran.totalVolume / 60` sur deux `Int` serait une division **entière** : le seuil
descendrait jusqu'à l'entier inférieur, et un objectif refusé par l'application React
Native serait accepté ici. Le portage compare donc deux `Double` :

    return Double(Quran.volume(ids)) >= Double(Quran.totalVolume) / 60

`_banc/verifier-reglages.mjs` exige cette forme **et** l'absence de la forme entière ;
`_banc/falsifier-reglages.mjs` rétablit la division entière pour vérifier que le banc
la voit.

*Les deux valeurs par défaut qui ne s'accordent pas.* `defaultState()` écrit
`notifications.learning = false` (`program.ts:57`) ; le repli de `resetAllProgress`
écrit `{messages: true, learning: true}` (`program.ts:90`). Autrement dit, une remise
à zéro **allume** le rappel quotidien d'apprentissage alors que l'état initial le
laisse éteint. C'est une incohérence de l'original, et elle est recopiée **à dessein** :
la corriger ferait diverger les deux applications après une remise à zéro. Le banc
vérifie les trois faits — que la référence diverge, et que le portage recopie la
divergence au lieu de la « corriger ».

**Deux écrans, parce que l'original en a deux.** Le bouton des réglages ouvre
`GoalScreen` ; « Options avancées · passages et jours » ouvre l'assistant. Les deux
modèles d'objectif ne produisent pas les mêmes libellés — `GoalScreen` écrit
`« Finir le Juz’ 12 »` avec `ranges: [{start: 1, end: …}]`, l'assistant écrit
`« Objectif personnalisé »` avec les plages choisies —, et les deux sont lisibles par
l'application React Native, qui retrouve un préréglé en comparant `goal.label` à
`goalPresetLabels`. D'où deux écrans : `ProgramEditorView` (portage de `GoalScreen`) et
`AdvancedProgramView` (étapes 1 à 3), dans le même fichier.

**Une divergence assumée.** `GoalScreen` porte une carte « Je connais déjà » qui marque
un **préfixe** du Coran (« jusqu'à la sourate X, verset Y »). Elle n'est pas reprise :
« Modifier mes connaissances » couvre le même besoin en plus large — plages
quelconques, sourates, juz’, hizb — et deux écrans qui écrivent `state.knowledge`
seraient deux endroits à faire diverger. La sauvegarde, elle, est inchangée :
`generateProgram(seedInitialRevisions(touch(draft)))`.

**Les écrans ne décident rien.** Le libellé de l'objectif vient de `state.goal.label`,
celui du rythme de `Pace.label`, les textes de la remise à zéro de `Program`, les sept
phrases d'objectif et les sept messages d'erreur de l'original — caractère par
caractère. `SettingsView` ne porte que la mise en page ; `KnowledgeEditorView` et
`ProgramEditorView` ne font que remonter des intentions à `AppViewModel`.

Le seul composant neuf, `SelectableRow` (`Features/Shared/Components.swift`), porte les
**deux** formes de la référence : `Choice` (`●` / `○`, une seule réponse) et
`CheckChoice` (une case **carrée** avec `✓`, plusieurs réponses). Elles vivent dans
`src/ui/theme.tsx` — **pas** dans `DesignSystem.tsx`, contrairement à ce que leur nom
laisse croire. C'est un **bouton**, jamais un `Toggle` : un `Toggle` garderait un état
interne qui pourrait diverger de `state.knowledge`, exactement comme la case `autoStop`
de §9.14.

**Ce que le banc a trouvé — dans le banc.** `_banc/verifier-reglages.mjs` — **86
vérifications, 0 échec** — compare le portage à la source TypeScript expression par
expression (bornes des six préréglés, libellés, seuil flottant, remise à zéro, niveaux
de rythme, jours, messages), puis vérifie que les écrans ne recopient rien. Trois
défauts ont été trouvés **en l'écrivant** :

1. l'ordre des objectifs était lu dans la liste **nue** de `goalAlreadyKnown`
   (`src/App.tsx:382`) autant que dans la liste de tuples (`:405`), ce qui donnait
   **sept** entrées au lieu de six — et un verdict rouge pour une raison sans rapport
   avec l'ordre. La coupe au premier `]` était fausse pour la même famille de raison :
   `surahs[104]` en contient un, ce qui a rendu « non détecté » sur cinq des six
   préréglés ;
2. `Choice` / `CheckChoice` étaient cherchés dans `DesignSystem.tsx` alors qu'ils vivent
   dans `theme.tsx` ;
3. le message de passage invalide était cherché dans la **concaténation** des trois
   écrans. Or **deux** écrans l'émettent : le contrôle restait vert si l'un des deux
   perdait le sien. Il est désormais fait **écran par écran** — et c'est la
   falsification qui l'a révélé, en mutant un seul fichier et en restant verte.

`_banc/falsifier-reglages.mjs` — **41 cas, 0 non conforme** — rejoue les six familles :
chaque borne de préréglé décalée d'un cran, une apostrophe droite à la place de
l'apostrophe typographique, l'ordre des objectifs et celui des niveaux permutés, la
division entière rétablie, la branche « un hizb entier » détournée vers les juz’, les
quatre champs que la remise à zéro doit conserver, l'horodatage qui n'avance plus, les
messages, et le renommage de `struct SelectableRow` — que le banc a d'abord **manqué**,
parce que `includes('struct SelectableRow')` reste vrai sur
`struct SelectableRowRenamed`. D'où une ancre à limite de mot (`\b`).

**Un orphelin de falsification, resté sur le disque.** Le délai d'exécution de l'outil
a tué `falsifier-executeur-audio.mjs` **en pleine mutation** : un `default:` est resté
dans `Services/PassageAudioExecutor.swift`, et le banc est devenu rouge pour une raison
qui n'avait rien à voir avec le code. Le fichier était **absent** de `git status` — mais
ce contrôle avait été fait **avant** l'exécution fautive. Deux conséquences : les
falsifieurs `falsifier-reglages.mjs` et `falsifier-executeur-audio.mjs` restaurent
désormais leurs sources sur `SIGINT` / `SIGTERM` / `SIGHUP`, et la règle « lire
`git status` **après** » est écrite dans l'en-tête du falsifieur.

**Le même accident, sous une forme plus retorse — et un second garde-fou.** Un délai
d'exécution a tué `falsifier-reglages.mjs` **en pleine mutation** à son tour. Cette fois
l'orphelin vivait dans `Features/Settings/SettingsView.swift`, un dossier que git
**n'avait jamais vu** : `git status` ne pouvait rien montrer, **même lu après coup** —
seul `?? Features/Settings/` apparaissait. Le titre de la remise à zéro était resté
recopié en clair (`"Tout remettre à zéro ?"`) là où `Program.resetProgressTitle` devait
être lu.

Le dégât visible — un banc rouge — n'était pas le pire. Le falsificateur décide qu'une
mutation est **détectée** quand le banc sort en `!= 0` ; sur un banc rouge **de toute
façon**, ce critère est satisfait par **n'importe quelle** mutation. Les **39** mutations
suivantes ont donc été déclarées « détectées » à tort : **le signal ne variait plus**.
Seuls deux cas avaient parlé juste — le témoin, et la mutation dont l'ancre avait été
consommée par l'orphelin (« chaîne à muter ABSENTE »).

D'où deux garde-fous, tous deux éprouvés :

1. `falsifier-reglages.mjs` **refuse de continuer** quand le témoin est rouge — il sort
   en `2` **avant d'écrire quoi que ce soit**. Un « ok » obtenu sur un banc rouge ne
   prouve rien, et un rapport qui l'enregistre sans s'arrêter est indiscernable d'un
   vrai vert.
2. **Mettre en scène (`git add -A`) avant de lancer un falsificateur.** La règle « lire
   `git status` après » ne voit que les fichiers **suivis** : c'est un trou, et l'orphelin
   est passé exactement par là. Une fois les fichiers neufs à l'index, une mutation
   restée en place se lit en `git diff` et se rend par `git checkout --`.

**Ce que le run n° 49 a appris, et que les bancs ne pouvaient pas dire.** Poussé en
`f34737d`, le bloc a été refusé en **55 s** par la compilation : **deux** erreurs dans
`Features/Settings/ProgramEditorView.swift`, où **une seule** fermeture
`(Division) -> Bool` servait à interroger `Quran.juzs`, `Quran.hizbs` **et**
`Quran.surahs` — ce dernier étant un `[Surah]`. Or `Surah` (`Core/Quran.swift:18`) et
`Division` (`:29`) sont deux structures **distinctes**, toutes deux porteuses de `start`
et `end` : interchangeables à la lecture, **incompatibles** au compilateur.

Les bancs trouvaient `Quran.surahs` et la fermeture, **chacun de son côté**, sans pouvoir
dire qu'ils ne vont pas ensemble : un contrôle qui vérifie la **présence** de deux choses
ne dit rien de leur **compatibilité de type**. Et l'étape du run qui compile
l'application (`xcodebuild build`) ne compile **pas** la cible de tests — le run n° 50 est
donc le premier où `ProgramGoalTests.swift` est compilé, et il le confirme vert :
**286 tests, 1 ignoré, 0 échec**, sur **quinze groupes**, dont les **33** de
`ProgramGoalTests`.

Règle : **un banc vert ne prouve pas que le Swift compile.** Les bancs lisent le flux,
les textes et les noms ; la compilation est seule à connaître les types.

**Ce qui reste.** L'apparence est portée depuis §9.19. Restent les autres cartes des
réglages : affichage du Coran, notifications, sources, profil et compte, et l'**entrée** de
l'assistant (l'écran d'accueil qui demande le sexe et le prénom). Aucun bouton mort n'a été
posé pour autant : l'écran ne montre que ce qui fonctionne.

### 9.19 L'apparence : quatre décisions qui ne doivent pas vivre dans la vue

Le thème s'appliquait déjà — `AppViewModel.palette` reproduit `applyTheme` depuis le début.
Ce qui manquait, c'est de pouvoir en **changer** : la première des lignes ⬜ de l'écran des
réglages. Le travail n'est donc pas d'afficher une palette, mais de porter quatre décisions
qui, écrites dans la vue, divergeraient en silence.

**Première décision : l'ordre d'affichage n'est pas l'ordre de la table.** L'original écrit
`[themeOptions[0], themeOptions[2], themeOptions[1]]` (`src/ui/DesignSystem.tsx:17`) — blanc,
**rose**, **vert**. Le vert passe derrière le rose alors qu'il le précède dans
`themeOptions`. Une recopie littérale « blanc, rose, vert » a une chance sur deux d'être
juste, et rien en Swift ne le signale. Le banc ne compare donc pas la liste à elle-même : il
lit les trois **indices** dans la référence, les applique à la table réellement lue, et
compare le résultat. Il exige en outre que l'ordre affiché **diffère** de l'ordre de la table
— sans quoi une recopie serait indiscernable d'une dérivation juste, et le contrôle ne
prouverait rien.

**Deuxième décision : la bascule des thèmes supplémentaires.** `useState(theme === 'lilac'
|| theme === 'night')` : elle est ouverte **d'emblée** si le thème stocké est l'un des deux.
Un `false` initial cacherait sa propre carte à un utilisateur de « Lilas & Perle ». Le
portage garde donc l'absence de choix distincte du choix (`@State private var extrasChoice:
Bool?`), et c'est le modèle qui dit ce que vaut l'absence.

**Troisième décision : l'ordre des accents est une donnée.** `AccentSelector` parcourt
`Object.keys(accents)` (`:18`), donc l'ordre d'insertion de `src/theme/tokens.ts:5-10` :
prune, rose, vert, doré. Un dictionnaire Swift n'a **aucun** ordre. `Theme.accentOrder` le
fixe, et le banc le compare à l'ordre d'insertion lu dans la référence.

**Quatrième décision : l'accent AFFICHÉ n'est pas l'accent stocké.**
`value={state.accent ?? accent}` (`AppearanceScreen.tsx:6`) : à défaut, l'accent se déduit du
thème — `classic` → vert, `feminine` → rose, sinon prune.

#### Le champ qui manquait, et pourquoi il n'est pas cosmétique

`Theme.Accent` n'avait que `label`, `primary` et `soft`. La référence en porte un quatrième :
`swatch`. Ce n'est pas un ornement — c'est **la seule chose** qui distingue visuellement les
quatre ronds du sélecteur. Et il n'est pas égal à `primary` :

| Accent | `swatch` | `primary` |
|---|---|---|
| prune | `#7B285C` | `#7B285C` |
| rose | `#D9899A` | `#A95069` |
| vert | `#6E8B68` | `#54734E` |
| doré | `#C89A52` | `#916825` |

**Trois accents sur quatre.** Confondre les deux champs donnerait trois pastilles fausses, le
code compilerait, et le test passerait si l'on ne vérifiait pas le **compte** exact des
accents divergents. C'est ce compte (trois) que fixe `AppearanceTests`, avec la raison : un
test qui passerait aussi bien si les deux champs coïncidaient partout ne prouverait rien.

Corollaire mesuré, et contre-intuitif : `Theme.white.green` **est** le `primary` de « prune ».
C'est pourquoi le thème blanc « fonctionne » sans accent — et pourquoi le thème vert, lui,
coche l'accent « Vert » **sans** que sa palette soit réécrite : `applyTheme` n'applique
l'accent que s'il est donné **ou** si le thème est blanc. Le rond coché et la couleur
appliquée suivent deux règles voisines mais distinctes, et `AppearanceTests` fixe l'écart qui
les sépare.

#### Le sous-titre, où deux caractères comptent

La carte des réglages affiche `\(nom du thème) · couleur d’accent` (`src/App.tsx:329`). Le
séparateur est un **point médian** (U+00B7) entouré d'espaces, et l'apostrophe de `d’accent`
est **typographique** (U+2019). Deux caractères qu'on croit avoir tapés justes. Le contrôle
compare donc la chaîne **entière**, et le test vérifie en plus qu'aucune apostrophe droite ni
aucun tiret n'y figure.

Le nom, lui, vient de `themeOptions.find(t => t.key === (state.theme ?? 'white'))?.name` : un
thème **inconnu** rend `undefined`, donc **rien**. Le portage rend la chaîne vide et compose
` · couleur d’accent` — un sous-titre amputé plutôt qu'un nom inventé. Ce n'est pas un cas
d'école : une version plus ancienne peut avoir stocké une clé que celle-ci ne connaît plus.

#### Ce qui n'est pas porté, et pourquoi c'est dit

**La section « Police de l'interface »** — trois choix (élégante, moderne, classique),
`AppearanceScreen.tsx:6`. Le choix **écrit** bien `state.uiFont`, mais rien ici ne le lit :
`src/theme/fonts.ts` branche `titleFont()` sur « Cormorant-Semibold » et `interfaceFont()` sur
« Cormorant-Regular », deux polices livrées par `@expo-google-fonts` et **absentes** de ce
dépôt. Afficher trois choix dont aucun ne change quoi que ce soit à l'écran serait un
mensonge : l'utilisateur croirait l'application cassée. Cette section viendra avec les
polices — **197** appels `.font(.system(` répartis sur **treize** fichiers, plus les fichiers
de police à embarquer.

**L'illustration des cartes de thème** — `themeArt`, cinq PNG de `assets/themes/`,
**10 199 065** octets au total. Ces cinq images servent **aussi** l'en-tête de l'accueil
(`IslamicHero`, `src/ui/Premium.tsx:13`) : elles seront portées **une seule fois**, avec le
bloc des ressources. Le banc ne se contente pas de constater l'absence : il vérifie que
l'écran n'invente **aucun substitut** — pas de bande de couleurs tirée de `swatches` (table
déclarée mais **jamais rendue** dans l'original), aucun code couleur écrit en dur.

#### Vérification, et ce que le banc a appris sur lui-même

`_banc/verifier-apparence.mjs` — **63** contrôles, 0 échec. `_banc/falsifier-apparence.mjs` —
**25** cas, 0 non conforme, **24** mutations détectées, chaque fichier restauré **octet pour
octet**. `Tests/AppearanceTests.swift` — **20** tests. `Theme` n'était testé **nulle part**
avant ce bloc.

Le falsificateur a servi **immédiatement**, et pas sur le code : sa première exécution a
montré **huit** défauts dans le banc lui-même. Trois venaient de la même erreur, qui mérite
d'être retenue :

> `bodyOf(source, marqueur, fin)` **inclut** son marqueur. Pour une déclaration Swift comme
> `accentOrder: [String] = ["prune", …]`, partir du marqueur `accentOrder: [String] = [`
> fait rencontrer le premier `]` du **type** `[String]`, pas celui de la **liste**. Le corps
> se réduisait à `accentOrder: [String`, qui ne contient aucune chaîne — et le banc annonçait
> « le portage ne déclare rien » sur trois listes parfaitement présentes.

Deux autres défauts du même genre : un motif qui exigeait `return` là où Swift l'omet
(fonction à expression unique), et une ancre « aucune image » qui attrapait
`Image(systemName:)` — la coche de sélection, qui n'a rien à voir avec l'illustration du
thème.

Règle : **un contrôle qui échoue accuse trois choses** — la source, l'ancre, ou lui-même.
Les huit défauts étaient tous dans le contrôle.


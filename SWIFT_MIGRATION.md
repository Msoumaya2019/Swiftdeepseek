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
| Réconciliation du document à la connexion | ✅ | ✅ | `user_state.data` | `Core/Reconcile.swift`, `Repositories/AppStateRepository.swift` | Port de `migrateReaderState`, `reconcileState` et `accountState` (`program.ts:48-130`), en **JSON brut** : sept règles de l'original testent `=== undefined`, ce qu'une structure Swift ne distingue pas de `null`. Voir §9.32. |
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
| Liste des sourates (recherche, filtre) | ✅ | ✅ | — (données embarquées) | `Core/Quran.swift`, `Core/SurahListOptions.swift`, `Features/Quran/SurahListView.swift` | Portée. La recherche d'une **sourate** porte sur quatre champs — numéro, nom, signification, arabe — et le filtre Mecquoise/Médinoise s'y applique ; la recherche d'une **division** en porte trois autres, et le filtre n'y est pas testé. Deux règles, pas une. Voir §9.29. |
| Liste des Juz' et des Hizb | ✅ | ✅ | — | `Core/Quran.swift`, `Core/SurahListOptions.swift` | Portée : **30** Juz', **60** Hizb, chacun avec sa plage de pages calculée par `QuranSourceNavigation.versePage` — la même fonction que la reprise d'une marque-page. Mesuré : **aucune** division ne change de plage entre les deux éditions. Voir §9.29. |
| Lecteur « Coran de Médine » (604 pages) | ✅ | ✅ | — | `Features/Quran/Reader/ReaderView.swift`, `MushafPageViewController.swift`, `Resources/Mushaf` | 604 PNG embarquées. |
| Lecteur « Coran 1441 » | ✅ | 🟡 | — | `Services/QuranSourceService.swift` | Lit les pages si elles sont présentes ; **le téléchargement et l'installation sont implémentés** — voir §9.4. |
| Pagination native au doigt | ✅ | ✅ | — | `MushafPageViewController.swift` | `UIPageViewController`, comme prévu. |
| Préchargement page précédente / courante / suivante | ✅ | ✅ | — | `MushafPageViewController.swift` | Trois pages, jamais 604. Cache LRU. |
| Centrage vertical sans marge fixe | ✅ | ✅ | — | `ReaderView.swift`, `MushafPageViewController.swift` | Zone de page = tout l'espace restant, `scaleAspectFit`, contraintes centrées. Aucun `marginTop`. |
| Reprise à la dernière page lue | ✅ | ✅ | `user_state.lastRead` | `Features/Home/HomeView.swift`, `ViewModels/AppViewModel.swift` | |
| Marque-pages | ✅ | ✅ | `user_state.bookmarks` | `Core/Bookmark.swift`, `Core/BookmarkOptions.swift`, `Core/QuranSourceNavigation.swift`, `Features/Quran/BookmarksView.swift` | Poser/retirer dans le lecteur, liste complète dans les deux écrans, reprise de lecture sur la page du **verset** dans l'édition affichée. La fusion (`mergeBookmarks`) est portée **et appelée** : `Reconcile.mergeBookmarksRaw` est le portage de `reconcileState`, son unique appelant dans l'original. Voir §9.28 et §9.32. |
| Choix de l'édition | ✅ | ✅ | `user_state.reader.mushaf` | `Features/Quran/Reader/ReaderView.swift` | Les cinq éditions, et les trois non reprises : voir §9.3. |
| Sources du Coran (attributions) | ✅ | ✅ | — | `Core/QuranSourcesCard.swift`, `Features/Settings/SettingsView.swift` | Les attributions de licence — Tanzil, QPC V4, cpfair, Rachid Maach, Quran Meta — et le lien vers tanzil.net, recopiés **au caractère près**, deux apostrophes typographiques distinctes comprises. Voir §9.24. |
| Profil : prénom, compte, photo | ✅ | 🟡 | `auth.users`, `friend_profiles`, bucket `friend-avatars` | `Core/ProfileOptions.swift`, `Features/Profile/ProfileView.swift`, `Tests/ProfileTests.swift` | Les 47 textes, les quatre conditions d'activation et les deux bornes de photo sont portés et gelés, et l'**écran est monté** — le prénom, le compte, la déconnexion, plus l'**avis global** qui manquait à tout le monde. La photo et le formulaire de connexion restent délibérément hors de l'écran. Voir §9.25 et §9.26. |
| Lecture simplifiée (Tajweed) | ✅ | ✅ | — (données embarquées) | `Core/TajweedOptions.swift`, `Features/Quran/Reader/TajweedVerseListView.swift`, `Tests/TajweedTests.swift`, `Tests/TajweedListTests.swift` | Portée, **modèle et rendu**. Les trois fonctions de `readerData.ts` sont épinglées par **25** tests : indexation en points de code (1 173 / 680 / 1 171 au verset 2:282), fusion par égalité de règle, garde de concordance, six branches de couleur, et la garde du vide des notes (`""` sur 4 906 lignes). Le rendu **verset par verset** (`MushafPage.tsx:34-43`, avec le défilement de `App.tsx:499`) est écrit et éprouvé par **15** tests de plus. L'édition est **proposée** : `isAvailable` lit les données (`hasArabic && hasTranslation`) au lieu de rendre `false`. Voir §9.30 et §9.31. |
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
| Notifications : carte des préférences | ✅ | ✅ | `user_state.notifications` | `Core/NotificationOptions.swift`, `Features/Settings/NotificationSettingsView.swift` | Les **sept** interrupteurs dans l'ordre de l'original, la porte de permission, le pied de carte et les **deux** vérifications locales. Le rappel quotidien est réellement programmé sur l'appareil, à 19 h 00. Voir §9.23. |
| Notifications push (jeton APNs) | ✅ | ⬜ | `push_devices`, `notification_preferences`, RPC `register_push_device` | — | Jeton APNs propre, même `user_id` — voir §7 et `README.md`. Ce qui manque est l'**envoi** : `registerPushDevice`, `updatePushPresence`, `unregisterPushDevice`, `pushDiagnostic` et le miroir `notification_preferences`. Demande un compte Apple Developer, un appareil physique, et une table serveur dont l'existence n'est pas vérifiée ici. |
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

### 9.20 L'horodatage d'une remise à zéro : une divergence sous la milliseconde

Le run n° 54 ne porte **que de la documentation** — la correction de quatre défauts de forme
dans ce document et dans `RAPPORT_DE_TEST.md`. Il est pourtant **rouge**, sur **un seul**
test. Un envoi de documentation ne peut pas changer le code des tests : l'échec ne peut donc
pas venir de ce qu'il porte, et il faut le lire comme la **sortie au grand jour d'un défaut
latent**.

**Le défaut.** `Core/DateKeys.swift` porte `maxISO`, qui reproduit la ligne 93 de
`src/core/program.ts` :

```js
const now = Date.now();
const previousTime = Date.parse(previous.updatedAt);
updatedAt: new Date(Math.max(now, previousTime + 1)).toISOString()
```

Tout y est en millisecondes **entières** : `Date.now()` en rend une, `Date.parse` en rend
une, et `toISOString()` n'écrit que trois décimales. `Math.max(now, previousTime + 1)` est
donc **toujours** strictement supérieur à `previousTime` — la référence ne peut pas rendre
une valeur égale, et c'est cette garantie qui fait qu'une remise à zéro **gagne la fusion**
contre l'état qu'elle remplace.

Le portage, lui, comparait `previous` à une lecture d'horloge **plus fine** que la
milliseconde :

```swift
var latest = Date()
for value in values.compactMap({ $0 }) where value >= latest {
    latest = value.addingTimeInterval(0.001)
}
return iso(latest)
```

Dès que les deux lectures tombent dans la **même** milliseconde, la comparaison est fausse,
`latest` reste `now`, et `iso()` rend la milliseconde de `previous` — une valeur **égale**.
La fenêtre n'est pas hypothétique, elle se mesure : c'est la fraction de milliseconde qui
restait au moment de la première lecture. D'où une cinquantaine de runs verts avant le
rouge — et un test qui ne l'attrape qu'une fois sur cinquante n'est pas un mauvais test,
c'est un bon test sur un défaut rare.

**Pourquoi c'est un défaut de compatibilité, et pas un détail.** L'application React Native
garantit un `updatedAt` strictement croissant ; le portage ne le garantissait pas. Les deux
applications auraient donc pu, sur la même remise à zéro, écrire deux horodatages dont l'un
n'est pas plus récent que l'autre — et diverger sur le champ même qui décide quelle version
gagne. C'est exactement ce que cette migration doit empêcher.

**La correction** (`a5a25fd`) calcule en millisecondes entières, comme le modèle JS, et rend
`now` **injectable** pour que la fenêtre se teste sans dépendre de l'horloge :

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

**Deux bancs, parce qu'un contrôle de forme ne prouve pas une propriété.**
`_banc/oracle-horodatage.mjs` — **53 vérifications, 0 écart** — empaquette le **vrai**
`src/core/program.ts` et exécute la **vraie** `resetAllProgress`, `Date.now` étant remplacé
sur une grille de **quinze cas** (cinq positions de `previous` × trois lectures d'horloge
fractionnaires). Son **témoin**, le portage d'avant correction, diverge sur **6 des 15** cas
— sans quoi la grille n'aurait pas de cas discriminant, et le banc ne prouverait que la
ressemblance de deux codes identiques. `_banc/falsifier-horodatage.mjs` — **4 mutations,
4 détectées** — restaure chaque source par empreinte SHA-256 : revenir au portage fautif,
passer `>=` à `>`, rendre la lecture d'horloge fractionnaire, et décaler la constante `+1`
de la formule de référence.

**Et un libellé qui promettait trop.** `_banc/verifier-reglages.mjs:338` portait
`verdict(/DateKeys\.maxISO\(/.test(…), 'l'horodatage avance strictement')`. Un contrôle de
**présence de motif** ne peut pas prouver une propriété **sémantique** — la même famille de
défaut que le §9.18 raconte pour la compatibilité de types. Le libellé dit désormais ce que
le contrôle fait — « la remise à zéro passe par `DateKeys.maxISO` (forme) » — et renvoie à
l'oracle pour le fond.

**Ce qui a changé dans les comptes.** Un test est né,
`testMaxISOAdvancesStrictlyEvenInTheSameMillisecond`, qui recopie trois chaînes **mesurées
par le banc** — jamais écrites de tête. `ProgramGoalTests` passe de **33** à **34** tests,
et le total déclaré de **306** à **307**.

### 9.21 Les illustrations des thèmes : deux clés qui ne portent pas le nom de leur fichier

Le dernier point ouvert de l'écran d'apparence était l'illustration des cartes. Elle est
portée — et elle cachait **deux pièges**, dont un seul se voit à la compilation.

**Ce que la référence déclare.** `src/ui/Premium.tsx:9` porte une table de cinq entrées :

```jsx
themeArt={{
  white: require('../../assets/themes/white.png'),
  classic: require('../../assets/themes/emerald.png'),
  feminine: require('../../assets/themes/rose.png'),
  lilac: require('../../assets/themes/lilac.png'),
  night: require('../../assets/themes/night.png')
}}
```

**Deux clés ne portent pas le nom de leur fichier** : `classic` lit `emerald.png`, et
`feminine` lit `rose.png`. Une recopie « évidente » — `classic.png`, `feminine.png` —
**compile**, passe le contrôle des clés, et laisse **deux cartes vides** : le nom serait
simplement introuvable dans le paquet, et rien d'autre ne le dirait. C'est la raison d'être
du contrôle `classic → emerald.png` / `feminine → rose.png` du banc, et de deux mutations
qui lui sont dédiées.

**Les cinq fichiers ne font pas le même format.** Mesuré : `white.png` fait **1613 × 975**,
les quatre autres **1254 × 1254**. Un `.aspectRatio(contentMode: .fit)` cadrerait donc
**juste** quatre thèmes et **laisserait des bandes** sur le cinquième. C'est `.fill` +
`.clipped()` qui est obligatoire — et non un choix esthétique.

**Les mesures viennent de la référence, et le banc les relit.** La carte
(`src/ui/DesignSystem.tsx:17`) place l'image à `width:'42%'`, `height:105`,
`borderRadius:14` ; le bandeau d'accueil (`src/ui/MainScreens.tsx:23`) la pose en fond avec
`opacity:0.55` et `minHeight:100`. Le portage les porte dans `Theme.Art` — et
`_banc/verifier-apparence.mjs` **lit ces cinq nombres dans la référence** avant de les
comparer, au lieu de les recopier. Les 42 % sont une **fraction de la boîte de contenu** de
la carte, pas une largeur en points : le `GeometryReader` est donc posé **à l'intérieur** du
`.padding(Theme.Spacing.sm)`, sans quoi la carte serait juste sur un seul format d'écran.

**Le dossier, et pas un groupe.** `Resources/Themes` est déclaré `type: folder` dans
`project.yml`, comme `Resources/Mushaf` — c'est ce qui donne au paquet un sous-dossier
`Themes/` où `Bundle.main.url(forResource:withExtension:subdirectory:)` trouve les fichiers.
Une référence de **groupe** laisserait les cinq PNG hors du paquet en gardant leurs noms
trouvables dans `project.yml`. Le chargement passe par `ThemeArtCache`
(`NSCache<NSString, UIImage>`) : chaque image pèse deux mégaoctets et se décode en
1254 × 1254 ; les relire à chaque rendu ferait clignoter la liste et repayerait le décodage.

**Ce qui n'est toujours pas porté : la police.** Les trois fichiers de police déclarés par
`package.json` — `@expo-google-fonts/amiri`, `@expo-google-fonts/cormorant-garamond` — sont
**absents** du dépôt de référence : `node_modules` n'y est pas installé, et
`find … -name '*.ttf' -o -name '*.otf'` ne rend **rien**. `state.uiFont` reste donc
**délibérément non branché**, et le §19 du rapport de test le dit.

**Une divergence assumée, annotée et non corrigée.** L'en-tête de `HomeView` affiche le
libellé de l'objectif dans sa grande ligne, là où `MainScreens.tsx:23` affiche
« As-Salâm ‘Alaykoum, » suivi du **prénom** (taille 32) puis « Prêt à continuer ton
apprentissage ? ». Le **bandeau illustré** est porté ; les **textes** ne l'ont pas été, et le
commentaire du fichier le dit plutôt que de le taire.

**Les comptes.** `_banc/verifier-apparence.mjs` passe de **63** à **89** vérifications, dont
les cinq empreintes SHA-256 des images comparées à celles de la référence. Il a fallu
**corriger deux expressions régulières du banc lui-même** : le libellé Swift est
`contentMode:`, pas `content:`, et `minHeight:Theme.Art.bannerMinHeight` se cherche sur le
texte **aplati** — où l'espace après le deux-points n'existe plus.
`_banc/falsifier-apparence.mjs` passe de **25** à **47** cas, tous détectés : les deux clés
trompeuses, une permutation de noms, une clé retirée, la lecture rendue non facultative, les
cinq mesures décalées, le `type: group`, le sous-dossier perdu, `.fill` devenu `.fit`, le
cache retiré, et les mesures recopiées dans la vue. Le contrôle des empreintes, lui, **ne
peut pas être atteint par une substitution de texte** : le falsificateur porte donc une
section **binaire**, qui écrase le contenu de `rose.png` par celui de `white.png` puis
restaure à l'octet.

### 9.22 L'affichage du Coran : quatre éditions, trois écritures, et une liste qui n'était pas la bonne

La carte « Affichage du Coran » de `src/App.tsx:330` a trois parties : le choix de
l'édition, le fond du Coran avec règles de Tajwid, et le suivi automatique de la
récitation. Elle a été portée avec `Core/QuranDisplayOptions.swift`,
`Features/Quran/QuranEditionChooser.swift` et
`Features/Settings/QuranDisplaySettingsView.swift`.

#### Une divergence réelle, trouvée en lisant la référence

`QuranScreenView` parcourait `QuranEdition.allCases` : il affichait donc **cinq**
éditions — Coran de Médine, Coran 1441, Lecture simplifiée, Moushaf Tajwid, Coran
avec règles de Tajwid — dans cet ordre-là. L'original n'en propose que **quatre**,
dans un autre ordre.

L'onglet Coran de l'original ne choisit pas son édition dans une liste : il ouvre un
sélecteur modal (`App.tsx:515`), qui énumère

    [{label:'Coran de Médine',           mode:'traditional'},
     {label:'Coran avec règles de Tajwid', mode:'coranTest'},
     {label:'Lecture simplifiée',         mode:'tajweed'},
     ...zipSources.map(s => ({label: s.label, mode: s.id}))]

et `zipSources` vaut `[{id:'coran_1441', label:'Coran 1441'}]`
(`src/core/quranSources.ts:5`). La carte de réglages (`App.tsx:330`) énumère
exactement les mêmes quatre entrées, dans le même ordre.

`tajweedPages` (« Moushaf Tajwid ») n'apparaît dans **aucun** des deux — et c'est
cohérent : `migrateReaderState` réécrit cette clé vers `coranTest` à chaque
chargement (`src/core/program.ts:60`). C'est une clé d'écriture que l'original ne
laisse jamais choisir. Le portage la proposait, ce qui donnait un choix
immédiatement annulé au chargement suivant.

La liste et son ordre vivent désormais dans `QuranDisplayOptions.editionKeys`, et le
banc exige l'**écart** avec `allCases` — si les deux coïncidaient un jour, le
contrôle échouerait en le disant.

#### Une seule décision, partagée par deux écrans

`QuranScreenView.choose()` portait la règle : une édition que cette version ne sait
pas rendre est refusée ; le Coran 1441 non installé lance l'installation **sans**
changer la préférence ; le reste sélectionne. Cette règle est maintenant
`QuranDisplayOptions.choice(for:coran1441Installed:)`, une fonction **pure** — elle
ne démarre rien et n'écrit rien —, et `QuranEditionChooser` la lit pour router vers
l'un de ses trois rappels. Les deux écrans partagent donc une seule décision.

Le refus de ne pas changer la préférence avant l'installation vient de
`QuranDownload.tsx:8` :

    if (quranDownloaded()) onSelect(); else setExpanded(true);

Tant que les pages ne sont pas là, l'original ouvre son installateur et **n'appelle
pas** `onSelect`. Écrire la préférence d'abord ouvrirait le lecteur sur une édition
dont les 9 060 images manquent — c'est-à-dire sur des pages vides.

#### Les trois écritures ne posent pas le même défaut

C'est le point qu'une relecture rapide rate. Les trois `onPress` de `App.tsx:330`
s'écrivent presque pareil, et ne font pas la même chose :

| appui | `mushaf` écrit | `followAudio` écrit |
|---|---|---|
| une édition | la valeur choisie | `state.reader?.followAudio !== false` |
| un fond | `state.reader?.mushaf ?? 'coranTest'` | `state.reader?.followAudio !== false` |
| le suivi audio | `state.reader?.mushaf ?? 'coranTest'` | la valeur donnée |

Deux conséquences que le portage reproduit telles quelles :

1. **Un appui sur un fond, sur une installation neuve, enregistre
   `mushaf: 'coranTest'`.** C'est surprenant — l'utilisateur croit n'avoir changé
   que la couleur du papier — mais c'est le contrat : l'application React Native
   relira ce document, et l'écrire autrement ferait diverger les deux.
2. **`followAudio` vaut `!== false`, pas `|| true`.** Un `false` stocké reste
   `false` ; une valeur absente devient `true`. Les trois écritures qui ne le
   posent pas explicitement le préservent, et seule celle du suivi audio peut
   écrire `false` sur un lecteur neuf.

#### L'horodatage : une divergence qui n'en est pas une

Le résumé de la session précédente affirmait que la carte de réglages n'appelait
**pas** `touch`, contrairement à `changeQuranSource` (`App.tsx:458`). C'est faux, et
la mesure le dit : les **six** `onPress` de la ligne 330 sont enveloppés dans
`touch(...)`. Trois des vingt-sept contrôles d'un autre banc portaient déjà une
valeur venue de la tête plutôt que du fichier ; celui-ci a été vérifié avant d'être
écrit.

Les trois règles du portage sont donc **pures** : elles ne touchent pas
`updatedAt`. Ce n'est pas un oubli — `AppStateRepository.mutate` applique
`Program.touch(transform(state))` (`Repositories/AppStateRepository.swift:113`), donc
**toute** écriture est horodatée une fois, et une seule. Le banc exige les **deux**
côtés de cette décision : la référence qui enveloppe, et le dépôt qui horodate. Si
l'un des deux changeait seul, le document cesserait d'avancer — ou avancerait deux
fois.

#### Les quatre fonds, et un lecteur hexadécimal qui manquait

`quranPaperOptions` (`src/core/readerAppearance.ts:1-6`) porte quatre fonds en
chaînes hexadécimales, et `quranPaperColor` replie une clé inconnue sur le
**premier** fond — pas sur une constante, ni sur la couleur du thème. Les quatre
chaînes sont conservées telles quelles dans `QuranDisplayOptions.paperOptions`, à
côté de la couleur résolue : c'est la chaîne que le banc compare au fichier de
référence, deux écritures de la même couleur étant indiscernables une fois
converties.

Le portage n'avait aucun lecteur de chaîne hexadécimale — `hex(_:)` prend un
`UInt32`, et il n'existe **aucune** `extension Color` dans le dépôt. D'où
`Theme.color(hexString:)`, qui rend `Color?` : une chaîne qui n'est pas six chiffres
hexadécimaux n'a pas de couleur, et rendre du noir ferait passer une faute de frappe
pour un choix de design.

La couleur du libellé d'un fond est écrite en clair dans l'original —
`'#342a27'` — et n'est **pas** `colors.text`. Les quatre fonds sont clairs, donc le
libellé doit rester sombre quel que soit le thème ; prendre la couleur de la palette
donnerait un libellé illisible sur fond clair dans un thème sombre. Elle est donc
dans le modèle, et le banc refuse tout code couleur écrit en clair dans l'écran.

#### Ce qui est stocké n'est pas encore appliqué, et c'est dit

Le fond n'est consommé qu'à un seul endroit de l'original : `readerState.background`
de `CoranTestScreen`, l'édition rendue par une page HTML dans un WebView avec 607
polices `.woff2` — une chaîne que ce portage n'a pas. Le suivi audio, lui, n'est lu
que par `followAudio(id)` (`App.tsx:445`), dans le même écran.

Les deux préférences sont donc **stockées, affichées et vérifiées**, mais elles ne
colorent et n'enchaînent encore rien ici. Les stocker est nécessaire : c'est ce qui
fait que l'utilisateur retrouve ses choix d'une application à l'autre. Le dire est
nécessaire aussi — un interrupteur qui ne change rien à l'écran ferait croire
l'application cassée. C'est le même raisonnement que pour `state.uiFont`.

Une divergence assumée, enfin : `DownloadSourceChoice` déplie son installateur
**dans** le sélecteur. L'écran de réglages du portage est une feuille : il lance
l'installation et le dit, et l'avancement reste visible dans l'onglet Coran, où
l'installateur vit depuis le début.

#### Les contrôles

`_banc/verifier-coran-affichage.mjs` — **97 vérifications**, `EXPECTED = 97`. Il lit
les quatre fonds, les trois sous-titres de la carte, le sous-titre du Coran 1441,
l'ordre des quatre éditions, les six mesures, la couleur du libellé, les trois
règles d'écriture, les deux côtés de la décision d'horodatage, et l'absence de
toute valeur recopiée dans les écrans.

`_banc/falsifier-coran-affichage.mjs` — **58 mutations plus un témoin**, 59 cas, 0
non conforme. Aucune source n'est laissée mutée : `git status` et `git diff` sont
identiques avant et après.

Deux ancres fautives ont été trouvées en l'écrivant, dont une par le falsificateur :

- la fenêtre de la carte commençait à sa phrase d'**explication**
  (`Choisis la présentation arabe des pages.`), qui vient **après** le titre dans le
  JSX. Le contrôle qui demandait d'y trouver `>Affichage du Coran<` ne pouvait donc
  pas réussir — il échouait sur un banc par ailleurs juste. L'ancre encodait ce
  qu'on attendait lire, pas ce que le fichier dit ;
- `borderWidth:.*?\?(\d+):(\d+)` : un `[^,}]*?` s'arrêterait au premier `?`, qui est
  celui de `state.reader?.paper`. Le quantificateur paresseux sur `.` est
  nécessaire.

Et une leçon de forme, revécue : `grep -cF` sur un motif de **deux lignes** compte
les lignes qui satisfont l'un **ou** l'autre — il a rendu `253` pour un contrôle qui
devait rendre `0`. Les vérifications de sous-chaîne se font sur le fichier entier,
par égalité de présence, jamais par comptage de lignes.

### 9.23 La carte des notifications : sept interrupteurs, trois prédicats, et un banc qui avait tort

**Ce qui est porté.** La carte « Notifications » de `App.tsx:331-348` : la porte de
permission, les **sept** interrupteurs dans l'ordre de l'original, le pied de carte
et les **deux** vérifications locales. Le type `NotificationPreferences` en déclare
**huit** — `revision` n'apparaît dans **aucune** des deux cartes : c'est le service
qui l'écrit, et l'ajouter « par symétrie » afficherait un huitième interrupteur que
l'original n'a pas.

**Un appui matérialise le défaut.** `App.tsx:304,306` écrit
`{...notificationPrefs, [key]:value}`, où `notificationPrefs` vaut
`state.notifications ?? {messages:true, learning:false}`. Toucher un interrupteur
sur une installation neuve écrit donc **aussi** `messages:true` et `learning:false`.
Ce n'est pas un défaut à corriger : c'est le contrat que l'application React Native
relit. Le défaut est une **donnée** (`NotificationOptions.materializedDefault`), et
un test le tient d'accord avec `Program.defaultState().notifications` — deux
endroits qui portent la même vérité sans pouvoir se lire.

**Trois prédicats de permission, et deux divergent.** `App.tsx:305` — la carte —
autorise sur `granted || PROVISIONAL`. `App.tsx:112` et `notifications.ts:61` — le
service et l'effet automatique — autorisent en plus sur `EPHEMERAL`. Un statut
EPHEMERAL (l'autorisation d'une journée qu'iOS accorde aux demandes provisoires)
laisse donc le service **envoyer** pendant que la carte montre encore la porte
d'autorisation. Les deux fonctions sont nommées (`cardAllows`, `serviceAllows`), et
le banc exige qu'elles partagent leur **préfixe** : la divergence est un ajout,
jamais une réécriture.

**Deux écritures du drapeau, et elles ne laissent pas le même document.** L'effet
automatique (`App.tsx:117-119`) force `messages` selon la préférence et
**`learning` à faux** : poser le drapeau **éteint** donc le rappel quotidien, quel
qu'il fût. L'écriture de la carte (`App.tsx:305`) ajoute seulement le drapeau au
défaut matérialisé. Les deux se gardent par le même retour anticipé.

**`null === null` est vrai — le piège de `sameChat`.** `notifications.ts:30`
compare `data?.linkId === activeLinkId` en égalité **stricte**. Or
`friend_messages.link_id` est **nullable** (message de groupe) et le SQL publie
`'linkId', new.link_id` (`social-v2.sql:93`) : sans conversation ouverte, la
notification d'un message de groupe est **supprimée** au premier plan. Un `String?`
confondrait `null` et l'absence ; d'où `PayloadString` à **trois** états —
`.missing`, `.null`, `.string`.

**Le registre se vide ENTIER au-delà de 200 entrées** (`notifications.ts:37`), y
compris celle qu'on vient d'ajouter. Ce n'est pas une erreur à corriger : c'est ce
que l'original fait, et le reproduire est la seule façon d'afficher la même chose.
Et l'enregistrement a lieu **même quand la notification n'est pas affichée** :
`shouldPresent` est pure, `record` écrit.

**Les drapeaux d'affichage sont dérivés par DEUX formules** (`App.tsx:169-172`) :
`!== false` pour `messages`, `corrections` et `adminMessages`, `=== true` pour
`sharedProgress`. Sur une clé absente, la première rend `true` et la seconde
`false` : la progression partagée est la seule éteinte par défaut, ce qui est
exactement le repli de son interrupteur.

**La garde du rappel ne dépend PAS de la valeur** (`App.tsx:173`) : `account &&
onboardingDone`, rien d'autre. C'est essentiel — éteindre l'interrupteur doit
**annuler** un rappel déjà posé, donc appeler la synchronisation avec `false`. Un
garde qui exigerait `enabled` laisserait le rappel en place. Conséquence à
connaître : sans compte connecté, éteindre l'interrupteur n'annule rien.

**Le miroir serveur est porté, pas écrit.** `App.tsx:177` écrit `revision: false`
**en dur** dans `notification_preferences`, et n'y met ni `learning` ni
`messagePreview`. Ce portage **n'écrit pas** cette table : elle demanderait une
vérification côté serveur, et la charte interdit d'ajouter une migration sans le
demander. La dérivation est portée et vérifiée pour qu'un futur écran ne
l'invente pas.

**`scheduleQueue` devient un acteur.** L'original sérialise ses programmations par
une chaîne de promesses (`notifications.ts:23,71,142`) ; un acteur donne la même
garantie par isolation. L'ordre est celui de l'original : **annuler d'abord**,
programmer ensuite — et l'annulation ne vise que le genre d'apprentissage, pas les
deux genres automatiques de `cancelAutomaticReminders`.

**Le troisième bouton de l'original n'est pas là.** `App.tsx:347` ajoute
« Vérifier le jeton push » dès qu'un compte est ouvert. Un bouton qui ne peut rien
vérifier serait un bouton mort : il est absent, et la dérivation
(`shouldRegisterPushDevice`) est portée pour qu'un futur écran ne puisse pas
l'inventer.

**Le banc, et ses vingt-quatre premiers échecs — tous du banc.** Le premier passage
de `_banc/verifier-notifications.mjs` a exécuté 161 contrôles et en a refusé 24.
Les vingt-quatre venaient du **contrôle**, pas du fichier :

- une seule discipline de comparaison manquait. Le banc mélangeait `flat()` et des
  motifs contenant des espaces : `status == .provisional` ne peut pas correspondre à
  un texte aplati, qui écrit `status==.provisional`. Cinq échecs pour cette seule
  raison ;
- `notifications.ts:146` a été cherché dans `App.tsx` — le texte du `throw` du test
  n'est pas dans la carte. Un échec pour un texte pourtant présent ;
- un seul fichier SQL était lu, `social-v2.sql`, alors que les trois `kind` du quiz
  vivent dans `quiz-notifications.sql` et `quiz-install.sql` : « douze `kind` »
  mesurait `huit` ;
- l'ancre de l'effet automatique était `Notifications.getPermissionsAsync()`, qui
  apparaît **deux** fois dans `App.tsx` (lignes 111 et 305). La fenêtre partait de
  la mauvaise, et le contrôle demandait à la ligne 111 ce que dit la ligne 119 ;
- `sameChat` et `destination` sont écrits en `switch` côté Swift, et le banc
  attendait la forme en quatre termes `&&` de l'original. Le contrôle encodait la
  **forme**, pas la **décision** ;
- `indexOf('schedule')` trouvait `scheduler.scheduled()` avant `scheduler.cancel(`
  — un préfixe qui contient le mot cherché ;
- `normalizeInterpolation` transformait `\(x)` en `${x)` sans fermer l'accolade.

Après correction : **179 contrôles**, 0 échec. Et `_banc/falsifier-notifications.mjs`
tue **15 mutations sur 15** — deux interrupteurs permutés, un repli inversé,
`cardAllows` rendu permissif, le drapeau qui n'éteint plus le rappel, le registre
plafonné à 100, `null` confondu avec `missing`, deux routes permutées, le rappel
déplacé à 18 h, une porte ouverte en grand, la garde `||` au lieu de `&&`, le miroir
`revision: true`, un `kind` renommé, deux textes, et la ligne d'accès retirée des
réglages. Le falsificateur vérifie d'abord que le banc **passe** sur l'arbre intact,
exige que chaque détection nomme le contrôle attendu — un code 2 serait une
détection pour la mauvaise raison —, restaure l'arbre dans un `finally`, et compare
les empreintes SHA-256 avant de rendre son verdict.

### 9.24 La carte « Sources du Coran » : cinq chaînes, deux apostrophes, et un banc qui compare au caractère près

**Ce qui est porté.** La dernière carte de la page « Réglages » de l'original
(`App.tsx:350`) : le titre, deux paragraphes d'attribution et un lien vers
tanzil.net. Elle ne propose **aucun** choix, n'ouvre **aucun** écran et ne dépend
d'aucun état — c'est un texte, et un lien. `Core/QuranSourcesCard.swift` porte
les cinq chaînes, `Features/Settings/SettingsView.swift` les affiche dans l'ordre
de l'original, `Tests/QuranSourcesTests.swift` les épingle.

**Pourquoi `QuranSourcesCard` et non `QuranSources`.** Le dépôt de référence a
déjà un module `src/core/quranSources.ts`, qui décrit les sources **d'images**
des pages — et ce portage l'a traduit ailleurs (`Core/VerseBounds.swift:5`,
`Services/QuranSourceService.swift`). Deux choses différentes, deux noms : ce
fichier dit « la carte », pas « les sources ».

**Deux apostrophes typographiques distinctes, et un tiret.** Le second paragraphe
écrit `juz’` avec une apostrophe courbe **fermante** (U+2019) et `rub‘` avec une
apostrophe courbe **ouvrante** (U+2018). La seconde est une singularité de
l'original — probablement une coquille — mais la corriger ici ferait diverger les
deux applications à l'écran pour une raison qui n'appartient à aucune des deux. Le
premier paragraphe, lui, écrit « 2007–2021 » avec un tiret **demi-cadratin**
(U+2013). Ces trois caractères sont épinglés par un test : une « normalisation
bienveillante » ne peut pas passer en silence.

**Deux décisions d'affichage qui ne sont pas des oublis.** Le titre est rendu
`fontSize:14, fontWeight:'600'`, couleur `muted` — plus petit et plus clair que
les titres des autres cartes, qui portent `fontWeight:'700'` et la couleur de
texte : la carte est une note de bas de page, pas un réglage. Et le lien emploie
`colors.green2` et non `colors.green` — deux couleurs qui **diffèrent** sur les
thèmes rose et violet (`Theme.swift`). Les boutons du dossier emploient `green` ;
ce lien-ci emploie `green2`, comme l'original.

**Le banc compare, il ne cherche pas.** `_banc/verifier-sources.mjs` — **31
contrôles**, 0 échec. Il ne cherche pas un motif dans le fichier Swift : il
**extrait** les cinq chaînes de `App.tsx:350` et les compare, caractère par
caractère, aux constantes du modèle. C'est la seule façon de voir une apostrophe
redressée : un motif qui encoderait ce qu'on attendait lire ne la verrait pas.

**Le falsificateur a fait voir deux contrôles faibles.** En le préparant — avant
de l'écrire — deux contrôles du banc se sont révélés incapables de tuer leur
mutation : celui du **montage** de la carte acceptait la simple présence du nom
`sourcesCard` (retirer la `Section` ne l'aurait donc pas tué), et celui de
l'**apostrophe** vérifiait que `\u{2019}` apparaissait *quelque part* dans les
tests, y compris dans le test négatif qui la refuse. Les deux ont été resserrés
sur la **forme montée** et sur l'**assertion exacte**, puis
`_banc/falsifier-sources.mjs` a tué **14 mutations sur 14** — titre abrégé,
apostrophes des deux sens, tiret redressé, adresse changée, flèche retirée,
septième constante, lien colorié comme un bouton, titre recopié dans l'écran,
### 9.25 Le profil : le prénom, le compte, et trois décisions qui ne se voient pas

`App.tsx:322` — la carte « Mon prénom » — est la plus longue de l'application :
quarante-sept textes, quatre boutons dont les conditions d'activation **ne sont
pas les mêmes**, deux bornes de photo qui **ne sont pas le même nombre**, et un
comptage de longueur qui **ne compte pas ce qu'on croit**. Le modèle est
`Core/ProfileOptions.swift`, les tests `Tests/ProfileTests.swift`.

**« Se connecter » n'exige pas d'arobase.** Les quatre conditions, extraites de
la référence :

| Bouton | `disabled` | Activé quand |
|---|---|---|
| Se connecter | `busy\|\|!email\|\|!password` | les deux champs sont non vides |
| Créer un compte | `busy\|\|!email\|\|password.length<6` | + six caractères de mot de passe |
| Renvoyer le courriel | `busy\|\|!email.includes('@')` | une arobase |
| Recevoir un lien | `busy\|\|!email.includes('@')` | une arobase |

Un portage « cohérent » alignerait les quatre. Ce serait une faute : `a@` active
les deux envois de courriel, et l'original laisse le serveur refuser l'adresse.
Le banc **évalue les expressions JavaScript extraites** et compare la décision
rendue à chaque assertion du fichier de tests Swift — douze décisions, douze
concordances.

**Le prénom se compte en unités UTF-16, pas en graphèmes.** `App.tsx:309` mesure
`value.length`, donc `'🙂'.length === 2` : un prénom d'un seul emoji est accepté
d'un côté, et un `count` de Swift l'aurait refusé. Quarante emoji font quatre-vingts
unités et sont refusés. `firstNameLength` et `passwordLength` comptent tous deux
`utf16.count`, et deux tests épinglent l'écart.

**La photo a deux bornes et un seul message.** `avatars.ts:16` refuse au-delà de
`2_800_000` caractères base64 — à la sélection —, `avatars.ts:34` au-delà de
`2_097_152` octets — à l'envoi —, soit exactement 2 Mio. Le message est le même :
« Choisis une photo de moins de 2 Mo. », un arrondi qui parle à l'utilisateur
pendant que la garde compte des octets. Deux autres messages se ressemblent et
**ne sont pas les mêmes** : `uploadAvatar` dit « Connecte-toi pour enregistrer ta
photo. », `removeAvatar` dit « Connexion requise. ».

**Et un test que j'avais écrit faux.** `testTwoTextsCarryATypographicApostrophe`
affirmait **deux** textes portant U+2019 ; compté, il y en a **trois** —
`confirmationResentNotice` porte « l'application » avec la même apostrophe courbe.
Le test est renommé, le commentaire corrigé, et le troisième texte épinglé.

Le banc `verifier-profil.mjs` porte **51 contrôles**, le falsificateur
`falsifier-profil.mjs` **25 mutations, 25 tuées**. Trois leçons en sont sorties,
toutes du même genre — un contrôle qui ne voit pas ce qu'il prétend :

- **Un banc ne lit que ce qu'on lui fait lire.** Le premier jet comparait les
  décisions *épinglées par les tests* aux expressions de la référence, mais ne
  lisait jamais les **corps** de décision du modèle : une mutation ajoutant un
  test d'arobase dans `canSignIn` aurait survécu. Deux contrôles ont été ajoutés.
- **Une mutation mal posée est un contrôle qui n'existe pas.** La mutation
  « le prénom se compte en graphèmes » visait `value.utf16.count`, présent
  **deux** fois dans le modèle — `firstNameLength` et `passwordLength` ont le
  même corps. Le falsificateur a refusé de la poser, et ce refus a révélé que le
  banc ne contrôlait que le premier des deux. Signature ajoutée à la mutation,
  second contrôle ajouté au banc.
- **Un compte global se périme du travail des autres.** `verifier-sources.mjs`
  affirmait « le dépôt porte 384 méthodes de test ». Vrai le jour où il a été
  écrit, faux dès que ce fichier-ci a apporté les siennes — et l'échec n'accusait
  pas ce que ce banc surveille. Le compte global appartient désormais au banc le
  plus récent, et à lui seul.

lien construit dans l'écran, carte retirée de la liste, épingle retirée des tests,
test renommé —, arbre restauré et empreintes SHA-256 comparées.

**Et un garde-fou de plus qui avait tort.** La passe qui a posé la carte a d'abord
**refusé d'écrire** : elle exigeait que *chaque* remplacement fasse grandir le
fichier, or la correction de l'en-tête (« Restent les sources et le compte » →
« Reste le compte ») le **raccourcit** légitimement. La garde de croissance est
devenue **optionnelle par motif** — nulle pour une reformulation, exigée pour un
ajout —, la croissance globale restant vérifiée une fois pour toutes. Même famille
que le garde-fou du triple saut de ligne : un contrôle absolu appliqué à une
grandeur qui peut légitimement varier refuse un fichier sain.

### 9.26 L'écran du profil, et un canal d'avis qui ne disait rien

Le bloc précédent avait gelé le **modèle** de la carte du profil sans écrire
l'écran. Celui-ci monte l'écran — et il a fallu régler, au passage, une chose qui
n'avait rien à voir avec le profil.

**Un canal mort.** `AppViewModel.notice` est posé par six endroits : la carte du
profil, celle des notifications, l'affichage du Coran, l'accueil, la connexion.
Une seule vue le lisait — `SignInView`, qui le traite comme une erreur. Partout
ailleurs, l'application enregistrait, synchronisait, se déconnectait **en
silence**. La cause est simple : l'original affiche son avis dans un **toast
global** (`App.tsx:256`), monté à la racine de son interface, et ce toast n'avait
pas été porté. Il l'est — `Components.swift` gagne `NoticeToast`, et
`App/ContentView.swift` le monte **au-dessus de la porte d'authentification**,
jamais dans les onglets : monté dans les onglets, « Déconnecté. » disparaîtrait
avec eux, puisque `AuthGate` revient alors à `SignInView`.

Conséquence assumée : `SignInView` ne consomme plus `notice`. Il lit le texte
**rendu** par le modèle (`authenticate`), l'affiche à côté de ses champs quand
l'issue est un échec, et le laisse à l'avis global autrement. Poser `notice` dans
`authenticate` aurait fait apparaître « Tes données de ce compte ont été
retrouvées. » **en rouge** sur l'écran de connexion.

**Un écran qui ne décide rien.** `ProfileView` ne porte ni borne, ni comparaison,
ni unité : les sept textes de la carte viennent de `ProfileOptions`, et le bouton
d'enregistrement passe la saisie **brute** au modèle, qui applique sa garde. La
seule chose écrite dans le fichier est sa propre « chrome » — le titre de la
feuille, sa ligne de sous-titre, le libellé d'accessibilité du bouton — comme
`SettingsView` écrit la sienne.

**Ce qui n'est pas monté, et pourquoi.** La rangée d'avatar et ses trois boutons
de photo demandent le bucket `friend-avatars` et une écriture sur
`friend_profiles.avatar_path` : une vérification serveur que cette version ne fait
pas. Même discipline que le bouton « Vérifier le jeton push » (§9.23) : on ne
monte pas un bouton qui ne peut rien faire. Le formulaire de connexion, lui, est
déjà servi par `SignInView` — en monter un second donnerait **deux portes** pour
un même contrat, et la seconde serait inatteignable, `AuthGate` montrant
`SignInView` avant toute page.

**Une recette de bouton qui vivait trois fois.** Le style du bouton de carte était
recopié dans `SettingsView.settingsRow`, dans
`NotificationSettingsView.actionButton`, et l'écran du profil en demandait une
quatrième copie. Il vit désormais dans `CardButton`, et un contrôle **compte les
occurrences dans tout le dépôt** : une quatrième copie le fait échouer.

**Ce que ce bloc a appris**

- **Une garde de délimiteurs doit comparer le DELTA, pas l'absolu.**
  `ViewModels/AppViewModel.swift` porte **147** `(` pour **148** `)` — une
  parenthèse vit dans une chaîne ou un commentaire, et le fichier était donc
  déséquilibré **avant** toute retouche. Le banc `equilibre-delimiteurs.mjs` ne
  s'y trompe pas : il retire chaînes et commentaires avant de compter. La passe
  d'écriture, elle, exigeait l'équilibre absolu et refusait donc une édition
  juste, en accusant le mauvais coupable.
- **Une garde de croissance est fausse pour une dé-duplication.** La même passe
  exigeait que chaque fichier **grandisse** ; la factorisation de `SettingsView`
  le **raccourcit** de 144 octets. La garde est devenue « le fichier doit
  **changer** », avec le delta signé. Même famille que le triple saut de ligne :
  un contrôle absolu appliqué à une grandeur qui peut légitimement varier refuse
  un fichier sain.
- **Un contrôle de recopie doit lire le CODE, pas le fichier.** Trois échecs du
  nouveau banc venaient de ses **propres commentaires** : `ProfileView.swift`
  cite « Mon prénom » pour dire d'où vient le texte, et `canSignIn` pour dire
  pourquoi la branche n'est pas montée. Le banc retire donc les commentaires — de
  **tous** les fichiers Swift, car un contrôle « absent » qu'un commentaire suffit
  à faire échouer et un contrôle « présent » qu'un commentaire suffit à satisfaire
  sont faux tous les deux.
- **Un contrôle qui vise un motif trop large accuse la mauvaise chose.** Le
  contrôle « l'écran de connexion ne consomme plus `notice` » cherchait
  `if let notice = model.notice` dans tout `ContentView.swift` — motif qui vit
  **aussi** dans le garde du toast que ce bloc venait d'écrire. Il isole désormais
  la structure `SignInView` avant de l'interroger.
- **Un falsificateur attrape ses propres ancres fausses.** Une mutation visait
  `Text("Terminé")`, qui n'existe pas — c'est `Button("Terminé")`. La garde
  « MAL POSÉE » l'a refusée au lieu de la laisser passer pour un succès.
- **Le compte global a déménagé, et c'est le mécanisme.** `verifier-profil.mjs`
  affirmait « le dépôt porte 415 méthodes de test ». Il n'en porte plus le
  compte : celui-ci appartient au banc le plus récent, et à lui seul — ici
  `verifier-ecran-profil.mjs`, qui exige **416**.

### 9.27 Les trois cartes du profil, et une répartition qui n'était pas la bonne

Le bloc précédent a monté l'écran du profil. Il manquait, sous la carte du prénom,
**trois cartes** que `App.tsx:325-327` place dans la branche `profile`. Ce bloc-ci
les monte — et il a fallu, pour cela, défaire une répartition que §9.16 avait posée
« en attendant ».

**Une page pour deux modes.** `ProfileScreen` sert **deux** pages dans l'original :
`App.tsx:294` la rend avec `mode: 'profile' | 'settings'`, et `utilityView` décide
laquelle. La branche `settings` (lignes 329-350) porte les réglages ; la branche
`profile` (lignes 321-328) porte la carte du prénom **et** les cinq cartes
supplémentaires. Le portage avait rangé deux d'entre elles — « Connaissances » et
« Objectif et rythme » — dans `SettingsView`, sous un en-tête qui l'annonçait :
« tant que la page Profil n'existe pas ». La page existe. Un `grep` sur tout le
dépôt ne trouve plus `Connaissances`, `Modifier mes connaissances` ni
`Modifier mon programme` ailleurs qu'à `App.tsx:325-326` : les deux cartes sont
retournées dans `ProfileView`, et l'en-tête de `SettingsView` dit désormais la
répartition de l'original. Sans ce déplacement, la même carte aurait eu **deux
chemins**, et le second aurait survécu à toute correction du premier.

**Ce qui n'est pas monté, et pourquoi.** Sur les cinq cartes, deux restent
absentes. « Mes récitations » (`openRecitations`) n'ouvre pas un écran mais un
enregistreur, suivi d'un canal de corrections d'enseignant — rien de tout cela
n'existe ici. « Amis et entraide » appelle `updateSocialProfile`, dont le `PATCH`
n'est pas implémenté : `SupabaseRESTClient` n'a **pas** de méthode `update`. Même
discipline qu'au §9.26 : on ne monte pas une carte qui ne peut rien faire.

**`setReviewsEnabled` — trois décisions qui ne se voient pas.** L'interrupteur de
la carte « Apprentissage » (`App.tsx:327`) appelle `setReviewsEnabled(state, value)`
(`review.ts:53`). Trois choses s'y décident, et aucune n'est lisible à l'œil :

1. **un retour anticipé** — `if (reviewsEnabled(state) === enabled) return state`.
   Basculer vers la valeur **déjà en place** ne doit pas toucher le document, sans
   quoi `updatedAt` avancerait pour rien, et une fusion arbitrerait sur un
   horodatage qui ne correspond à aucun changement ;
2. **`cycleDays` est ré-épinglé**, non remis à 7 : `reviewCycleDays(state)` (repli
   7) conserve la durée choisie quand on éteint puis rallume ;
3. **`resumedAt` n'est daté qu'à l'allumage** — éteindre n'efface pas la date de
   reprise.

`resumedAt` est d'ailleurs **écrit et jamais lu** : dans l'original il n'apparaît
que dans le type `ReviewSettings` et dans cette fonction. Le portage l'écrit comme
l'original — l'absence d'un champ qu'on ne lit pas est invisible, et le retirer
aurait été une décision, non une fidélité.

**Une quatrième copie, et c'est elle qui décide.** `Pace(rawValue: pace)?.label ?? pace`
vivait à **trois** endroits (`ProgramView`, `ProgressScreenView`, `SettingsView`).
La carte « Objectif et rythme » en demandait une quatrième. L'idiome est extrait
dans `Core/Program.swift` (`Pace.displayed(_:)`), à côté de la définition de
`Pace`, et un contrôle refuse désormais **toute** occurrence de la forme brute dans
les vues. Les trois appelants passent par lui — dont `ProfileOptions.goalAndPace`,
qui compose la ligne « objectif · rythme » : la vue ne choisit pas le libellé, elle
passe le rythme **stocké**.

**`CycleChoice`, né de deux rangées.** La rangée des durées de la carte
« Apprentissage » (`{days} j`) et celle du tableau de bord (`ReviewDashboard.tsx:24`,
`{days} jours`) sont la **même recette** de bouton (`theme.tsx:29`,
`small secondary={!selected}`). Elle vivait en clair dans `ReviewDashboardView` —
avec une **divergence** : texte non sélectionné en `text` au lieu de `green`, et un
`minHeight: 40` que l'original n'a pas. Elle vit maintenant dans `CycleChoice`, que
les deux rangées emploient.

**Ce que ce bloc a appris**

- **Un falsificateur attrape ce qu'un banc vert ne dit pas.** Trois mutants ont
  **survécu** à la première passe, et chacun accusait un vrai défaut du banc :
  `settings.cycleDays = reviewCycleDays(state)` apparaît **deux** fois dans
  `Review.swift`, et `return Program.touch(next)` **sept** fois — les contrôles
  portaient sur le fichier entier, donc casser `setReviewsEnabled` laissait un
  autre exemplaire satisfaire le motif. Ils portent désormais sur le **corps** de
  la fonction, et le banc dit où il s'arrête : ils prouvent que la fonction
  **porte** ces quatre décisions ; qu'elle se comporte comme le TypeScript, c'est
  l'oracle qui le dit, et lui porte sur la translittération.
- **`includes('struct CycleChoice')` est vrai de `struct CycleChoiceGone`.** Une
  sous-chaîne n'est pas un symbole. Le contrôle exige la forme de la déclaration
  (`struct CycleChoice:`), et, pour les **appels**, la parenthèse (`CycleChoice(`).
- **`includes('goalCard')` vérifiait une déclaration, pas un montage.**
  `private var goalCard: some View` porte le même jeton que l'appel : retirer la
  carte de la pile laissait le contrôle vert. Il exige maintenant les trois noms
  **à la suite**, ce qui est aussi l'ordre de `App.tsx:325-327`.
- **Un sujet qui déménage n'est pas un sujet perdu.** Deux contrôles de
  `verifier-reglages.mjs` §9 portaient sur les cartes déplacées. Les supprimer
  aurait retiré la couverture ; ils sont **re-établis** dans le nouveau banc, à
  l'endroit où la carte vit — et le témoin du banc quitté est recalé de 86 à 84,
  parce qu'un contrôle qui ne s'exécute pas ne prouve rien.
- **Un témoin neutralisé ne garde rien.** Le brouillon du nouveau banc portait
  `const EXPECTED = 0` **et** un garde `EXPECTED !== 0 &&` : le compte ne pouvait
  pas échouer. Le compte est mesuré (85), puis la trappe est retirée — et le
  falsificateur le prouve en retirant un contrôle, ce qui fait sortir le banc
  en **2**.
- **`codeSwift` garde les chaînes.** Une première version du banc les retirait
  aussi : un contrôle d'**absence** ne pouvait plus échouer, et un contrôle de
  **présence** devenait faux à l'envers — `Pace.displayed` est appelé **à
  l'intérieur** d'une interpolation, invisible une fois les chaînes retirées.

Banc : `_banc/verifier-cartes-profil.mjs` — **85 vérifications**, 0 échec, les neuf
bancs antérieurs rejoués. Falsificateur : `_banc/falsifier-cartes-profil.mjs` —
**21 mutations**, toutes tuées, arbre rendu intact. Tests : **416 → 422**.


### 9.28 Les marques-pages : un écran, deux portes, et une liste de sourates qui n'existait pas

#### Ce que le bloc a monté

`BookmarksScreen.tsx` (12 lignes) est un écran à part entière dans l'original :
`App.tsx:492` le rend **à la place** du lecteur quand `bookmarksOpen` est vrai. Il
liste les marque-pages visibles, en supprime un après confirmation, et
« Reprendre » ramène la lecture sur la page du verset.

Le portage ajoute `Features/Quran/BookmarksView.swift` et
`Core/BookmarkOptions.swift` (les onze textes), et l'ouvre depuis **deux**
endroits : le lecteur (`ReaderView`, un `fullScreenCover`) et l'onglet Coran
(`QuranScreenView`, une feuille). Les deux passent par la même règle de reprise,
`AppViewModel.resumeBookmark` — c'est ce qui garantit que la page **annoncée** par
la liste et celle que « Reprendre » **ouvre** sont la même.

#### Trois règles que le portage ne tenait pas

**1. `save` doit effacer `lastUsedAt` et `deletedAt`.**
`bookmarks.ts:8` construit un objet NEUF à sept clés — `verseId, surah, ayah,
page, sourcePages, createdAt, updatedAt` — qui ne reprend ni l'un ni l'autre. Le
portage les conservait. La conséquence est invisible et réelle : `visible` trie sur
`(lastUsedAt ?? updatedAt)`, donc ré-enregistrer une marque-page déjà reprise la
**déplaçait** dans la liste au lieu de la remettre à sa date d'écriture ; et
ré-enregistrer une marque-page supprimée ne la ressuscitait pas. L'oracle compare
les deux objets clé par clé, `null` et « clé absente » étant tenus pour la même
chose — `Codable` omet les optionnels nuls à l'encodage, la référence ne les écrit
pas du tout.

**2. La page d'une reprise n'est pas celle du moushaf.**
`sourceVersePage` (`sourceNavigation.ts:4`) traduit un VERSET en page pour
l'édition affichée. Le portage repliait sur `item.page`, c'est-à-dire la page du
**Coran de Médine** — y compris quand on lisait le **Coran 1441**. Mesuré sur les
fichiers livrés : les deux paginations diffèrent pour **56 versets sur 6236**, et le
premier est le 746 (Al Mâ'idah 77) — page 121 côté Médine, page **120** côté 1441.
Ouvrir la 121 dans le 1441 menait donc à un passage sans rapport, sans aucun
symptôme : la page s'affiche. `Core/QuranSourceNavigation.swift` porte désormais les
deux branches atteignables, et la règle vit **une seule fois** — la liste et la
reprise l'appellent toutes les deux.

**3. L'égalité de `visible` doit être départagée.**
L'original trie sur l'horodatage seul, sans départager les ex æquo — mais son entrée
n'est pas arbitraire : les clés de `state.bookmarks` sont des indices de tableau
(`"1"`, `"2"`, …), `Object.values` les rend en ordre **numérique croissant**, et
`Array.prototype.sort` est **stable**. Deux marques-pages de même horodatage restent
donc dans l'ordre croissant des versets. Swift ne donne ni l'un ni l'autre : un
`Dictionary` n'a pas d'ordre, `sorted(by:)` n'est pas stable. Sans le départage
explicite ajouté à `Bookmark.visible`, l'ordre de la liste divergerait de celui de
l'application React Native **sur le même document**. Le banc exécute le vrai
`visibleBookmarks` sur un ex æquo et compare l'ordre obtenu.

#### Une branche non portée, et pourquoi elle ne coûte rien

`sourceVersePage` a trois branches ; celle de `coranTest` — le moushaf de Tajwid —
n'est pas portée : `testVersePage` lit un index verset → pages construit depuis les
607 polices `.woff2` de `coranTest/model.ts`, que cette application n'embarque pas.
La branche est **inatteignable**, et c'est mesurable : `QuranEdition.isAvailable`
n'est vrai que pour `.medine` et `.coran1441`, et `QuranEdition.displayed(stored:)`
remplace toute autre préférence par `.medine` (§9.3). Un test le vérifie
explicitement, plutôt que de laisser croire à un support complet.

#### Une découverte : l'onglet Coran de l'original n'est pas celui qu'on croit

En lisant `MainScreens.tsx:28-33` pour brancher l'écran, une divergence de fond est
apparue. **`QuranScreen` — l'onglet « Coran » de l'original — est une liste de
sourates** : recherche, filtre Mecquoise/Médinoise, sélecteur `Liste / Juz' / Hizb`,
médaillon de numéro, carte « J'ai appris jusqu'à », carte de pied « Coran avec règles
de Tajwid », et un bouton flottant « Dernière lecture ».

Le portage n'en a **rien**. `QuranScreenView.swift` occupe la place mais porte autre
chose : le choix d'édition, l'installation du Coran 1441, la reprise, les
marque-pages. C'est une composition propre au portage — §9.22 le laissait entendre en
discutant la liste d'éditions, sans jamais dire que **l'écran entier** diffère.

Ce que le document en disait était faux, et l'était depuis le premier commit :

| Ligne | Ce qui était écrit | Ce qui est mesuré |
|---|---|---|
| §3, « Liste des sourates » | `✅` porté, fichiers `Core/Quran.swift`, `Features/Quran/QuranScreenView.swift` | **jamais construit** — le fichier n'en a jamais porté trace, pas même en `54b2674` |
| §3, « Liste des Juz' et des Hizb » | « l'interface liste seulement les sourates pour l'instant » | elle ne liste **rien** |

Preuve : aucune des neuf chaînes de `MainScreens.tsx:28-33` — « Rechercher une
sourate », « Aucun résultat », « Mecquoise », « Médinoise », « J'ai appris jusqu'à »,
« Dernière lecture », « Mushaf de Médine », « Liste des Juz' », « Liste des Hizb » —
n'existe dans le dépôt. Les **données** sont prêtes (`Surah.meaning`,
`Surah.arabic`, `Surah.isMeccan`, `Quran.juzs`, `Quran.quarters`) ; seul l'écran
manque. Les deux lignes du tableau sont corrigées, et l'écran est inscrit comme le
prochain bloc.

#### Deux points qu'il fallait savoir, dont un a été réglé depuis

- **`mergeBookmarks` était portée mais jamais appelée — elle l'est maintenant.**
  L'original ne l'appelle que depuis `reconcileState` (`program.ts:68`), qui n'était
  pas porté, et `offlineMerge.ts` — le chemin de fusion qui *est* porté — n'a
  **aucune** règle propre aux marque-pages. Le portage était donc fidèle mais
  **incomplet** : la fusion générique à trois voies traite `bookmarks` comme
  n'importe quelle carte d'objets. `Core/Reconcile.swift` (§9.32) porte
  `reconcileState` et `accountState`, et `Reconcile.mergeBookmarksRaw` est désormais
  **exercée** — côte à côte avec `Bookmark.merge`, que deux tests d'accord comparent.
- **Le texte d'état vide décrit un geste que ce portage n'a pas.**
  `BookmarksScreen.tsx:11` dit « Touche « Marque-page », puis un verset sur la
  page » : l'original a un mode de pose où l'on touche le verset exact. Le portage
  n'a pas ce mode — le bouton du lecteur marque le verset courant. La chaîne est
  conservée telle quelle (elle vient de la référence, et le banc l'épingle), et la
  divergence est bornée à une phrase.

Banc : `_banc/verifier-marques-pages.mjs` — **106 vérifications**, 0 échec, les dix
bancs antérieurs rejoués. Falsificateur : `_banc/falsifier-marques-pages.mjs` —
**21 mutations**, toutes tuées, arbre rendu intact. Tests : **422 → 454**.


### 9.29 La liste des sourates : deux règles de recherche, un filtre à moitié appliqué, et une porte que le portage avait inventée

`QuranScreen` (`src/ui/MainScreens.tsx:28-34`) est l'onglet « Coran » de l'original :
**114 sourates**, ou **30 Juz'**, ou **60 Hizb**, une recherche, un filtre de lieu de
révélation, une carte de progression, une carte de pied vers le Coran de Tajwid, et un
bouton flottant « Dernière lecture ». §9.28 avait montré que le portage occupait cette
place avec autre chose. Ce bloc-ci construit l'écran, et déplace ce qui l'occupait.

#### Ce que le bloc a monté

`Core/SurahListOptions.swift` porte tout ce qu'un écran ne doit pas décider : les trois
vues, le filtre, la dérivation des lignes, la pagination d'une division, la progression,
et les textes. `Features/Quran/SurahListView.swift` ne fait que rendre et déclencher des
effets — il ne porte **aucun** libellé : mesuré, ses sept chaînes littérales sont des
noms de symboles SF et un nom d'illustration.

Les blocs qui occupaient la place sont partis là où l'original les met :

| Ce qui était dans l'onglet Coran | Où c'est allé |
|---|---|
| le choix d'édition (`QuranEditionChooser`) | le lecteur et les réglages (§9.22) |
| l'installation du Coran 1441 | `Features/Quran/Coran1441InstallView.swift`, monté par le lecteur |
| la reprise de lecture en ligne | le bouton flottant « Dernière lecture » |
| la porte vers les marque-pages | **nulle part** — voir plus bas |

#### Les deux règles de recherche, et pourquoi elles ne se confondent pas

`MainScreens.tsx:31` porte **deux** recherches, dans deux branches d'un même ternaire :

- une **sourate** se cherche sur quatre champs concaténés —
  `` `${s.number} ${s.name} ${s.meaning} ${s.arabic}` `` ;
- une **division** se cherche sur trois autres —
  `` `${d.number} ${view} ${surahs[verseAt(d.start).surah-1].name}` `` — où le nom est
  celui de la sourate où la division **commence**, jamais de sa fin.

Le portage les tient séparées (`matches(_:query:filter:)` et
`matches(_:mode:query:)`), et c'est mesurable plutôt que cosmétique. Trois
conséquences, recomptées sur les fichiers livrés :

| Recherche | Ce qu'elle trouve |
|---|---|
| `"114"` sur les sourates | **1** — le numéro se cherche en `contains`, pas en égalité |
| `"1"` sur les sourates | **34** — 1, 10 à 19, 21, 31, … 114 |
| `"ouverture"` sur les sourates | **2** — la sourate 1 (« L'ouverture ») et la 94 |
| `"yâsîn"` sur les sourates | **0** — le nom s'écrit « Yâ Sîn », en **deux mots** |
| `"juz"` sur les Juz' | **30** — c'est un préfixe de « Juz’ » |
| `"juz'"` (apostrophe droite) | **0** — le libellé porte U+2019 |
| `"baqarah"` sur les Juz' | **2** — Al Baqarah ouvre les Juz' 2 **et** 3 |
| `"pages"` sur les Juz' | **0** — la signification n'est pas cherchée |

Une version « propre » qui unifierait les deux recherches compilerait, et
afficherait une liste plausible : simplement, ces huit nombres changeraient.

#### Le filtre ne s'applique qu'à une vue sur trois

Le filtre de lieu de révélation est testé **après** la recherche, et **seulement**
dans la branche des sourates — `filter==='all'||(filter==='meccan'?s.isMeccan:!s.isMeccan)`.
La branche des divisions ne le regarde pas du tout, et le bouton qui l'ouvre n'est
d'ailleurs rendu que dans la vue « Liste » (`view==='Liste'&&<IconButton name="filter-outline"`).

Le portage le tient par construction : `rows(mode:query:filter:edition:)` ne
**transmet** `filter` qu'à la branche des sourates. Un test le vérifie des deux
façons — par la forme du code, et par un compte : **30** Juz' et **60** Hizb quel
que soit le filtre.

#### La page d'une division n'est pas une arithmétique locale

« Pages X – Y » vient de `studyPage` (`studyProgress.ts:8`), qui est exactement
`QuranSourceNavigation.versePage` **sans** page connue — la fonction que la reprise
d'une marque-page emploie déjà (§9.28). Le portage **délègue** au lieu d'en écrire
une seconde : deux copies d'une même règle divergent en silence, et c'est le défaut
que ce portage venait de fermer ailleurs.

Le séparateur est un **cadratin** (U+2013) entouré de deux espaces, et non un trait
d'union : un œil ne fait pas la différence dans un écran, un `grep` la fait.

L'original résout cette page sur `state.reader?.mushaf` **brut**, y compris
`coranTest` — dont la pagination n'est pas portée. Le portage lui passe l'édition
**affichée** (`QuranEdition.displayed(stored:)`) : pour `traditional` et
`coran_1441`, les deux donnent la même page ; pour les trois éditions non rendues,
le repli est le Coran de Médine. Divergence bornée, la même que celle du lecteur
(§9.3).

#### Une porte en trop, que le portage avait inventée

En recalibrant les bancs, une découverte : l'onglet Coran du portage portait une
**seconde porte** vers « Mes marques-pages ». L'original n'en a qu'**une** —
`App.tsx:512`, `sessionPanel === 'bookmarks'`, un panneau du lecteur. `QuranScreen`
lui-même n'ouvre jamais `BookmarksScreen`.

C'était donc une entrée que l'application React Native ne connaît pas, et une
seconde liste à tenir d'accord. Elle a disparu avec l'écran qui la portait, et le
banc l'épingle désormais par un contrôle **négatif** : l'onglet Coran n'a aucune
porte, et le lecteur est la seule. Trois contrôles et trois mutations ont été
repointés en conséquence dans `verifier-marques-pages.mjs` et son falsificateur.

#### « J'ai appris jusqu'à » prend le plus grand verset, pas le plus récent

`const known=memorizedIds(state),last=known.length?Math.max(...known):null`. La
règle est **`Math.max`**, pas la date de validation : `memorizedIds` retient
`perfect` et `review` (`program.ts:138`), jamais `learning`, et le libellé nomme le
**plus grand identifiant** mémorisé. Un test le vérifie par la négative — un petit
verset validé **plus récemment** ne gagne pas — et c'est bien `memorizedIDs.last`
d'une liste **triée** qui le porte, puisque `Dictionary` n'est pas ordonné en Swift.

#### Le défaut que seul le flux pouvait voir

Le run n° 67 a **échoué**, sur treize tests — et il a trouvé un défaut réel, pas une
faute de test. En JavaScript, `''.includes('')` vaut `true` ; en Swift,
`"abc".contains("")` vaut **false**. Les deux recherches portaient donc
`haystack.lowercased().contains(query.lowercased())` : une requête vide ne trouvait
**rien**. Or la recherche part toujours vide — c'est la requête sur laquelle l'écran
s'ouvre. L'onglet Coran s'affichait donc **vide**, et c'était le cas normal, pas un
cas limite.

Le banc ne pouvait pas le voir, et il le disait : il relit le source et rejoue les
règles **en JavaScript**. C'est l'exécution du langage qui manquait, et c'est
exactement ce que l'intégration continue apporte. Le corollaire est plus utile que le
défaut : **un banc qui rejoue l'original ne prouve rien du portage** — il faut, pour
chaque règle, un contrôle qui regarde ce que le langage en fait.

Deux contrôles (un par recherche, lisant le **corps** de la fonction) et deux
mutations font désormais tomber ce défaut **en local**, en quelques secondes. Les
mutations M02 et M03, dont l'ancre citait la ligne remplacée, ont été repointées sur
la nouvelle garde : c'est le pré-vol des ancres qui l'a dit, avant toute écriture.

Banc : `_banc/verifier-liste-sourates.mjs` — **135 vérifications**, 0 échec, les
**onze** bancs antérieurs rejoués. Falsificateur : `_banc/falsifier-liste-sourates.mjs`
— **30 mutations**, toutes tuées, arbre rendu intact. Tests : **454 → 502**, dont
**48** pour `Tests/SurahListTests.swift`.

### 9.30 Le Tajweed : une unité de comptage qui n'est pas celle de Swift, et deux pièges de vérité

`src/core/readerData.ts` tient trois fonctions — `tajweedVerse`, `tajweedSpans`,
`tajweedColor` — et `MushafPage.tsx:34-43` le rendu qui les emploie. L'édition
`tajweed` (« Lecture simplifiée ») n'est pas une page : l'original la fait passer par
le rendu **verset par verset**, celui des cartes de verset. Ses données étaient
**déjà** dans ce dépôt — `tajweed-text.json` (1 531 274 octets), `tajweed-rules.json`
(2 755 691), `translation-fr-rashid.json` (1 522 305) — et **aucun** code Swift ne les
lisait. Ce bloc-ci porte le modèle et l'épingle ; le rendu viendra au bloc suivant (§9.31).

#### L'unité de comptage : le seul point où le portage pouvait planter

Les `start` / `end` des annotations indexent le texte. En JavaScript, `[...text]`
découpe en **points de code** ; en Swift, `Array(text)` découpe en **graphèmes** — une
lettre arabe suivie de ses harakat est UN graphème pour plusieurs points de code.

Mesuré sur les 6 236 versets : points de code et unités UTF-16 coïncident partout
(0 écart), mais points de code et graphèmes diffèrent sur **6 236 versets sur 6 236**.
Le verset 2:282 (identifiant 289) porte **1 173** points de code pour **680** graphèmes,
et sa plus grande fin d'annotation vaut **1 171** :

```
1 171 > 680    →  indexer en `Character` sortirait du tableau, donc planterait
1 171 ≤ 1 173  →  indexer en scalaires y reste
```

Le défaut aurait frappé sur le plus long verset du Coran — précisément celui qu'on
ouvre pour vérifier. `TajweedOptions.spans` indexe donc en `Unicode.Scalar`, et un
test épingle les trois nombres. Le nombre de 680 vient d'`Intl.Segmenter` (ICU,
UAX #29), une implémentation **indépendante** de celle de Swift : c'est une
contre-mesure, pas une reformulation.

#### Trois règles silencieuses de plus

- **La fusion se fait sur l'égalité de la RÈGLE**, pas sur l'identité de
  l'annotation. Mesuré : 42:2 porte trois annotations `madd_6` voisines et rend **un**
  fragment, pas trois.
- **Un verset sans annotation rend UN fragment nu**, pas zéro — 63 versets sont dans
  ce cas (`annotations: []`). Rendre `[]` laisserait la carte sans texte.
- **Mais « un fragment » ne veut pas dire « sans règle »** : mesuré, **un seul** verset
  (4274, 42:2) rend un fragment unique *coloré*. Le contre-exemple est épinglé à côté
  du cas nu, pour qu'un raccourci — « `count == 1` donc nu » — casse au lieu de passer.

L'ordre des six branches de `tajweedColor` est la règle, pas un goût : deux préfixes
sont testés avant les égalités. Mesuré sur les 18 règles livrées : 5 par `madd`,
3 par `ikhfa`/`iqlab`, 6 par `idghaam`/`ghunnah`, 1 par `qalqalah`, 1 par `silent`, et
**2** dans le défaut — `hamzat_wasl` (13 252 annotations) et `lam_shamsiyyah`
(2 733), les deux plus fréquentes du Moushaf. Une règle inconnue y tombe aussi, sans
rien dire : c'est le comportement de l'original, et le figer vaut mieux que le
découvrir.

#### Le piège de vérité : `footnotes` vaut `""` sur 4 906 lignes

`translation-fr-rashid.json` porte la clé `footnotes` sur les **6 236** lignes, et elle
vaut `""` sur **4 906** d'entre elles. L'original écrit
`translation?.footnotes ? <Label> : null` (`MushafPage.tsx:38`) : une chaîne **vide**
est fausse en JavaScript, donc la note ne s'affiche pas.

Un `String?` décodé, lui, rendrait `Optional("")` — non `nil` — et un `if let`
l'aurait affichée : **4 906 notes vides**, et un blanc de plus sous chacune. C'est la
même famille que `''.includes('')` de §9.29 — la **vérité** opposée à la **présence** —
sauf qu'ici l'écart vit dans une donnée et non dans un appel. `Translation.footnote`
rend donc `nil` sur `""`, et un test oppose explicitement les deux sur le même verset.

#### L'édition était alors NON PROPOSÉE, et c'était délibéré

`QuranEdition.isAvailable` rendait alors `false` pour `.tajweed`, et `imageURLs` n'avait
aucune branche pour elle. Le modèle était porté ; le **rendu** ne l'était pas. Proposer
l'édition à ce moment-là aurait ouvert des cartes vides — exactement le défaut que
§9.28 avait corrigé pour `coranTest`. Deux contrôles du banc interdisaient ce dérapage :
`isAvailable` devait rester faux, et **aucun écran** ne devait appeler `TajweedOptions`.

La prédiction qui fermait ce paragraphe s'est vérifiée : « le jour où le rendu arrive, ces
deux contrôles tomberont — et c'est alors qu'il faudra les retourner ». §9.31 est ce jour,
et les deux contrôles ont été **retournés**, non supprimés : l'un exige désormais que
`isAvailable` lise les données, l'autre qu'**exactement un** écran appelle le modèle.

#### Ce que ce banc ne peut pas prouver, et qui est écrit dans son en-tête

Le banc rejoue `readerData.ts` **en JavaScript** : il prouve ce que fait l'original, pas
ce que fait le portage. C'est la leçon de §9.29, et elle est répétée dans l'en-tête de
`verifier-tajweed.mjs`. Ce que le banc vérifie est donc de deux ordres : la **forme** du
Swift — indexation en scalaires, fusion par règle, garde de concordance, ordre des six
branches, garde du vide — et la **concordance** des nombres entre les données et
`Tests/TajweedTests.swift`. Ce qui reste à l'intégration continue est le comportement :
25 tests, dont celui des 1 173 / 680 / 1 171.

`QuranSourceNavigation` n'a **pas** été touché : `.tajweed` reste rangé avec les
éditions paginées, et c'est **fidèle** — `isZipSource(source)` ne vaut que pour
`coran_1441` (`quranSources.ts:6`), donc `sourceVersePage('tajweed', …)` retombe sur
`pageOf(id)` dans l'original aussi. La page d'un verset en Tajweed est donc sa page du
Coran de Médine, et c'est cette page qui choisit la plage de versets affichée
(`MushafPage.tsx:31`). Un contrôle du banc compare les deux sources pour figer cet
accord, plutôt que de « corriger » un portage qui était juste.

#### Le run n° 69 est tombé, sur une faute de type qu'aucun banc ne pouvait voir

La poussée du bloc a produit le run n° **69** : `failure` en **2 min 5 s**, l'étape « Jouer
les tests » rouge. Ce n'était **pas** un test qui échouait — c'était la **compilation** du
fichier de test. Deux erreurs, lignes 209 et 210 de `Tests/TajweedTests.swift` :

```
error: value of tuple type '(text: String, annotations: [TajweedOptions.Annotation])' has no member 'surah'
error: value of tuple type '(text: String, annotations: [TajweedOptions.Annotation])' has no member 'ayah'
```

Le test lisait `verse?.surah` sur le tuple que rend `TajweedOptions.verse(_:)`, lequel ne porte
que `text` et `annotations`. Les coordonnées d'un verset vivent dans la table du Coran, et
c'est là que `verseLabel` les prend déjà : la correction lit `Quran.verses[versetFusionne - 1]`
— aucune API ajoutée, contrat du modèle inchangé.

C'est le pendant exact de la leçon de §9.29. Là, un banc qui **rejoue l'original** ne prouve
rien du portage ; ici, **un banc qui lit du texte ne prouve rien de la compilation**. Les
quatre outils locaux — `equilibre-delimiteurs`, `coherence-swift`, `verifier-tajweed`,
`falsifier-tajweed` — lisent tous du **texte** : ils comptent des délimiteurs, des noms de
types, des lignes de données. Aucun ne type-vérifie, et une faute de **type** n'a aucune
signature textuelle. Le banc était donc vert — ses **120** contrôles — pendant que le code ne
compilait pas. La seule autorité reste `.github/workflows/ios.yml`.

Corollaire, et il vaut pour tout ce document : le compte de **527** tests que le banc annonçait
n'a **pas** été mesuré au n° 69, l'exécution s'étant arrêtée avant. Une **prédiction** n'est pas
une mesure, même quand elle se vérifie ensuite.

**La garde ajoutée, et ce qu'elle avoue.** Le banc porte maintenant un contrôle **proxy** :
dans `Tests/TajweedTests.swift`, toute ligne lisant `.surah` ou `.ayah` doit la lire sur
`TajweedOptions.translation(…)` ou sur `Quran.verses`. Il ne type-vérifie pas — il dit où il
s'arrête : ce sont les deux seules **sources** de coordonnées admises dans ce fichier. Deux
contrôles l'encadrent : l'un épingle la **forme du tuple** (`text: String, annotations:
[Annotation]`), pour que le proxy rougisse le jour où `verse(_:)` porterait `surah` au lieu de
survivre en silence ; l'autre vérifie qu'il **n'est pas vide** (quatre lignes concernées).
Mutation **M29** ajoutée pour l'éprouver : elle réintroduit `verse?.surah`, et le proxy la tue.

Banc : `_banc/verifier-tajweed.mjs` — **120 vérifications**, 0 échec, les **douze**
bancs antérieurs rejoués. Falsificateur : `_banc/falsifier-tajweed.mjs` — **29
mutations**, toutes tuées, arbre rendu intact. Tests : **502 → 527**, dont **25** pour
`Tests/TajweedTests.swift`.

### 9.31 Le rendu verset par verset : une édition qui n'est pas une page, et deux contrôles retournés

§9.30 a porté le **modèle** du Tajweed et laissé le rendu à écrire, en fermant sur une
prédiction : « le jour où le rendu arrive, ces deux contrôles tomberont — et c'est alors
qu'il faudra les retourner ». Ce bloc-ci est ce jour. Il fait **deux moitiés d'un seul
changement**, et il faut dire pourquoi elles ne se séparent pas.

#### Un rendu qu'aucun écran ne pouvait atteindre

`ReaderView` reçoit son édition **fixée à la construction**, et cette valeur vient de
`QuranEdition.displayed(stored:)`, qui rend `edition.isAvailable ? edition : repli`.
Tant que `.tajweed.isAvailable` valait `false`, `ReaderView` ne pouvait **jamais**
recevoir `.tajweed` : la liste n'aurait été dessinée nulle part. Écrire le rendu sans
retourner l'offre aurait donc produit du code **inatteignable** ; retourner l'offre sans
écrire le rendu aurait ouvert des cartes vides, le défaut de §9.28. Les deux moitiés
sont un seul bloc parce qu'aucune n'a de sens seule.

#### L'offre ne peut pas être une constante

Le réflexe serait `case .tajweed: return true`. C'est faux, et c'est le même piège que
`coranTest` : une constante **offerte** ne dit rien de la présence des données. La
condition est donc une **lecture** :

```swift
case .tajweed: return TajweedOptions.isAvailable
```

et `TajweedOptions.isAvailable` vaut `hasArabic && hasTranslation`, c'est-à-dire les trois
JSON du Tajweed présents dans le paquet — `tajweed-text`, `tajweed-rules`,
`translation-fr-rashid`. Si l'un manquait, l'édition disparaîtrait d'elle-même. Un
contrôle du banc exige cette **forme** (la lecture, pas la constante) ; un autre exige la
**conjonction** des deux présences, et une mutation (M35) retire le second terme pour
vérifier que le contrôle le voit.

#### Le rendu n'est pas une page, et c'est structurel

`MushafPage.tsx:34-43` a une branche propre pour `mode === 'tajweed'` : un fond `soft`
arrondi, un en-tête doré centré, puis **une carte par verset**. Une page du moushaf porte
une image ; le Tajweed porte du texte, et une page peut compter **286 versets**. `App.tsx:499`
le dit sans ambiguïté : `scrollEnabled={mushaf==='tajweed'}`,
`height={mushaf==='tajweed'?readerViewport.height:fit.height}`,
`flexGrow={mushaf==='tajweed'?1:0}`. Sans défilement, une telle page serait **coupée**.

Le défilement est donc **structurel**, et il interdit de loger cette liste dans le
`UIPageViewController` : `ReaderView.body` a gagné une **troisième forme** — un
`if edition == .tajweed { TajweedVerseListView(…) } else { MushafPageController(…) }`,
plat, dans le `ZStack` existant. Plat, et non un nouveau `@ViewBuilder` : au-delà de dix
enfants, Swift cesse de type-vérifier le surplus.

#### Quatre décisions du rendu, dont une qui change un type

**Les couleurs des cartes sont des littéraux, et ce ne sont pas celles de la page.**
`difficult ? '#FCE8E8' : marque-page ? selected : sélection ? selected : paper`, bordure
`difficult ? 1 : 0`, `borderColor: difficult ? '#D97878' : colors.green2`. Ce rouge **n'est
pas** `VerseHighlightStyle.difficultRed` (`#E85B5B`), qui est la couleur de **surlignage
sur la page** : deux rouges, deux usages, et un test les oppose nommément.

**`color(of:textColor:)` a changé de type.** La fonction rendait une `String` ; elle rend
désormais une `Color` — `(Span, Color) -> Color`. La raison n'est pas esthétique :
`Theme.color(hexString:)` rend `nil` sur une chaîne invalide, et **aucune table de cette
application ne porte la couleur de texte d'un thème sous forme hexadécimale** —
`Palette.text` est une `Color`. Prendre une `String` aurait obligé la vue à **fabriquer**
un hexadécimal que rien ne vérifie : une seconde source pour la même vérité. La table des
règles, elle, **reste une chaîne** (`color(_ rule: String) -> String`) pour que le banc
puisse la comparer au fichier de référence.

**`lineSpacing` n'est pas `lineHeight`.** Le `lineHeight` de l'original est **absolu**
(`{fontSize:16, lineHeight:25}`) ; le `lineSpacing` de SwiftUI est **additif**. La
traduction est donc `max(0, lineHeight − UIFont.systemFont(ofSize: fontSize).lineHeight)`,
et son invariant est vérifiable : `UIFont.lineHeight + lineSpacing == lineHeight`. Un test
le mesure aux tailles employées (25, 31.2, 34, 16).

**Le rail de séance de la liste n'est pas celui de la marge.** `MushafPage.tsx:41` lit
`plainPositions[id]`, rempli par le `onLayout` de **chaque carte** : une barre de la
première carte active au **bas de la dernière**, et **un point par verset actif** — vingt
pixels, rempli jusqu'à `sessionThrough` inclus. `MarginAnnotations`, lui, regroupe par
proximité et couvre des **groupes**. Confondre les deux donne un rail plausible et faux.
Un test par règle : la barre, les points, leur ordre, le remplissage, et l'absence de rail
quand aucun verset n'est actif.

#### Ce qui n'est pas porté, et qui est écrit dans l'en-tête du fichier

Le geste de balayage (`swipe.panHandlers`), le bandeau d'étude (`studyBanner`) et le zoom
(`ZoomableReader`) : le rendu reçoit `textScale` mais le tient à `1`. L'original les a ;
ils ne sont pas dans ce bloc, et le fichier le dit plutôt que de le taire.

#### Les deux contrôles retournés, et les six assertions qui les suivaient

Retourner l'offre a fait tomber **huit** affirmations, pas deux : les deux contrôles du
banc, et **six** assertions de tests qui disaient la même chose dans quatre fichiers —
`QuranEditionTests` (deux), `QuranSourceNavigationTests` (une), `QuranDisplayTests`
(trois). C'est la trace que laisse une migration bloquée : les assertions de l'ancienne
application continuent d'affirmer ses contraintes.

Elles ont été **retournées**, pas supprimées. Le contrôle des appelants méritait d'être
revu pour lui-même : il ne testait qu'une **longueur** (`appelants.length === 0`) et jamais
la **valeur** de l'élément — il ne pouvait donc pas distinguer « aucun appelant » de
« un mauvais appelant », deux défauts différents. Il exige maintenant **exactement un**
appelant, et le **nomme**. C'est ce qui a fait apparaître un défaut du contrôle lui-même :
`path.relative` rend des **antislashs** sous Windows, si bien que la comparaison au chemin
littéral échouait — invisible tant que le contrôle ne comparait qu'un nombre.

Deux autres garde-fous ont été ajoutés, chacun contre un faux verdict : un contrôle de
**non-vacuité** sur les ancres de `funcBody` (le changement de signature de
`color(of:textColor:)` avait rendu une ancre muette, et un contrôle qui cherche dans une
chaîne vide échoue pour la **mauvaise raison**), et la qualification des deux repères
`TajweedOptions.ornament)` / `TajweedOptions.ornamentGap)` — le premier est un **préfixe**
du second, donc un repère nu aurait été satisfait par la mauvaise constante.

#### Le run n° 71 est tombé, sur une règle d'API que le texte POUVAIT voir

La poussée du bloc a produit le run n° **71** : `failure` en **57 s**, l'étape
« Compiler (simulateur) » rouge, une **seule** erreur —

```
error: extra argument 'minHeight' in call
```

`TajweedVerseListView.swift:294` écrivait `.frame(width: largeur, minHeight: hauteur,
alignment: .top)`. Or **cette surcharge n'existe pas** : `frame` en a deux, `width`/`height`
et la famille `minWidth`/`idealWidth`/`maxWidth`/`minHeight`/`idealHeight`/`maxHeight` —
et jamais un mélange. La correction fixe la largeur par `minWidth == maxWidth` et la
hauteur seulement **plancher** par `minHeight` : c'est exactement `width` + `minHeight` de
l'original. Neuf étapes sur quatorze étaient vertes avant celle-ci, dont celle qui vérifie
que la configuration Supabase atteint la compilation — le défaut était bien unique.

Ce run vaut par ce qu'il apprend sur la **frontière** tracée au n° 69. Là, une faute de
**type** n'avait aucune signature textuelle, et le banc ne pouvait rien en dire. Ici la faute
est d'**API**, et sa règle est **purement syntaxique** : un appel qui porte `width:` *et*
`minHeight:` ne peut pas compiler, et cela se **lit**. Le banc porte donc désormais ce
contrôle, sur **tout le projet** — 90 appels `frame(…)` analysés —, avec le témoin de
non-vacuité qui l'accompagne. La leçon se précise : ce n'est pas « le texte ne peut rien dire
de la compilation », c'est « le texte dit ce qui a une **signature** textuelle ». Un type
n'en a pas ; une surcharge, si.

#### Le run n° 72 a trouvé l'invariant qu'on avait oublié de retourner

La poussée du correctif a produit le run n° **72** : `failure` en **6 min 25 s**, la
**compilation verte** — l'étape qui était tombée au n° 71 — et l'étape « Jouer les
tests » rouge sur **un** échec, pour **542** tests exécutés :

```
Tests/QuranEditionTests.swift:122: error: -[QuranEditionTests
testWhateverIsStoredTheDisplayedEditionIsRenderable] : XCTAssertNotNil failed
- tajweed n'a pas de rectangles : aucune mise en évidence possible
```

C'est une **septième** assertion que le retournement avait manquée. Le bloc avait retourné
deux contrôles du banc et **six** assertions écrites — mais celle-ci était **dérivée** :
son libellé parlait de « l'édition affichée », et son corps exigeait `boundsSource` de
**toute** édition affichée. Elle disait vrai tant que la liste n'existait pas ; le jour où
`.tajweed` est devenu affichable, elle est devenue fausse — **sans qu'aucune de ses
lignes n'ait changé**. C'est la leçon de §9.28 : une assertion qui survit à l'état qu'elle
visait ne protège plus rien, elle interdit le progrès. Et la leçon de §9.30 : les six
assertions qu'on avait su retourner étaient celles qui **nommaient** l'édition ; la
septième ne la nommait pas.

**La réparation dit les deux façons de rendre, au lieu d'en choisir une.** `QuranEdition`
porte maintenant `isVerseList` — une seule édition, `.tajweed` — et `isRenderable`, qui
rend `isVerseList ? TajweedOptions.isAvailable : boundsSource != nil`. L'invariant se
vérifie alors en **deux branches** : une édition paginée doit savoir où sont ses versets ;
une édition en cartes n'a **pas** de rectangles et ne doit pas en avoir — une bande y
serait posée sur une page qui n'existe pas. Un second test,
`testTheVerseListEditionIsTheOnlyOneWithoutRectangles`, dit **qui** a le droit de n'avoir
aucun rectangle : sans lui, une édition future pourrait perdre son `boundsSource` sans que
rien ne le signale, puisque le test ci-dessus la laisserait passer en la croyant en cartes.

#### Les nombres

Banc : `_banc/verifier-tajweed.mjs` — **141 vérifications**, 0 échec, les **treize** bancs
antérieurs rejoués. Falsificateur : `_banc/falsifier-tajweed.mjs` — **37 mutations**, dont
**huit** ajoutées ici (M30 le routage, M31 le défilement, M32 l'ornement, M33 un test
retiré, M34 le type de retour, M35 la condition de présence, M36 la surcharge `frame`,
M37 la seule édition en cartes), toutes tuées, arbre rendu intact. Tests : **527 → 543**,
dont **15** pour `Tests/TajweedListTests.swift`.

### 9.32 La réconciliation : une fonction que rien n'appelait, sept règles d'absence, et un défaut latent trouvé par un test d'accord

`src/core/program.ts:48-130` porte trois fonctions qui décident **laquelle des deux
applications gagne** sur le document partagé : `migrateReaderState` réécrit les clés
d'édition héritées avant tout, `reconcileState` fusionne un document local et un document
distant quand les deux existent, et `accountState` choisit entre le cache local et le
document du serveur à la connexion. Jusqu'ici, ce portage n'en avait **aucune** : il
écrivait le document distant tel quel. `Core/Reconcile.swift` les porte toutes les trois.

C'est aussi le **seul** appelant de `mergeBookmarks` — la fonction dont §9.28 disait qu'elle
était « portée mais jamais appelée ». Elle l'est désormais.

#### Pourquoi du JSON brut, et non des structures

Sept comparaisons de l'original testent `=== undefined`, et ce n'est pas un détail de
style : `uiFont`, `accent`, `studyProgress`, `reviewCycle`, `reviewConsolidations`,
`reviewPriorityDue` et `reader.testPage`. Une structure Swift **écrase** la différence
entre « clé absente » et « clé à `null` » — les deux deviennent `nil` —, donc un portage
typé répondrait `true` là où l'original répond `false`. La conséquence n'est pas
théorique : un `reviewCycle` que l'utilisateur a remis à `null` **ressusciterait** au
premier chargement. Le document circule donc comme un `JSONValue`, et non comme un
`AppState` — ce que l'en-tête de `Core/JSONValue.swift` annonçait depuis le premier jour :
une clé absente et une clé nulle ne sont pas la même chose.

#### Une seconde règle, mesurée : `undefined` **retire** la clé du document écrit

`JSON.stringify` **supprime** une clé dont la valeur est `undefined` :
`{...remote, profile: undefined}` garde `profile` en mémoire mais le document **sérialisé**
ne le porte plus. Or c'est le document sérialisé que l'autre application lira — `result
.document` en mémoire n'est pas l'observable. La fonction qui pose une clé la **retire**
donc quand la valeur est absente, là où écrire `.null` **ajouterait** une clé que
l'application React Native n'écrit jamais.

Et parce que l'opérateur `??` de JavaScript rend son opérande droit **tel quel**, un
`profile: null` distant est bel et bien recopié : la distinction n'est pas contournée, elle
est **reproduite**. Un premier jet de test se trompait exactement là — il vérifiait
l'absence de la clé sur le document **en mémoire**, où elle est encore présente. Le banc
juge désormais sur le document **sérialisé**, et l'oracle a été muni d'un
`documentSerialise()` pour que le cas ne puisse pas se rejouer.

#### Le piège du bloc : un ternaire isolé

Partout la famille des métadonnées se replie sur `??` — remplacé par `recover` — sauf
`reviewCycle`, qui seul écrit `remote.reviewCycle === undefined ? local.reviewCycle :
remote.reviewCycle` : il teste la **présence** de la clé, pas sa nullité, et **garde donc
un `null` distant**. Le porter avec le même `recover` que ses six voisins aurait été le
contresens exact. Le banc porte un contrôle **négatif** qui interdit cette écriture-là, et
la mutation correspondante (M01) est tuée.

#### Deux implémentations d'une même règle, et pourquoi les deux restent

`Bookmark.merge` travaille sur des structures, `Reconcile.mergeBookmarksRaw` sur le JSON ;
`Program.migrateReaderState` sur des structures, `Reconcile.migrateRaw` sur le JSON. Les
versions **brutes** gagnent sur le chemin d'écriture, pour deux raisons : elles ne
réencodent pas un document qu'on s'apprête à écrire, et elles **préservent** les champs
inconnus d'une entrée de marque-page qu'une structure perdrait en silence. Les versions
typées restent, parce qu'elles sont le modèle du reste de l'application — et parce que les
comparer est une preuve. Deux tests d'**accord** les mettent côte à côte, chacun avec son
**témoin de non-vacuité** :

```swift
XCTAssertEqual(compared, pairs.count, "aucune paire comparée : le test serait vide")
XCTAssertEqual(compared, readers.count, "aucun document comparé : le test serait vide")
```

Un test d'accord qui ne compare rien est vert, et ne dit rien. Ces deux lignes sont ce qui
l'empêche.

#### Le défaut latent que le test d'accord a trouvé

`Program.migrateReaderState` lisait `state.reader?.mushaf`. C'est un enchaînement
facultatif, et il **ne crée pas** l'objet `reader` — contrairement au
`{...state.reader, mushaf: …}` de l'original, qui en crée un vide pour y poser la clé. Sur
un lecteur **absent**, la migration typée ne faisait donc **rien** quand la référence
**crée** l'objet. Le défaut était invisible parce que rien n'appelait la migration depuis un
lecteur absent — c'est le test d'accord, écrit pour vérifier autre chose, qui l'a mis au
jour. La correction tient en une ligne :

```swift
var reader = next.reader ?? ReaderPreferences(mushaf: "coranTest", followAudio: true)
```

avec un commentaire qui nomme le défaut et le test qui le garde.

#### La preuve : un oracle **exécuté**, pas une transcription

`_banc/oracle-reconcile.mjs` **découpe** les trois fonctions dans le fichier de référence,
retire les annotations de type nommées une à une (cinq signatures, la flèche typée
`(): AppState =>`, `state.reader?.mushaf as string`, l'assertion non-nulle `state.reader!`),
et les **exécute** via `new Function`. Il porte **22 cas**, et chaque cas transporte, dans
sa clé `observations`, le **texte exact** de l'assertion Swift qu'il doit confirmer.

C'est ce qui a trouvé **deux défauts réels dans mes propres tests**. Deux cas mesuraient un
horodatage en prenant `theme` pour la différence locale — or le distant gagne **toujours**
`theme` (`remote.theme ?? local.theme`), donc le retour anticipé « rien à pousser » se
déclenchait **avant** le recalcul de l'horodatage, et le test lisait la valeur brute du
distant. Une transcription n'aurait rien vu : elle aurait recopié l'erreur avec le reste du
fichier. C'est la différence entre recopier une règle et la faire tourner.

Une limite, écrite dans l'en-tête de l'oracle : `state.sessions.some(…)` lève un
`TypeError` sur une clé absente, donc les cas de l'oracle **doivent** porter `sessions: []`.
L'application réelle, elle, le garantit — `defaultState` l'écrit et `loadState` exige un
tableau. C'est un danger **de l'oracle seul**, pas du portage.

#### Et un vrai défaut dans le chemin de synchronisation

`Repositories/AppStateRepository.applyRemote` adoptait `rawState = remote` — le document
distant **brut** — au lieu du document **réconcilié** que `accountState` venait de
calculer ; et rien ne **poussait** le résultat quand la réconciliation le demandait. Les
deux sont corrigés : `applyRemote` rend maintenant le `shouldPush` de la réconciliation, et
`StateSyncService.syncOnSignIn` enqueue le document courant quand il vaut `true`. Sans cela,
le portage aurait porté la fonction qui décide, et continué d'écrire la mauvaise réponse.

#### Le run n° 74 est tombé, et il avait raison deux fois

La compilation est passée, et **trois assertions** sont tombées sur **585** tests exécutés —
le compte est donc **mesuré**, et il vaut celui que le banc annonçait. Les trois sont dans
mes propres tests, et le portage était juste dans les deux cas.

**Le premier est le plus instructif.** `testNoRemoteKeepsTheLocalDocumentAndPushes` attendait
le local **tel quel** : `XCTAssertEqual(outcome.document, local)`. Or la référence écrit
`local = migrateReaderState(local)` **avant** `if (!remote)`, donc un lecteur **absent** est
**créé** — `{...undefined}` vaut `{}` en JavaScript, et `undefined !== false` vaut `true`. Le
document rendu porte donc un `reader` que le test ne prévoyait pas.

**Ce qui a laissé passer ce test mérite d'être écrit, parce que c'est un défaut de la preuve
et non du code.** L'oracle portait bien le cas, et son entrée était la bonne — un local sans
lecteur. Mais son observation jugeait `state.theme` sous l'étiquette
`XCTAssertEqual(outcome.document, local)` : **un champ unique mesuré sous le nom d'une
assertion portant sur tout le document**. Le cas disait « l'original rend `night` », donc
« vrai », tandis que l'assertion Swift affirmait quelque chose de plus fort, et de faux. Un
`texte` doit mesurer **exactement le chemin qu'il nomme**, sinon un cas vert couvre une
assertion fausse. Les quatre observations du cas nomment maintenant chacune son assertion — et
l'oracle **dit** que l'original crée le lecteur (`state.reader.mushaf="coranTest"`).

**Et aucun contrôle du banc ne visait cette création.** Le banc pinçait celle de la migration
**typée** (`Program.migrateReaderState`), pas celle de la migration **brute** — le trou exact
par lequel le défaut est passé. Un contrôle les épingle toutes les deux désormais, et la
mutation **M32** retire la création brute : elle est tuée.

**Le second défaut est une attente retournée.** `testTheRawDefaultIsNotTheTypedDefault`
affirmait que la sérialisation typée « écrit un `null` ». Mesuré : elle **omet** la clé —
`Codable` synthétisé passe par `encodeIfPresent`, donc une propriété optionnelle nulle
disparaît du JSON. C'est le document **brut**, et lui seul, qui écrit `reviewCycle: null`. La
distinction est celle de tout ce bloc : `reconcileState` teste
`remote.reviewCycle === undefined`, donc une clé **absente** est remplacée par la valeur
locale, et un `null` explicite est **conservé**. Les deux attentes sont retournées, et la
troisième assertion — `XCTAssertNotEqual(typed, Reconcile.defaultDocument())` — était déjà
vraie.

#### Les nombres

Banc : `_banc/verifier-reconcile.mjs` — **158 vérifications**, 0 échec, les **treize** bancs
antérieurs rejoués. Falsificateur : `_banc/falsifier-reconcile.mjs` — **32 mutations**,
toutes tuées, arbre rendu intact, l'arbre vérifié par `git status --porcelain` avant et
après chaque mutation. Tests : **543 → 585**, dont **42** pour `Tests/ReconcileTests.swift`.

Le compte **global** a changé de banc à cette occasion — il n'appartient qu'au plus récent,
sinon deux bancs l'affirmeraient et divergeraient au bloc suivant. `_banc/verifier-tajweed
.mjs` est donc passé de **142** à **141** vérifications : le contrôle qui **nommait** le
total appartient désormais au nouveau banc, et l'ancien affirme son **absence**.

### 9.33 La navigation du `coranTest` : une justification fausse, une pagination partagée, et la pastille qui lisait la mauvaise édition

Le fichier `Core/QuranSourceNavigation.swift` justifiait l'omission de la branche `coranTest`
par « **607 polices `.woff2`** ». Ce nombre est vrai — et il ne dit rien de ce fichier.

**Ce que la branche de navigation lit vraiment.** `src/coranTest/data/verse-index.json` fait
**380 782 octets** et ne contient que des **nombres** : `{"surah:ayah": {id, pages, lines}}`
pour **6 236 versets** — aucune police, aucune vue. Les 607 `.woff2` appartiennent à la chaîne
de **rendu** (`src/coranTest/html.ts`, un `WKWebView`), qui n'a pas été portée et qui reste le
seul report assumé. La raison écrite était donc **fausse pour ce qu'elle justifiait**.

**Une mesure, deux branches repliées.** `coran_1441-bounds.json` et `verse-index.json`
rendent la même page pour les **6 236 versets** — **0 divergence** ; `testPageRange` et
`zipPageRange` la même plage pour les **604 pages** — **0 divergence**. `VerseBounds.rows`
ne lit qu'une ressource du `Bundle`, pas `VerseBounds.Source` : l'index du 1441 **est**
l'index du `coranTest`. La branche est portée, rangée avec le Coran 1441, et **dormante** —
`displayed(stored:)` ne rend jamais `.coranTest` (`isAvailable == false` → repli `.medine`).

**Le défaut latent, lui, était vivant.** `AudioRepeatSettingsView` construisait sa pastille
« Toute la page » avec `Quran.pageRange(page)` — la pagination du **Coran de Médine** —, là où
l'original reçoit `pageRangeOverride={sourcePageRange}` (`App.tsx:437`, consommé en
`PassageAudioPlayer.tsx:36` sous `pageRangeOverride ?? pageRange(page)`). Mesure : les deux
paginations s'écartent sur **36 pages sur 604**, et **33** d'entre elles ont une **longueur**
différente (page 597 : `6 099…6 125` contre `6 093…6 118`, sept versets d'écart). La plage est
désormais portée par `QuranSourceNavigation.pageRange(_:page:)`, sa table **dérivée** de
l'index du 1441 — pour qu'elle ne puisse pas dévier de `versePage` —, et l'écran reçoit la
plage **au lieu** de la page.

**Deux pièges de banc, mesurés en réparant ce bloc.**

1. **Un contrôle qui nomme une règle doit lire la règle, pas une de ses copies.** La ligne
   `case .coran1441, .coranTest:` apparaît **deux fois** dans le fichier — `versePage` et la
   nouvelle `pageRange`. Le contrôle de `verifier-marques-pages.mjs` cherchait la chaîne
   **n'importe où** : la mutation qui retirait `coranTest` du premier groupe laissait le
   second satisfaire le contrôle, et le banc restait **vert** (M07 survivante). De même, le
   contrôle « le fichier dit POURQUOI » était satisfait par la copie de `displayed(stored:)`
   que porte le commentaire de la branche de Tajwid, 200 lignes plus bas (M08 survivante).
   Les deux contrôles épingle désormais les **textes exacts** — le groupe **suivi de la ligne
   qui le distingue**.
2. **Une mutation voyage avec son contrôle.** Le contrôle « l'écran lit le libellé de
   l'objectif » a quitté `verifier-reglages.mjs` pour `verifier-cartes-profil.mjs` quand la
   carte a rejoint la page Profil (§9.24). La mutation, elle, était restée sur
   `Features/Settings/SettingsView.swift`, où la chaîne n'existe plus : le harnais a **refusé**
   de la jouer — « la chaîne à muter est ABSENTE — la mutation ne prouve rien ». Le contrôle
   déplacé se retrouvait donc **sans falsificateur**. Déplacer un contrôle sans déplacer sa
   mutation ouvre un trou silencieux : la mutation a suivi, dans
   `falsifier-cartes-profil.mjs` (**M22**), où elle meurt.

**Un témoin de compte qui comptait à moitié.** `verifier-marques-pages.mjs` comptait les
`verdict` du haut du fichier, pas les **dix** contrôles « le banc précédent passe encore »
émis par une boucle. Pire, si l'un de ces dix bancs meurt avant sa dernière ligne,
`execFileSync` lève et le module s'arrête **là** : le témoin n'est jamais écrit. La boucle se
compte maintenant elle-même, et sa ligne de synthèse est écrite avant tout arrêt possible.

#### Les nombres

Banc : `_banc/verifier-source-navigation.mjs` — **43 vérifications**, 0 échec, plus
`_banc/oracle-source-navigation.mjs` (**18 vérifications**) qui **exécute** l'original
compilé par `esbuild` au lieu de le translittérer. Falsificateur :
`_banc/falsifier-source-navigation.mjs` — **19 mutations**, toutes tuées, arbre rendu intact.
Tests : **585 → 594**, dont **10 → 19** pour `Tests/QuranSourceNavigationTests.swift`.

Le compte **global** a encore changé de banc : il vit maintenant dans
`verifier-source-navigation.mjs` (43 vérifications). `verifier-reconcile.mjs` est passé de
**158** à **157** — le contrôle qui nommait le total a déménagé, et l'ancien dit qu'il l'a
perdu. `verifier-tajweed.mjs` (**141**) et `verifier-marques-pages.mjs` (**106**) reposent
tous deux ce fait.

#### La limite connue, et pourquoi elle n'est pas un défaut

`SurahListOptions.pageSpan` construit « Pages X – Y » avec `studyPage(id, **edition**)`, là où
`MainScreens.tsx` emploie `state.reader?.mushaf ?? 'coranTest'` — la préférence **stockée**,
sans passer par `displayed()`. Inobservable aujourd'hui (`.coranTest` n'est jamais affiché, et
`SurahListView` passe bien `model.edition`), mais le jour où la chaîne `.woff2` arrive, le
portage divergerait de l'original. **Divergence délibérée, consignée** — pas un oubli.


### 9.34 La porte d'accueil : un dossier vide qui ne l'était pas, et deux surfaces d'authentification qui se ressemblent

`Features/Auth/` était **vide**, et ce vide ne voulait pas dire « fonctionnalité
manquante » : l'écran de connexion vivait **à la racine de l'application**
(`App/ContentView.swift`, `private struct SignInView`). C'est le premier défaut —
un dossier qui a l'air d'attendre du code alors que le code est ailleurs, au
mauvais endroit pour qui le cherche.

Le second est plus grave, parce qu'il ne se voit pas : `SignInView` employait
`ProfileOptions.canSignIn`, c'est-à-dire la règle de la **carte du profil**, tout
en se présentant comme la **porte** de l'application. La référence porte bel et
bien **deux surfaces d'authentification avec des règles différentes** :

| Surface | Fichier | Règle |
| --- | --- | --- |
| La **porte** | `src/App.tsx:285` | `busy \|\| !email.includes('@') \|\| (mode==='signup' ? password.length<6 : !password)` |
| La **carte du profil** | `src/App.tsx:322` | `busy \|\| !email \|\| !password` |

La porte exige donc l'**arobase même pour se connecter**, et fait dépendre la
longueur du mot de passe du **mode** : six caractères pour créer un compte, la
seule non-vacuité pour se connecter. La carte, elle, se contente de la
non-vacuité des deux champs. Le portage mélangeait les deux.

Trois autres faits, tous mesurés :

- **La porte s'ouvre sur un CHOIX.** `mode` est initialisé à `null`
  (`App.tsx:260`), et **trois** boutons se rendent tant qu'il l'est : « Se
  connecter », « Créer mon compte », et « Réessayer la restauration de ma
  session ». Ce troisième est ce qu'un portage « propre » perd — il ne
  correspond à aucun écran, seulement à une reprise.
- **Les boutons secondaires sont conditionnels.** « Mot de passe oublié »
  n'existe qu'en connexion ; « Renvoyer la confirmation » n'existe qu'en
  inscription **et seulement après qu'un message a été écrit**. Les confondre
  ferait apparaître deux actions impossibles.
- **Le mot de passe se compte en unités UTF-16.** `password.length` en
  JavaScript compte les unités, pas les graphèmes : **trois emoji valent six
  unités**, et arment l'inscription. Le test le dit par la mesure —
  `troisEmoji.count == 3` **et** `passwordLength(troisEmoji) == 6`.

#### L'oracle, et quatre contrôles qui ne mordaient pas

`_banc/oracle-auth-gate.mjs` **extrait** les deux expressions `disabled={…}` du
texte de `App.tsx` et les **évalue** — il ne recopie pas la règle. Sur 100
décisions, le portage et l'original s'accordent ; ils divergent sur **14** cas,
qui sont exactement la frontière entre les deux surfaces.

Le banc a d'abord laissé **six mutations survivantes**, chacune révélant un
contrôle qui ne mordait pas :

1. une borne `[\s\S]{0,600}` après `func canSubmit` **débordait sur la
   fonction suivante**, qui portait le même test — lire le **corps**, borné ;
2. la divergence avec `ProfileOptions.canSignIn` n'était affirmée par **aucun**
   contrôle — en ajouter un qui lise le corps de `canSignIn` ;
3. un contrôle relisait le **type** `Mode?` au lieu de la **déclaration** : une
   valeur initiale `.login` le laissait vert ;
4. un **compte** ne voit ni un renommage ni une assertion changée — épingler le
   **nom** du test et la **ligne** d'assertion ;
5. la garde d'unicité de l'oracle ne se déclenche jamais sur `App.tsx` : un
   contrôle du seul résultat ne peut pas voir qu'on l'a retirée — lire la
   **garde** dans le texte de l'oracle.

Et un cinquième défaut, dans l'outillage du banc lui-même : `codeSwift` ouvrait
un littéral de caractère sur **toute apostrophe droite**, alors que les fichiers
du portage sont pleins d'apostrophes **typographiques** (`’`). Une apostrophe
**non appariée** faisait glisser tout le fichier en « état chaîne », où les
commentaires n'étaient **plus** retirés — et un commentaire citant
`AuthGateOptions.canSubmit` suffisait alors à satisfaire un contrôle sur
l'appel. On sort désormais d'un littéral sur un **saut de ligne**, et un `’`
n'ouvre jamais rien.

#### Les nombres

- **17** tests ajoutés (`Tests/AuthGateTests.swift`), **594 → 611**.
- `_banc/verifier-porte-auth.mjs` : **42** vérifications.
- `_banc/falsifier-porte-auth.mjs` : **18** mutations, **0 survivante**.

### 9.35 Le sélecteur de sourate : `Number` n'est pas `parseInt`, et un oracle qui a menti

`src/SurahPicker.tsx` fait **18 lignes**, et ce n'est pas l'onglet Coran : c'est
une **feuille modale posée sur le lecteur** (`Modal presentationStyle="pageSheet"`),
ouverte depuis le panneau d'options de séance (`App.tsx:514`). Sa règle tient en
une ligne, `goPage` (`:11`) :

```js
const page = Number(pageText);
if (!Number.isInteger(page) || page < 1 || page > 604) { Alert.alert('Page invalide', …); return; }
```

**`Number` n'est pas `parseInt`, et le portage doit le savoir.** Relevé sur
dix-neuf saisies, mesuré et non supposé :

| Saisie | `Number(...)` | Décision |
| --- | --- | --- |
| `'  12  '` | 12 | accepté — les espaces extérieurs sont tolérés |
| `'0007'` | 7 | accepté |
| `'+5'` | 5 | accepté |
| `''` / `' '` | 0 | **refusé** — `0 < 1` |
| `'605'` | 605 | refusé |
| `'3.5'` | 3.5 | refusé — `Number.isInteger(3.5)` est faux |
| `'abc'`, `'nan'`, `'inf'` | `NaN` | refusé |
| `'1e2'` | 100 | **accepté** |
| `'0x10'` | 16 | **accepté** |

`Int("1e2")` et `Int("0x10")` rendent `nil` en Swift : **deux divergences
réelles**. Elles sont **nommées dans le portage** plutôt que tues, et elles sont
**hors d'atteinte** : le champ porte `keyboardType="number-pad"`, un pavé qui
n'offre que les dix chiffres — ni `e`, ni `x`, ni `.`, ni `,`, ni `+`, ni `-`.
Sur tout ce qui est atteignable, les deux décisions s'accordent.

Les deux autres règles sont plus discrètes :

- **`initialScrollIndex={Math.max(0, currentSurah-1)}`** (`:15`). Le `max` n'est
  pas décoratif : `currentSurah` peut valoir `0`, et l'indice vaudrait alors
  `-1` — que `FlatList` refuse.
- **`{onPage && …}`** : la ligne de saut n'existe que si l'appelant fournit
  `onPage`. C'est la propriété **optionnelle** du type de la référence, et elle
  décide d'une ligne entière de l'interface.

#### L'oracle a menti une fois, et c'est la mesure qui l'a dit

`_banc/oracle-surah-picker.mjs` **extrait** le prédicat du fichier et l'évalue.
La première version le cherchait par sa **forme lettrée** — `page > 604` — alors
que le fichier écrit `page>604`, **sans espaces**. `indexOf` a rendu `-1`, et
l'expression extraite est sortie **vide** : l'oracle lisait l'espacement
**attendu**, pas celui du fichier. Un banc qui aurait comparé des décisions
contre une expression vide aurait pu rester vert pour la pire des raisons.

L'ancrage est désormais par **structure** (`\s*`), le caractère d'ambiguïté est
refusé explicitement, et **les deux lectures des bornes doivent s'accorder** —
le prédicat en lit une, une fonction dédiée l'autre, et l'oracle **lève** si
elles diffèrent.

#### Le montage, et le geste qui compte

`onSelect` (`App.tsx:517`) fait **cinq** gestes ; le premier est le seul
audible : arrêter l'audio. Sans lui, le verset **précédent** continuerait de
jouer sur la nouvelle page. Les quatre autres oublient un état que le portage
n'a pas (file de commandes, verset sélectionné), ou ferment la feuille.

`onPage`, lui, **ferme la feuille PUIS navigue** — et l'ordre est observable :
rester ouvert sur une page qui a changé derrière serait déroutant.

Et une règle de fond : `surah.start` est un identifiant de **verset**, pas une
page. Le poser dans `page` montrerait la page 8 pour la sourate 2 — un défaut
silencieux, visible, et faux. On passe par `showPage`, qui résout dans
l'**édition affichée** (`QuranSourceNavigation.versePage`).

#### Les pièges de banc, mesurés ici

1. **Un contrôle qui cherche une chaîne n'importe où confond « la règle est là »
   et « la chaîne est là ».** `has(reader, 'model.audio.stop()')` restait vert
   après le retrait de l'appel — le nom survit ailleurs. Lire le **corps**.
2. **L'ancre du corps doit désigner la DÉCLARATION, pas une mention.**
   `corpsDe(reader, 'surahPicker', …)` prenait `showSurahPicker` dans les états
   et rendait un corps **vide** : trois mutations mouraient « à côté » sur un
   découpage faux.
3. **Comparer des positions se fait dans le CODE, pas dans le texte.** Un
   commentaire qui **cite** la ligne avant qu'elle n'existe faisait échouer
   l'ordre sur un fichier **juste**.
4. **Une ancre qui doit rester absente du fichier qui la cherche ne peut pas y
   être écrite telle quelle.** Le contrôle du compte citait sa propre ancre, et
   `codeJS` **garde les chaînes** : le banc se satisfaisait lui-même. L'ancre est
   écrite **en pièces concaténées**.
5. **Une mutation qui ne change rien n'accuse pas le banc.** M07 écrivait la
   borne dans un **commentaire**, que `codeSwift` retire : la mutation était
   invisible, et le survivant accusait le banc à tort. La mutation doit être du
   **code**.

#### Les nombres

- **26** tests ajoutés (`Tests/SurahPickerTests.swift`), **611 → 637**.
- `_banc/verifier-surah-picker.mjs` : **55** vérifications.
- `_banc/falsifier-surah-picker.mjs` : **23** mutations, **0 survivante**, **0 à
  côté**.
- `verifier-source-navigation.mjs` passe de **43** à **44** : son contrôle de
  passation citait un successeur **périmé deux fois** (`611`, puis `157`) ; il
  vérifie désormais la propriété durable — **un seul** banc calcule le total.

### 9.36 La messagerie : les règles d'un fil, et les primitives d'écriture qui manquaient

Le bloc précédent avait rendu l'onglet Amis **lisible** — la liste des relations,
les demandes reçues, le code d'invitation. Il ne montrait **rien** de ce que deux
amis se disent : `SocialService` portait dix-huit fonctions, aucune ne touchait
`friend_messages`. C'est ce trou que ce bloc ferme, en portant le cœur de
`src/services/social.ts:130-190`.

**Les règles vivent dans `Core/`.** `Core/MessagingOptions.swift` porte les
décisions, et rien d'autre : les bornes (`pageSize` **50**, `summaryLimit` **300**,
le partage tronqué à **2000**), les **quatre sortes** de message et le fait qu'une
seule — `recitation` — porte une pièce jointe, le masquage d'un message pour soi
seul, la marque de lecture, et le résumé d'une conversation. Aucune de ces
fonctions ne parle au réseau : elles se mesurent, et c'est tout.

**Le résumé d'une conversation est trois décisions dans un ordre précis.**
L'original écrit `result[row.link_id] ??= {...}` — donc le **premier** message
parcouru gagne, et comme la liste arrive du plus récent au plus ancien, c'est le
dernier message qui s'affiche. Un message supprimé remplace son **corps** par le
libellé, mais **garde sa date** : c'est la date d'envoi qui ordonne la liste, pas
celle du masquage. Et un décompte non nul **crée** le résumé s'il n'existait pas,
avec `new Date()` pour horodatage — un horodatage que rien ne peut mesurer hors
ligne, donc **injecté**. Une quatrième décision se cache sous la troisième :
`unread: 0` est posé par le parcours puis **écrasé** par le décompte, jamais
déduit du nombre de messages.

**Le comptage se fait en unités UTF-16, pas en graphèmes.** `slice(0, 2000)` de
JavaScript compte les unités ; `String.count` de Swift compte les graphèmes. Sur
1 001 familles emoji, les deux donnent des longueurs différentes. Le portage prend
donc `Array(description.utf16)` et reconstruit en `String(decoding:as:UTF16.self)`
— ce qui **tolère** une paire de substitution coupée par la borne, là où une
reconstruction naïve produirait un caractère invalide.

**Deux divergences sont nommées plutôt que tues.** La première : `trim` de
JavaScript retire `U+FEFF` (le BOM), `whitespacesAndNewlines` de Swift **non** —
mesuré, `U+FEFF` appartient à la catégorie `Cf` (format) et non `Zs` (séparateur
d'espace). La seconde : la formule du nombre de versets d'une récitation
(`end - start + 1`) n'a **pas** de garde dans l'original ; le portage la ramène à
zéro par `max(0, …)`. Aucune des deux n'est atteignable depuis l'interface, et
toutes deux sont écrites dans le fichier au lieu d'être découvertes plus tard.

#### Les primitives d'écriture qui manquaient

`SupabaseRESTClient` ne savait que **lire** (`select`) et appeler une fonction
(`rpc`). La messagerie écrit dans trois tables et compte des lignes. Quatre
primitives sont donc ajoutées, chacune avec la sémantique exacte de l'original :

- `insert` — `Prefer: return=minimal`, un `INSERT` pur, **jamais** un `upsert` ;
- `upsert` — `resolution=merge-duplicates` et `on_conflict` : la ligne est
  **fusionnée**, pas dupliquée. Sans elle, une conversation ne se marquerait lue
  qu'une fois ;
- `count` — un `HEAD` avec `count=exact`, le total lu dans `Content-Range`. Ce
  n'est pas un `select` détourné : `head:true` de l'original n'existe pas côté
  PostgREST, c'est la **méthode** qui change ;
- `maybeSingle` — l'objet unique. PostgREST n'a pas de `.maybeSingle()` : on
  demande `Accept: application/vnd.pgrst.object+json` et on borne à `limit=1`.
  Le cas « aucune ligne » rend **`nil`**, pas une erreur — PostgREST répond
  **406**, et lever là ferait échouer la lecture d'un profil d'ami qui n'a pas
  encore de ligne.

#### L'oracle, exécuté et non cité

`_banc/oracle-messaging.mjs` rejoue les expressions **réelles** de `social.ts` :
`body.trim()`, `slice(0,2000)`, la comparaison `created_at > last_read_at`, le
`??=` des résumés, `Math.floor` de la durée. Il vérifie d'abord que ses **onze
ancres** sont toujours dans l'original — une ancre périmée rendrait l'oracle
complaisant — puis rejoue **56 relevés**.

La leçon de ce bloc : le banc **exécute** l'oracle, il ne le cite pas. Une
première version se contentait d'un contrôle de texte (« le banc de tests nomme
l'oracle ») ; mesuré, une mutation de l'ORACLE **survivait** — le banc ne le
lançait jamais. L'oracle est donc devenu une **fonction exportée** `relever()`,
que le banc appelle et dont il lit le verrou ; lancé seul, il imprime et sort.

#### Quatre contrôles qui ne mordaient pas, et pourquoi

La première campagne a laissé **cinq survivantes**. Chacune a nommé un vrai trou :

1. **Un contrôle de sortie rejouée ne voit pas le fichier muté.** Neuf mutations
   portaient sur les *règles rejouées en JavaScript*, pas sur le Swift : monter
   la borne dans `MessagingOptions.swift` ne changeait rien à la fonction de
   rejeu. Une section entière lit désormais le **corps réel** de chaque fonction —
   découpé sur l'accolade **appariée**, commentaires retirés.
2. **Un nom préfixe en cachait un autre.** `func upsert` trouvait
   `upsertUserState`, une **autre** fonction : le corps rendu était le sien, et le
   contrôle `on_conflict` accusait une fonction qui le porte pourtant. L'ancre
   exige désormais que le nom **se termine** (`(?![A-Za-z0-9_])`).
3. **Une chaîne peut satisfaire pour un voisin.** `merge-duplicates` apparaît
   **deux fois** dans le client — aussi dans `upsertUserState`. Chercher la chaîne
   dans le fichier entier laissait l'une couvrir l'autre : le contrôle lit
   maintenant le **corps** de `upsert`.
4. **Une ancre écrite en clair se satisfait elle-même.** Le contrôle du compte
   cherchait `let compteTotal = 0`, chaîne qu'il écrivait lui-même — et `codeJS`
   **garde** les chaînes. L'ancre est composée en morceaux.

#### Deux contrôles de banc repris, parce qu'ils étaient périmés

Le contrôle de passation de `verifier-surah-picker` **citait son propre
successeur** — il nommait `verifier-messagerie.mjs`, un nom qui périme au bloc
suivant. Il vérifie désormais la propriété **durable** : ce banc-ci ne calcule
plus le compte, et le porteur actuel le fait.

Celui de `verifier-source-navigation` allait plus loin dans l'erreur : il
**nommait** `verifier-surah-picker.mjs` comme « le plus récent », ce qui se
périme exactement au bloc suivant. Il **compte** désormais combien de bancs
calculent le total — il en faut **un**, et peu importe lequel.

#### Un piège de fin de ligne, encore

Les deux bancs de ce bloc ont été écrits avec des fins de ligne **CRLF**. Une
ancre de mutation écrite avec `\n` ne correspondait donc **pas** au fichier :
« 0 occurrence de l'ancre », sur un texte qui paraissait identique. C'est la
deuxième fois que ce piège coûte un aller-retour — les fichiers Swift, eux,
étaient déjà en LF, et c'est ce qui compte pour l'intégration continue.

#### Les nombres

- **41** tests ajoutés (`Tests/MessagingTests.swift`), **637 → 678**.
- `_banc/oracle-messaging.mjs` : **56** relevés d'accord avec l'original.
- `_banc/verifier-messagerie.mjs` : **165** contrôles verts.
- `_banc/falsifier-messagerie.mjs` : **24** mutations, **0 survivante**, **0 à
  côté**.
- Le compte global des tests **change de porteur** : `verifier-surah-picker` le
  rend, `verifier-messagerie` le calcule, et `verifier-source-navigation` vérifie
  la propriété durable — **un seul** banc le calcule.

### 9.37 L'écran de la messagerie, et cinq survivantes qui ne lisaient pas le bon objet

Le §9.36 avait porté **le service** — les règles, les douze modèles, les quatre
primitives d'écriture — et l'avait prouvé. Il manquait **l'écran** : rien ne
l'affichait. C'était le trou réel, et c'est ce que `Features/Friends/MessagingView.swift`
comble (27053 octets).

#### Ce que la vue ne décide pas

L'original porte la liste d'amis et le fil **dans un seul composant**, pilotés
par un état `selected` — `null` veut dire « la liste ». Le portage les sépare en
deux vues, et le lien est un `navigationDestination(item:)` : SwiftUI empile et
désempile d'un geste, là où l'original traîne quarante lignes de `useEffect`.

La frontière est la même que partout ailleurs : **la vue ne décide de rien**.
Elle *appelle* `MessagingOptions.pageSize`, `.outgoing`, `.isRead`,
`.sessionCount`, `.appointmentISO` et `Kind.carriesRecitation`. C'est la
condition pour que l'écran ne puisse pas diverger sans qu'un test tombe — et le
banc le vérifie sur le **corps** de `send`, pas sur le nom de la règle.

#### Trois règles nées avec l'écran, et deux mesures qui ont surpris

**`Number(...)`, et non `Int(...)`.** La garde du nombre de séances est
`!Number.isInteger(Number(t)) || Number(t) < 1 || Number(t) > 14`
(`SocialScreens.tsx:177`). Mesuré : `Number("")` vaut **0** et `Int("")` rend
`nil` ; `Number("1e2")` vaut **100** et `Int("1e2")` rend `nil` ; `Number("0x10")`
vaut **16**. Les deux conversions **refusent** ces entrées, mais **pas par la
même branche** — et c'est ce qu'un test épingle par son nom. Le cas hexadécimal
est **déclaré inatteignable** : le champ porte `keyboardType(.numberPad)`.

**Le 31 février roule — et c'était déjà juste.** La garde du rendez-vous
reproduit le gabarit `^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})$`, puis
`new Date("…T…:00")`, puis refuse si la date est invalide **ou passée**. En
écrivant le portage, une sonde (`node -e`) a mesuré que `2026-02-31` rendait
`Invalid Date` — donc une garde d'aller-retour a été ajoutée. **La sonde était
cassée** : un `$` mangé par le shell faisait porter le test sur autre chose. La
mesure propre donne `2026-03-03T09:00:00.000Z` — **le 31 février roule au 3
mars**, en forme ISO comme en constructeur numérique, et l'original l'**accepte**.
La garde d'aller-retour, « propre » en apparence, aurait **divergé** : un écran
refusant une saisie que l'application React Native accepte. L'oracle le mesure
désormais dans les deux sens, et le cas de 2027 est celui qui le prouve — en
2026 la date roulée tombe dans le passé, et le refus vient alors de la **borne**,
pas du calendrier.

**`isRead` est `<=`, et non `<`.** Le miroir de `isUnread` (`>`) : un message
écrit à la milliseconde exacte de la marque de lecture est **lu**. L'accord entre
les deux prédicats est **mesuré** sur trois paires, jamais écrit — deux négations
qui se répondent sont exactement ce qu'une refonte casse en silence.

#### Un test qui n'avait jamais tourné

Le run n° **82** est tombé sur `testTheReadStampIsInWholeMilliseconds`, et il
avait **raison**. Le test construisait `Date(timeIntervalSince1970:
1_767_225_600.4567)` et attendait la chaîne `…00.456Z`. Or un `Double` ne
représente pas `.4567` exactement : la valeur la plus proche est **au-dessus**,
donc `.4567 × 1000 = 1767225600456.7002`, et l'arrondi donne **457**. Le run a
mesuré `…00.457Z`. La chaîne attendue n'était pas celle que l'entrée portait :
l'assertion comparait un arrondi à une valeur qui n'avait jamais existé.

Le test ne portait pas sur la bonne propriété. Ce qui compte n'est pas une
chaîne donnée — c'est que l'horodatage soit écrit **en millisecondes entières**,
comme `toISOString()`. Le test mesure désormais trois choses : une valeur
exactement représentable rend son horodatage exact, une seconde ronde rend
`.000Z`, et **toute** entrée rend une queue de **trois chiffres**. La dernière
tient même pour l'entrée qui avait fait échouer la première version.

#### Cinq survivantes, et une seule cause

La première campagne a laissé **cinq** mutations vivantes : M26 (`outgoing`),
M29 (le décimal), M30 (le 31 février), M31 (`<=`), M32 (les millisecondes). Une
seule cause : **le banc lisait le NOM des règles, jamais leur CORPS.** Casser
`return createdAt <= otherReadAt` en `<` ne changeait rien de ce que le banc
relisait — il cherchait l'appel, qui restait là.

Le remède est celui du §9.36 : lire la **fonction**, par `corpsDe`, qui sépare
sur l'accolade **appariée**. Six contrôles de plus lisent donc les corps réels de
`sessionCount`, `appointmentISO`, `isRead` et `number`, plus le formateur ISO de
`DateKeys`.

Deux pièges supplémentaires, mesurés :

- **`outgoing` apparaît deux fois** dans la vue — la garde du bouton et le corps
  envoyé. Muter la seule seconde ligne laissait la première satisfaire le
  contrôle. Le banc lit donc le **corps de `send`**.
- **La mutation M29 se satisfaisait elle-même** : elle écrivait
  `… == value || true`, et la chaîne cherchée `value.rounded() == value` restait
  **intacte** dans le texte muté. La mutation change désormais l'**opérateur**
  (`==` → `!=`), et un contrôle négatif exige qu'aucun `!=` n'apparaisse.

Et **M21** — la garde des ancres de l'oracle — survivait à un seuil « ≥ 50
relevés » : onze relevés noyés dans quatre-vingt-treize ne font pas tomber le
total sous le seuil. L'oracle **publie** désormais le nombre d'ancres qu'il a
réellement vérifiées (`ancresVerifiees`), compté **dans la boucle** — une boucle
vidée laisse `ancres.length` intact.

#### Les nombres

- **59** tests dans `Tests/MessagingTests.swift` (18 de plus), **637 → 696**.
- `_banc/oracle-messaging.mjs` : **93** relevés (37 de plus).
- `_banc/verifier-messagerie.mjs` : **199** contrôles verts (34 de plus).
- `_banc/falsifier-messagerie.mjs` : **33** mutations, **0 survivante**, **0 à
  côté** — contre 5 survivantes à la première campagne.
- Un contrôle **fragile** réparé chez un prédécesseur (`verifier-porte-auth`
  épinglait « 41 dans `Tests/MessagingTests.swift` », un chiffre qui a valu 41
  puis 59) : il éprouve maintenant que le porteur **dérive** la part.

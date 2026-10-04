# LOCAL_DATA_MIGRATION.md

## Ce que ce document établit

L'application React Native range une partie de ses données **uniquement sur
l'appareil** : AsyncStorage, trousseau (SecureStore), base SQLite locale, fichiers.
Ces données **ne sont pas dans Supabase**.

Ce document les recense, et dit pour chacune :

- ce qu'elle contient ;
- si elle existe aussi dans Supabase (donc si elle se retrouve toute seule) ;
- ce qui se passe si elle est perdue.

## Conclusion principale, à lire en premier

> **Aucune donnée locale de l'application React Native n'est récupérable par
> l'application Swift.**

Ce n'est pas un choix, c'est une contrainte du système : les deux applications ont
des identifiants de paquet différents (`fr.coranmemoire.app` et
`fr.swiftdeepseek.app`). iOS leur donne des **bacs à sable séparés**. La base
SQLite `coran-memoire.db`, le trousseau et les fichiers de l'une sont
**invisibles** pour l'autre, et le resteront.

Conséquence pratique : **la migration ne peut pas être automatique.** Elle doit
être soit supportée (l'application relit les données depuis Supabase), soit
acceptée comme une perte.

Bonne nouvelle : l'essentiel de ce qui compte — progression, séances, révisions,
consolidations, marque-pages, amis — vit dans Supabase. Ce qui reste local est
soit reconstructible, soit de confort.

**Le dépôt React Native n'a pas été modifié** pour faciliter cette migration, et
ne le sera pas sans autorisation explicite.

---

## 1. Ce qui est local et n'existe PAS dans Supabase

Ces éléments sont perdus au passage. Aucun n'est critique pour la progression,
mais deux méritent une décision (voir §4).

### 1.1 File d'attente hors ligne — **le seul point vraiment sensible**

| | |
|---|---|
| Où | SQLite `coran-memoire.db`, table `pending_sync` |
| Colonnes | `id`, `user_id`, `payload` (document JSON complet), `created_at`, `base` |
| Rôle | Les modifications faites hors ligne, en attente d'envoi. `base` conserve la dernière version synchronisée connue, pour la fusion à trois voies. |

**Ce qui se passe si elle n'est pas vidée :** ces modifications ne sont **pas**
dans Supabase. Si la personne ouvre l'application Swift avant que l'application
React Native ne se soit reconnectée, elle voit l'état du serveur — donc **sans**
ces modifications. Les changements ne sont pas détruits (ils restent sur
l'appareil, dans la base de l'application React Native), mais ils ne sont pas
visibles côté Swift.

**Marche à suivre, sans toucher au dépôt de référence :** demander à la personne
d'**ouvrir l'application React Native avec du réseau**, et de la laisser
synchroniser, **avant** d'installer et d'utiliser l'application Swift. C'est une
consigne d'usage, pas une modification de code.

### 1.2 Base SQLite locale

| Table | Contenu | Sort |
|---|---|---|
| `app_state` | La dernière version locale du document (une seule ligne, `id = 1`) | Reconstruite depuis Supabase à la première synchronisation. |
| `account_state` | Le document mis en cache, par `user_id` | Idem. |
| `pending_sync` | Voir §1.1 | Voir §1.1. |

### 1.3 Trousseau (SecureStore)

| Clé | Contenu | Sort |
|---|---|---|
| `sb-<référence-projet>-auth-token` | La session Supabase (jetons d'accès et de rafraîchissement), découpée en tranches de 1500 caractères | **Perdue.** La personne se reconnecte une fois dans l'application Swift, avec les mêmes identifiants, et retrouve le même compte. Sans conséquence. |

### 1.4 AsyncStorage — réglages d'appareil

| Clé | Contenu | Dans Supabase ? | Si perdue |
|---|---|---|---|
| `notifications-requested-on-device` | `'yes'` une fois la demande d'autorisation système affichée | Non, par choix | L'application Swift redemande l'autorisation une fois. Attendu. |
| `notification-installation-id` | Identifiant d'installation de l'appareil | `push_devices` (une ligne par appareil) | Un nouvel identifiant est créé. L'ancien appareil devient un jeton mort côté serveur ; l'application Swift enregistre le sien. |
| `audio-reciter-hafs:<userId\|guest>` | Récitateur choisi, par compte | **Partiellement** : aussi dans `user_state.audioPreferences.reciterId` | Rien : la valeur est déjà dans le document partagé. |
| `audio-reciter-hafs` | Ancienne clé, sans compte | Non (héritage) | Rien. Ancienne forme, migrée par l'application React Native elle-même. |
| `audio-reciter-legacy-owner` | Le compte qui a adopté la valeur héritée | Non | Rien. |
| `audio-repeat-preferences` | Réglages de répétition audio : `countChoice`, `customCount`, `repeatMode`, `gap`, `speed`, `autoStop` | **Non** | **Perdue.** Voir §4. |
| `recitation-info-<userId>` | `'yes'` une fois l'avertissement d'enregistrement vocal accepté | **Non** | L'application Swift réaffiche l'avertissement une fois. Attendu, et même souhaitable. |
| `guest-content-favorites` | Favoris de contenus pour un visiteur **sans compte** | `content_favorites` (comptes connectés uniquement) | Rien pour une personne connectée : ses favoris sont dans la table. |
| `daily-content:<AAAA-MM-JJ>` | Résultat mis en cache de `daily_content_for_date` | Oui, via la fonction RPC | Rien : le contenu est redemandé au serveur. |
| `pending-avatar:<courriel>` | Chemin local d'une photo de profil choisie mais **pas encore envoyée** | Non | **Perdue.** Voir §4. |

### 1.5 Fichiers

| Chemin | Contenu | Sort |
|---|---|---|
| `Documents/quran/coran_1441/` | Le Coran 1441 installé : 9 060 bandes de lignes (`001-01.png` … `604-15.png`), plus `ready-v1.json` (marqueur de fin). Pendant l'installation : `download.zip`, `download-complete.json`, `resume.bin` | **Non transférable, et sans perte.** L'application Swift réinstalle les mêmes images depuis la **même** archive (`https://files.quran.app/hafs/madani_1441/zips/images_1440.zip`), et sous les **mêmes** noms — `quranLineUri` de l'original et `Coran1441Install.fileName` produisent tous deux `%03d-%02d.png`. Un dossier déjà rempli par l'une des applications est donc reconnu par l'autre. Le seul écart de nom est `resume.bin` contre `resume.json` : le fichier de reprise est interne à une application et n'est jamais relu par l'autre. |
| `Cache/quran-verse-audio-v1/*.mp3` | Audio des versets mis en cache | Non transférable, et sans importance : c'est un cache. |
| Enregistrements de récitation (avant envoi) | Fichiers audio locaux | Ceux **déjà envoyés** sont dans le bucket `recitations` et dans la table `recitations` : ils restent accessibles. Ceux **jamais envoyés** sont perdus. |

---

## 2. Ce qui est local ET aussi dans Supabase

Ces données se retrouvent **toutes seules**, parce qu'elles vivent dans le
document partagé `user_state.data` ou dans une table partagée. C'est le cas de la
grande majorité :

`knowledge`, `goal`, `pace`, `learningDays`, `sessions`, `revisions`,
`memorizedAt`, `reviewSettings`, `reviewHistory`, `reviewCycle`,
`reviewConsolidations`, `reviewPriorityDue`, `difficultyMarkers`,
`difficultyHistory`, `studyProgress`, `bookmarks`, `readPages`, `lastRead`,
`theme`, `accent`, `uiFont`, `reader`, `notifications`, `profile`,
`audioPreferences.reciterId`, et tout le social (`friend_profiles`,
`friend_links`, `friend_messages`, …).

**C'est le point important :** la progression, les séances, les révisions, les
consolidations, les versets difficiles et les marque-pages sont **déjà**
synchronisés. L'application Swift les affiche dès la première connexion, sans
rien migrer.

---

## 3. Ce que l'application Swift fait déjà

- Elle **restaure la session depuis son propre trousseau** et ouvre l'application
  sans réseau (`AuthService.restore`).
- Elle tient **sa propre** file d'attente locale
  (`Storage/LocalStore.swift` : `enqueue`, `pendingOperations`, `acknowledge`) et
  la vide à la reconnexion, avec la même fusion à trois voies.
- Elle écrit son cache dans `Application Support`, **exclu des sauvegardes
  iCloud** (données reconstructibles : rien à sauvegarder).
- Elle conserve le **même `user_id`**, donc elle voit immédiatement les données
  déjà synchronisées.

---

## 4. Décisions à prendre (aucune n'est bloquante)

Deux éléments locaux ne sont **pas** dans Supabase et ne sont **pas**
reconstructibles. Il faut choisir :

**a) `audio-repeat-preferences`** — nombre de répétitions, mode (passage ou
verset par verset), silence entre les versets, vitesse, arrêt automatique.

- *Option 1 (recommandée)* : ne rien faire. Ces réglages sont propres à
  l'appareil et se re-règlent en quelques secondes. Les faire migrer
  supposerait d'ajouter une clé dans `user_state.data` — donc un changement dans
  l'interface partagée, à valider selon la procédure de
  `SUPABASE_COMPATIBILITY.md` §4.
- *Option 2* : ajouter une clé additive `audioRepeatPreferences` au document
  partagé. Rétrocompatible (l'application React Native l'ignorerait), mais cela
  demande une autorisation explicite.

**b) `pending-avatar:<courriel>`** — une photo choisie mais dont l'envoi n'a pas
abouti.

- *Option 1 (recommandée)* : ne rien faire. La personne la rechoisit.
- *Option 2* : prévenir l'utilisateur, dans le rapport, de vérifier sa photo de
  profil dans l'application React Native avant de changer d'application.

**c) La file `pending_sync`** — voir §1.1. La seule action utile est une consigne
d'usage : synchroniser l'application React Native avant la bascule.

---

## 5. Interdits

- Ne **pas** modifier le dépôt React Native pour faciliter la migration sans
  autorisation explicite.
- Ne **pas** chercher à lire les fichiers, la base SQLite ou le trousseau de
  l'application React Native : c'est impossible depuis un autre bac à sable, et
  toute tentative de contournement serait une atteinte à la vie privée de
  l'utilisateur.
- Ne **pas** copier de données d'appareil dans un dépôt Git.

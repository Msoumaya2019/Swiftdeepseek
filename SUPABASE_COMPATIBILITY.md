# SUPABASE_COMPATIBILITY.md

Ce document décrit le contrat entre les deux applications et la base Supabase
**existante**. Il dit ce qui est partagé, ce qui ne doit jamais changer, et
comment procéder quand un changement paraît nécessaire.

- Dépôt de référence (application React Native) : `Msoumaya2019/coran-memoire`
- Dépôt de cette application : `Msoumaya2019/Swiftdeepseek`
- Projet Supabase : **le même pour les deux**, aucune nouvelle instance

---

## 1. Ce qui rend les deux applications compatibles

### 1.1 L'authentification

Les deux applications parlent au **même point d'entrée GoTrue**
(`/auth/v1/token`) avec la même clé publiable. Conséquences directes :

- une personne qui a déjà un compte se connecte **avec les mêmes identifiants** ;
- elle obtient le **même `user_id`** (UUID), parce que c'est le même serveur qui
  le délivre ;
- `user_state.user_id` référence `auth.users(id)`, donc **le document de
  progression est le même** ;
- les tables sociales (`friend_links`, `friend_profiles`, …) la reconnaissent
  comme la même personne, avec **les mêmes amis**.

C'est la raison pour laquelle cette application **ne crée aucun utilisateur**.
`AuthService.signUp` existe, mais son usage prévu est limité aux personnes qui
n'ont réellement pas encore de compte : créer un second compte pour quelqu'un qui
en a déjà un produirait exactement le doublon d'utilisateurs à éviter.

### Les URL de redirection d'authentification — étape manuelle, PAS ENCORE FAITE

L'application native utilise un schéma d'URL qui lui est **propre** —
`swiftdeepseek://auth` (`Core/AppConfig.swift:71`) — et non celui de l'application
React Native, `coranmemoire://auth` (`src/services/sync.ts:13`). Le choix est
délibéré : deux applications distinctes ne doivent pas se disputer le même schéma
au niveau du système.

Ce schéma n'est employé que par deux gestes :

| Geste | Appel |
|---|---|
| Réinitialisation du mot de passe | `Services/AuthService.swift:108` |
| Renvoi de la confirmation d'inscription | `Services/AuthService.swift:112` |

**Le projet Supabase doit donc autoriser `swiftdeepseek://auth`.** Mesuré sur le
projet réel (`GET /auth/v1/settings`, HTTP 200) : `"mailer_autoconfirm": false`.
La confirmation par e-mail est **obligatoire** — une inscription ne produit aucune
session tant que le lien n'a pas été suivi.

Comportement documenté par Supabase, et **non mesuré ici** : une adresse de retour
absente de la liste autorisée n'est pas refusée, elle est **remplacée** par le
*Site URL* du projet. La personne est bien confirmée, mais atterrit sur une page
web au lieu de revenir dans l'application. C'est un défaut silencieux : aucune
erreur n'est levée côté client.

**Où le faire** : tableau de bord Supabase → *Authentication* → *URL
Configuration* → *Redirect URLs* → ajouter `swiftdeepseek://auth`. **Conserver**
`coranmemoire://auth`, dont l'application React Native a besoin.

Cette étape vit dans la configuration du projet Supabase, pas dans le code : elle
ne peut pas être posée par le dépôt, et **elle n'a pas encore été faite**.

### 1.2 Le document d'état : `public.user_state`

C'est **le** point de compatibilité. Le schéma est volontairement minimal
(`supabase/schema.sql` du dépôt de référence) :

```sql
create table if not exists public.user_state (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz
);
```

`data` est **un seul document JSONB opaque** : toute la progression de la
personne y est rangée. Le schéma relationnel n'a jamais à connaître sa structure.

Quatre politiques RLS, et elles seules décident de l'accès :

| Opération | Politique |
|---|---|
| `select` | `(select auth.uid()) = user_id` |
| `insert` | `with check ((select auth.uid()) = user_id)` |
| `update` | `using (... = user_id) with check (... = user_id)` |
| `delete` | `using (... = user_id)` |

**Aucune clé privilégiée n'est nécessaire pour que cela fonctionne.** La clé
publiable suffit, parce que c'est le jeton de la personne connectée qui porte
l'identité.

### 1.3 Les clés du document

Elles sont le contrat. Les deux applications doivent écrire exactement les mêmes
noms. Les voici, telles qu'elles existent déjà dans les documents des
utilisateurs actuels :

`schema`, `onboardingDone`, `onboardingStep`, `updatedAt`, `userId`,
`knowledge`, `goal`, `pace`, `learningDays`, `sessions`, `revisions`, `profile`,
`theme`, `uiFont`, `accent`, `notifications`, `reader`, `bookmarks`,
`readPages`, `lastRead`, `memorizedAt`, `reviewSettings`, `reviewHistory`,
`reviewDue`, `difficultyMarkers`, `difficultyHistory`, `reviewModelStartedAt`,
`reviewCycle`, `reviewConsolidations`, `reviewPriorityDue`,
`reviewCycleHistory`, `consolidationHistory`, `studyProgress`,
`audioPreferences`

Trois d'entre elles sont particulièrement fragiles et sont donc documentées
séparément :

| Clé | Pourquoi c'est fragile |
|---|---|
| `studyProgress` | indexée par `"<mode>:<id>"`, soit `learning:<sessionId>` ou `revision:<taskId>`. Une clé mal construite rend un suivi **invisible** pour l'autre application. Dans ce dépôt, elle passe par `Program.studyKey(_:_:)` — jamais par une chaîne écrite à la main. |
| `reviewSettings.cycleDays` | 7, 14, 21 ou 30. Une valeur hors de cet ensemble fausserait les deux clients. |
| `reviewSettings.dailyQuantity` | `nisf`, `hizb`, `juz` ou `juz2`. Mêmes libellés que l'affichage. |

### 1.4 Les autres tables (partagées, pas encore toutes exploitées)

L'application React Native utilise 24 tables et 36 fonctions RPC. Cette
application n'en utilise pour l'instant qu'une petite partie (voir
`SWIFT_MIGRATION.md`). **Toutes sont partagées** : aucune n'a été créée ni
modifiée par ce dépôt.

Tables : `admin_notifications`, `app_admins`, `app_problem_reports`,
`content_categories`, `content_favorites`, `daily_content_schedule`,
`daily_contents`, `friend_group_members`, `friend_groups`, `friend_links`,
`friend_message_hidden`, `friend_message_reads`, `friend_message_reports`,
`friend_messages`, `friend_profiles`, `friend_review_appointments`,
`friend_shared_goals`, `notification_preferences`, `push_devices`,
`recitation_corrections`, `recitation_feedback`, `recitations`,
`social_suspensions`, `user_state`.

Bucket de stockage : `recitations`.

Fonctions RPC : `accept_friend`, `accept_group_invite`,
`accept_review_appointment`, `accept_shared_goal`, `admin_learning_accounts`,
`admin_notification_recipients`, `block_friend`, `cancel_review_appointment`,
`create_friend_group`, `daily_content_for_date`, `decline_friend`,
`decline_group_invite`, `delete_friend_group`, `delete_friend_message`,
`ensure_social_profile`, `finalize_recitation_correction`, `friend_inbox`,
`friend_overview`, `invite_group_member`, `my_push_delivery_status`,
`my_unread_messages`, `open_admin_contact`, `publish_social_progress`,
`register_push_device`, `remove_friend`, `remove_group_member`,
`report_friend_message`, `request_friend`, `resolve_friend_report`,
`save_daily_content`, `send_admin_notification`, `set_group_moderator`,
`set_social_online`, `suspend_social_member`, `unblock_friend`,
`unsuspend_social_member`.

---

### 1.5 Ce qui a été MESURÉ sur le projet réel

Ces quatre appels ont été passés sur le projet `npbwnvrqmajwqtnncuyv` avec la clé
publiable, le 4 octobre 2026. Ils ne modifient rien : ce sont des lectures. Ils
remplacent une supposition (« la clé doit être bonne ») par une mesure.

| Appel | Code | Ce que ça prouve |
|---|---|---|
| `GET /auth/v1/health` | 200 | Le projet existe et GoTrue répond. |
| `GET /auth/v1/settings` | 200 | **La clé est acceptée.** Une clé refusée donnerait 401. Le fournisseur `email` est actif, l'inscription est ouverte, la confirmation d'adresse est **exigée** (`mailer_autoconfirm: false`). |
| `POST /auth/v1/token?grant_type=password` (identifiants volontairement faux) | 400 `invalid_credentials` | **La clé n'est pas en cause** : c'est le couple adresse/mot de passe qui est refusé. Une clé invalide donnerait `invalid_api_key`. |
| `GET /rest/v1/user_state?select=user_id` | 401 `42501` | Le rôle `anon` n'a **aucun privilège** sur `user_state`. |

### Le point important : `anon` n'a pas le droit de lire `user_state`

La réponse exacte est :

    {"code":"42501","message":"permission denied for table user_state",
     "hint":"Grant the required privileges to the current role with:
             GRANT SELECT ON public.user_state TO anon;"}

C'est une information utile pour ce client, et elle est **rassurante** :

- RLS ne s'applique qu'aux rôles qui ont déjà le privilège sur la table. Ici,
  l'accès est refusé **avant** RLS, au niveau du privilège : un visiteur non
  connecté ne peut donc pas même atteindre les politiques.
- Conséquence pour l'application Swift : **elle doit être authentifiée avant de
  lire quoi que ce soit**, exactement comme l'application React Native. Il n'y a
  pas de « mode invité » à prévoir — et il ne faut pas en ajouter un.
- Le rôle `authenticated`, lui, doit avoir le privilège (l'application React
  Native fonctionne). **Non vérifié ici** : le confirmer demande un compte réel,
  ce que fait l'étape 10 de la première mission (« tester avec un compte
  existant »). C'est le seul point de ce document qui reste à mesurer.

### Ce que la racine PostgREST renvoie, et pourquoi ce n'est pas une erreur

`GET /rest/v1/` répond **401** avec :

    {"message":"Secret API key required",
     "hint":"Only secret API keys can be used for this endpoint."}

Ce n'est **pas** un signe que la clé est mauvaise : Supabase réserve désormais la
racine PostgREST (la description OpenAPI) aux clés secrètes. La clé publiable y
est refusée par conception. Tester la validité d'une clé publiable sur cette
adresse mène donc à une conclusion fausse — c'est un piège à connaître, et
`/auth/v1/settings` est le bon point de contrôle.

---

## 2. Ce qui est INTERDIT

Ces opérations casseraient l'application React Native en production, pour des
utilisateurs réels dont la progression est dans ce document.

| Interdit | Pourquoi |
|---|---|
| `drop table` / `drop column` | L'application React Native lit et écrit ces objets. La faire échouer n'est pas un risque théorique : c'est une perte de données pour des personnes réelles. |
| `rename` une table ou une colonne | Même raison : le nom est écrit en dur dans le code React Native. |
| Changer un type brutalement (`jsonb` → autre, `text` → `uuid`) | Les valeurs existantes ne se convertiraient pas, ou se convertiraient mal. |
| Supprimer ou affaiblir une politique RLS | Ce serait ouvrir les données d'autrui. RLS **est** le modèle de sécurité : sans elle, la clé publiable, qui est publique par nature, donnerait accès à tout. |
| `truncate` | Perte de données immédiate. |
| Écrire dans `user_state.data` une structure qui **remplace** au lieu de **fusionner** | L'autre application perdrait les clés qu'elle connaît. Voir §3. |
| Mettre la clé `service_role` dans un client | Elle contourne RLS. Elle ne doit jamais quitter le serveur. |
| Créer un second projet Supabase, une seconde authentification, dupliquer les comptes | C'est précisément ce que la demande interdit : mêmes comptes, mêmes UUID, mêmes données. |

---

## 3. Ce qui est AUTORISÉ sans risque

Un changement **purement additif** et **rétrocompatible** ne casse rien, parce que
l'application React Native l'ignorera :

- une **nouvelle table** (elle ne la lira pas) ;
- une **nouvelle colonne nullable** avec valeur par défaut (`null` ou `default`) ;
- une **nouvelle vue** ;
- une **nouvelle fonction** RPC (aucun nom existant n'est modifié) ;
- une **nouvelle politique RLS permissive** sur une table existante, à condition
  qu'elle n'élargisse l'accès qu'à ce qui appartient déjà à la personne ;
- l'ajout d'une **nouvelle clé** dans `user_state.data` — c'est même le
  mécanisme prévu pour faire évoluer le document.

Dans ces cas, cette application peut les utiliser **sans rien demander**,
puisque l'application React Native continue de fonctionner à l'identique.

---

## 4. Procédure d'arrêt et de demande

Toute opération qui **n'entre pas** dans la liste du §3 est un changement
d'interface partagée. La règle est de **s'arrêter et demander**, jamais
d'improviser.

La marche à suivre :

1. **Ne rien exécuter.** Aucune migration, aucun `alter`, aucun `update` de
   masse.
2. **Écrire ce qui est envisagé**, dans ce document, sous forme de proposition :
   - l'objet concerné (table, colonne, politique, fonction) ;
   - le changement exact (SQL si possible) ;
   - **ce que l'application React Native en verrait** : lit-elle cette colonne ?
     s'attend-elle à une valeur non nulle ? un `null` la ferait-elle échouer ?
   - le plan de retour arrière ;
   - si l'opération est réversible sans perte.
3. **Demander l'autorisation** avant toute exécution, en présentant cette
   analyse.
4. N'exécuter qu'après accord explicite, et **vérifier ensuite** qu'un document
   `user_state` réel se relit sans perte.

### Pourquoi cette procédure est aussi stricte

Le mode d'échec est silencieux. Une colonne renommée ne produit pas d'erreur au
déploiement : elle produit une application qui ne synchronise plus, chez des
personnes qui ne comprendront pas pourquoi. Comme les deux clients partagent le
même document, une erreur côté Swift devient une perte côté React Native.

---

## 5. Comment cette application écrit dans `user_state`

Trois protections, dans `Core/OfflineMerge.swift` et
`Repositories/AppStateRepository.swift` :

1. **`JSONValue`** (`Core/JSONValue.swift`) est la représentation de référence.
   Le document n'est jamais réduit à une liste de champs connus : une clé
   inconnue traverse la lecture et l'écriture **intacte**. C'est ce qui permet à
   cette application de ne pas détruire une clé qu'une version plus récente de
   l'application React Native aurait ajoutée.

2. **`AppStateRepository.patch(raw:with:)`** ne remplace que les clés que cette
   application connaît, et laisse les autres telles quelles.

3. **`OfflineMerge`** est un port fidèle de `src/core/offlineMerge.ts` : fusion à
   trois voies (`base` / `local` / `remote`), fusion des tableaux par `id`,
   pierres tombales pour les suppressions, `through` au maximum, `status: done`
   prioritaire, union pour `validations` / `History` / `readPages` / `completed`.
   `Tests/OfflineMergeTests.swift` couvre chaque règle.

Le point d'entrée d'écriture est un `upsert` complet
(`Prefer: resolution=merge-duplicates`), exactement comme `pushState()` côté
React Native (`src/services/sync.ts`).

---

## 6. Ce qui n'est PAS fait et ne le sera pas sans accord

- Aucune migration n'a été appliquée.
- Aucune table, colonne, politique RLS ou fonction n'a été créée ni modifiée.
- Aucune donnée n'a été écrite dans le projet Supabase.
- Le dépôt `Msoumaya2019/coran-memoire` n'a reçu **aucun commit, aucune branche,
  aucune poussée, aucune modification de fichier**.

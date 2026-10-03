# Models/

Ce dossier est **réservé** et volontairement vide pour l'instant.

Les modèles de données partagés avec l'application React Native ne sont pas
rangés ici, mais dans `Core/` :

| Ce que l'on cherche | Où c'est |
|---|---|
| Le document complet `user_state.data` | `Core/AppState.swift` |
| Une valeur JSON arbitraire (clé inconnue préservée) | `Core/JSONValue.swift` |
| Les fonctions RPC (JSON brut) | `Core/Review.swift`, `Core/Program.swift` |
| Le Coran (sourates, juz’, hizb, pages, versets) | `Core/Quran.swift` |
| Les modèles du social (amis, relations) | `Services/SocialService.swift` |

**Pourquoi ne pas les avoir déplacés ici ?** `AppState` n'est pas un modèle
isolé : c'est le contrat de compatibilité avec l'application React Native, et
`Core/OfflineMerge.swift` opère dessus. Le garder à côté de la fusion à trois
voies et de `JSONValue` évite de disperser ce qui doit rester lu ensemble.

Ce dossier servira si des modèles propres à l'interface (non partagés)
apparaissent — un modèle de présentation pour une liste, par exemple. Tant
qu'aucun n'existe, mieux vaut un dossier vide qu'un dossier fourre-tout.

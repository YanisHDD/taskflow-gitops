# taskflow-gitops — Dépôt GitOps du cours CI/CD M2

Ce dépôt décrit l'état voulu de l'application TaskFlow dans Kubernetes.  
Argo CD surveille la branche \main\ et aligne le cluster dessus : pour modifier la production, on ne tape aucune commande à la main, on passe uniquement par une Pull Request relue et validée.

---

## Équipe

- **Yanis Haddad** ([@YanisHDD](https://github.com/YanisHDD))
- **Moustapha** ([@hping404](https://github.com/hping404))
- **Sofiane** ([@Soso9240](https://github.com/Soso9240))

---

## Structure du Dépôt

| Chemin | Rôle |
| --- | --- |
| \pps/taskflow/\ | Les manifests Kubernetes déclaratifs surveillés par Argo CD |
| \rgocd/application.yaml\ | Déclare l'application dans Argo CD (auto-sync, prune, selfHeal) |
| \docs/screenshots/\ | Preuves de déploiement et captures d'écran |
| \exemples/bluegreen/\ | Manifests pour le déploiement Blue-Green (Argo Rollouts) |
| \exemples/canary/\ | Manifests pour le déploiement Canary (Argo Rollouts) |
| \scripts/install.sh\ | Installation du cluster \kind\ et des outils |
| \scripts/argocd-ui.sh\ | Port-forward pour ouvrir l'interface Web Argo CD |
| \scripts/observe.sh\ | Vérifie quelle version répond et avec quel code HTTP |

---

## Livrable J2 — Journal des Déploiements (MSPR 4.1)

### 1. Journal des Déploiements

| ID | Date & Heure | Version | Action Git | Binôme / Validateur | Statut Argo CD | Délai | Résultat observe.sh |
|---|---|---|---|---|---|---|---|
| **#1** | 07/10/2026 11:34 | \1.0.0\ | \e100da\ (PR #1) | Mouss / Yanis | **Synced** & **Healthy** | Instantané | \40 version=1.0.0 http=200\ |
| **#2** | 07/10/2026 11:41 | \2.0.0\ | \5d4515\ (PR #2) | Yanis / Mouss | **OutOfSync** ➔ **Synced** | < 5s (via Refresh UI) | \40 version=2.0.0 http=200\ |
| **#3** | 07/10/2026 11:48 | \2.0.0\ (drift) | Commande manuelle \scale --replicas=1\ | Test local | **OutOfSync** ➔ **Synced** via \selfHeal\ | < 3s | 4 pods rétablis (1 ancien, 3 recréés) |
| **#4** | 07/10/2026 11:51 | \1.0.0\ (rollback) | \295c4ea\ (PR #3 Revert) | Yanis / Mouss | **OutOfSync** ➔ **Synced** | < 5s (via Refresh UI) | \40 version=1.0.0 http=200\ |

---

### 2. Analyse Technique & Délais

- **Délai de déploiement (PR 2.0.0) :**
  Normalement, Argo CD vérifie les changements sur Git toutes les 3 minutes. Pour aller plus vite et ne pas attendre la minute de polling, j'ai appuyé sur le bouton **Refresh** dans l'UI d'Argo CD. L'application est passée immédiatement en **OutOfSync**, puis s'est resynchronisée en moins de 5 secondes. Il a supprimé les anciens pods pour créer les nouveaux en \ev:2\, et on voit bien le message du commit ainsi que son hash affichés sur l'interface.
- **Comportement face à la dérive (Ligne 5 du Lab) :**
  Quand j'ai fait la commande \kubectl -n taskflow scale deployment taskflow --replicas=1\, l'application est passée en **OutOfSync**. La correction automatique (\selfHeal\) a été tellement rapide que je n'ai même pas eu le temps de capturer l'écran rouge tellement ça va vite. Mais sur la capture des pods, on voit bien la preuve : il y a 1 pod à 7 minutes (celui qui est resté quand j'ai forcé à 1) et les 3 autres ont été recréés direct (1 minute) dès qu'Argo CD a détecté la dérive pour remettre les 4 replicas.

---

### 3. Réponses aux 3 Questions

#### 1. Push ou Pull ?
- **Push (CI/CD classique) :** C'est le pipeline CI (ex: GitHub Actions) qui a les clés admin du cluster et qui fait \kubectl apply\. Le problème, c'est que si le pipeline a une faille, tout le cluster est accessible. En plus, si quelqu'un va modifier un pod à la main sur le cluster, le pipeline ne le verra jamais.
- **Pull (GitOps avec Argo CD) :** C'est l'agent Argo CD installé directement dans le cluster qui va lire Git et appliquer les différences. Aucun accès n'est ouvert depuis l'extérieur vers le cluster, et il surveille l'état réel en continu pour corriger les écarts.

#### 2. Qui a corrigé quoi ?
C'est le contrôleur **Argo CD**.  
Dès qu'on a fait le \scale --replicas=1\ à la main, l'application est passée en **OutOfSync**. Comme on a activé \selfHeal: true\ dans \rgocd/application.yaml\, Argo CD a vu que le cluster n'avait plus les 4 pods prévus sur Git, donc il a écrasé direct notre modif manuelle et recréé immédiatement les 3 pods manquants sans qu'on touche à rien.

#### 3. Pourquoi git revert ?
1. Si on essaie de corriger directement sur le cluster avec \kubectl\, Argo CD va annuler notre commande direct à cause du \selfHeal\.
2. En faisant un **git revert** depuis la PR sur GitHub, on crée un vrai commit de retour en arrière. Il est relu et validé par le binôme, tout reste propre et tracé dans l'historique Git, et Argo CD redéploie automatiquement la version stable.

---

## Preuves Visuelles (Screenshots)

### 1. Déploiement initial (1.0.0)
- **Argo CD Synced & Healthy :**  
  ![Argo CD 1.0.0](docs/screenshots/01-argocd-taskflow-1.0.0-synced.png)
- **Détail du Pod en 1.0.0 :**  
  ![Pod 1.0.0](docs/screenshots/01-pod-taskflow-1.0.0-healthy.png)
- **Test avec observe.sh (1.0.0) :**  
  ![Observe 1.0.0](docs/screenshots/02-observe-1.0.0.png)

### 2. Montée de version en 2.0.0 par PR
- **PR #2 validée et mergée :**  
  ![PR 2.0.0](docs/screenshots/03-pr-2.0.0-merged.png)
- **Argo CD avec les 4 pods en 2.0.0 (rev:2) :**  
  ![Argo CD 2.0.0](docs/screenshots/05-argocd-taskflow-2.0.0-synced.png)
- **Détail du Pod en 2.0.0 :**  
  ![Pod 2.0.0](docs/screenshots/06-pod-taskflow-2.0.0-healthy.png)
- **Test avec observe.sh basculé en 2.0.0 :**  
  ![Observe 2.0.0](docs/screenshots/04-observe-2.0.0.png)

### 3. Test de dérive et Self-Heal
- **Commande kubectl scale à 1 replica :**  
  ![Drift scale](docs/screenshots/07-drift-kubectl-scale.png)
- **Preuve du Self-Heal (1 pod à 7 min, 3 pods recréés à 1 min) :**  
  ![Drift selfHeal](docs/screenshots/08-drift-argocd-selfheal-pods.png)

### 4. Rollback par git revert
- **Création du Revert sur GitHub :**  
  ![Revert Create](docs/screenshots/09-revert-pr-create.png)
- **PR #3 de Revert validée et mergée :**  
  ![Revert Merged](docs/screenshots/10-revert-pr-merged.png)
- **Argo CD de retour en 1.0.0 (rev:3) :**  
  ![Argo CD 1.0.0 retour](docs/screenshots/11-revert-argocd-synced-1.0.0.png)
- **Détail du Pod réaligné en 1.0.0 :**  
  ![Pod 1.0.0 retour](docs/screenshots/12-revert-pod-1.0.0-healthy.png)

---

## Lab de l'Après-Midi — Stratégies Blue-Green et Canary

### 1. Stratégie Blue-Green (1.0.0 ➔ 1.1.0)

#### Journal des Déploiements Blue-Green

| ID | Date & Heure | Version | Action Git | Validateur | Statut Argo CD / Rollout | Résultat observe.sh |
|---|---|---|---|---|---|---|
| **#5** | 07/10/2026 14:25 | `1.0.0` (Blue-Green) | `6a24403` (PR #4) | Mouss / Yanis | **Synced** & **Healthy** (Rollout rev:1) | `40 version=1.0.0 http=200` |
| **#6** | 07/10/2026 14:35 | `1.1.0` (Preview) | `b3de244` (PR #5) | Mouss / Yanis | **Suspended** (Pause voulue, 8 pods au total) | Prod : `1.0.0` / Preview : `1.1.0` |
| **#7** | 07/10/2026 14:36 | `1.1.0` (Prod) | Commande `kubectl argo rollouts promote` | Manuel | **Healthy** (rev:2 actif, rev:1 coupé après 30s) | `40 version=1.1.0 http=200` |

#### Comment ça s'est passé :
On a remplacé notre `deployment.yaml` par le `rollout.yaml` de Blue-Green, avec deux services : `taskflow` pour la prod et `taskflow-preview` pour tester la nouvelle version. On a mis `autoPromotionEnabled: false` pour pas que ça bascule tout seul.

Quand on a mergé la PR pour passer en 1.1.0, Argo CD a déployé la nouvelle version mais s'est mis en pause (**Suspended**). C'est normal :
- On a eu **8 pods qui tournent en même temps** (4 anciens en 1.0.0 et 4 nouveaux en 1.1.0).
- Quand on a lancé `./scripts/observe.sh taskflow`, la prod répondait toujours à 100% en 1.0.0.
- Et avec `./scripts/observe.sh taskflow-preview`, on a pu tester la 1.1.0 tranquillement sans impacter les utilisateurs.

Une fois qu'on a vu que la preview marchait nickel, j'ai tapé :
```bash
kubectl argo rollouts promote taskflow -n taskflow
```
La prod a basculé d'un coup sur la 1.1.0 (`40 version=1.1.0 http=200`). Les anciens pods en 1.0.0 sont restés en vie pendant 30 secondes au cas où on voulait revenir en arrière, puis se sont coupés tout seuls.

#### Preuves Visuelles Blue-Green :
- **Mise en place du Rollout Blue-Green :**  
  ![Blue-Green setup](docs/screenshots/13-bluegreen-setup-synced.png)
- **PR #4 validée et mergée :**  
  ![PR Blue-Green setup](docs/screenshots/14-bluegreen-pr-setup-merged.png)
- **Preview active (8 pods et statut Suspended) :**  
  ![Blue-Green preview 8 pods](docs/screenshots/15-bluegreen-preview-8-pods-suspended.png)
- **Test observe.sh (prod en 1.0.0 vs preview en 1.1.0) :**  
  ![Blue-Green observe prod vs preview](docs/screenshots/16-bluegreen-observe-prod-vs-preview.png)
- **Promotion vers la prod :**  
  ![Blue-Green promote success](docs/screenshots/17-bluegreen-promote-success.png)
- **Cluster après les 30s (les anciens pods sont coupés) :**  
  ![Blue-Green healthy](docs/screenshots/18-bluegreen-after-promote-healthy.png)

---

### 2. Stratégie Canary (1.1.0 ➔ 2.0.0 ➔ 2.1.0 buggée)

#### Journal des Déploiements Canary

| ID | Date & Heure | Version | Action Git | Validateur | Statut Argo CD / Rollout | Résultat observe.sh |
|---|---|---|---|---|---|---|
| **#8** | 07/10/2026 15:03 | `1.1.0` (Canary Setup) | `7e4983f` (PR #8) | Mouss / Yanis | **Synced** & **Healthy** (Rollout Canary rev:2) | `40 version=1.1.0 http=200` |
| **#9** | 07/10/2026 15:09 | `2.0.0` (Canary 25%) | `9d3312e` (PR #9) | Mouss / Yanis | **Suspended** / **Paused** (1 pod canary, 3 pods stables) | Split de trafic (ex: 31 en 1.1.0 / 9 en 2.0.0) |
| **#10** | 07/10/2026 15:15 | `2.0.0` (Promotion 100%) | Commande `kubectl argo rollouts promote` | Manuel | **Healthy** (4 pods passés en 2.0.0 rev:3) | `40 version=2.0.0 http=200` |
| **#11** | 07/10/2026 15:44 | `2.1.0` (Crash test) | `18c96db` (PR #10) | Mouss / Yanis | **Suspended** (Palier 25% actif) | `28 v2.0.0` / `8 v2.1.0` / `4 erreurs 500` ! |
| **#12** | 07/10/2026 15:52 | `2.0.0` (Abort d'urgence) | Commande `kubectl argo rollouts abort` | Manuel (coupure d'urgence) | **Degraded** (Canary coupé, retour 100% stable) | `40 version=2.0.0 http=200` (sauvetage réussi) |

#### Comment ça s'est passé :
On a remplacé notre stratégie par Canary dans `rollout.yaml` et supprimé le service preview qui ne sert plus ici.
1. **Le palier à 25% (version 2.0.0) :**
   Quand on a déployé la 2.0.0, le Rollout s'est mis en pause automatique à 25%. Avec le `--watch`, on voyait bien 1 pod en version Canary (2.0.0) et 3 pods en version Stable (1.1.0).
   En lançant `observe.sh`, on a eu plusieurs répartitions : d'abord 26 / 14, puis 31 / 9. Comme le disait le prof : *« Sans ingress ni service mesh, la part de trafic suit la proportion de pods : 4 réplicas → 25% = 1 pod sur 4. Un pourcentage précis demande un traffic router »*. C'est du round-robin K8s standard, et le 31 en 1.1.0 contre 9 en 2.0.0 colle quasiment pile aux 75% / 25% théoriques !
2. **La montée vers 100% :**
   J'ai lancé la promotion avec `kubectl argo rollouts promote taskflow -n taskflow`. La bascule vers 100% n'est pas instantanée : elle a pris environ 1 minute / 1 minute 30 parce que le manifest contient des pauses automatiques (pause de 60s au palier 50%, pause de 30s au palier 75%). La preuve se voit direct sur l'âge échelonné de nos 4 pods sur la capture : 6m21s, 114s, 53s et 22s !
3. **Le crash test (version 2.1.0) et l'abort d'urgence :**
   En déployant la version 2.1.0, le piège s'est déclenché au premier palier de 25% : alors que le pod était affiché tout vert (`Healthy`) par les probes Kubernetes, `observe.sh` a fait remonter direct des erreurs utilisateurs : **`4 version=aucune http=500`** !
   Pour éviter d'impacter plus de monde, j'ai tout de suite tapé :
   ```bash
   kubectl argo rollouts abort taskflow -n taskflow
   ```
   L'effet a été immédiat : le pod 2.1.0 a été coupé (`ScaledDown`), et 100% des requêtes sont revenues instantanément sur la version stable 2.0.0 (`40 version=2.0.0 http=200`).
   Dans Argo CD, le Rollout passe alors en statut **Degraded** (avec l'événement explicite : `RolloutAborted: Rollout aborted update to revision 4`).

---

### 3. Réponses aux Questions d'Analyse (Livrable Après-Midi)

#### A. « Blue-Green ou Canary pour TaskFlow ? » (Risque vs Coût)
- **Niveau coût / ressources :**  
  - Le **Blue-Green** est plus cher : il double temporairement les ressources (2× pods en simultané, soit 8 pods au lieu de 4). Sur un gros cluster avec beaucoup de CPU/RAM, ça coûte le double en infrastructure pendant les bascules.
  - Le **Canary** est beaucoup plus économe : il n'ajoute que les pods nécessaires par palier (1 pod en plus à 25%), donc il consomme à peine 1.25× les ressources.
- **Niveau risque :**  
  - Le **Blue-Green** protège 100% des utilisateurs avant la bascule grâce au service preview (`taskflow-preview`), mais la bascule est binaire (tout ou rien) : si un bug passe à travers les tests de preview, 100% des utilisateurs se le prennent d'un coup.
  - Le **Canary** expose une petite part d'utilisateurs réels au bug (ici 25% ont vu les erreurs 500 sur la 2.1.0), mais il permet de limiter la casse et de couper en urgence (`abort`) avant que 100% des clients ne soient touchés.
- **Verdict pour TaskFlow :**  
  Pour TaskFlow, **Canary** est le choix le plus pertinent car l'application est légère et le Canary permet de valider le comportement avec du vrai trafic par petits paliers sans doubler la facture d'hébergement. Si le métier refuse catégoriquement qu'un seul utilisateur voie une erreur, on privilégiera Blue-Green.

#### B. « Pendant un canary, vous faites un abort. Que montrent le Rollout, Argo CD et Git, et que faut-il faire ensuite ? »
- **Ce que montre le Rollout :** Il affiche le statut **`Degraded`**. Il a mis la révision Canary à l'écart (`ScaledDown`) et a réactivé 100% du trafic sur l'ancienne révision stable (4 pods en 2.0.0).
- **Ce que montre Argo CD :** L'application et le Rollout passent en statut **`Degraded`** (cœur brisé). Dans l'onglet Events du Rollout, on voit bien l'événement : `RolloutAborted: Rollout aborted update to revision 4`.
- **Ce que montre Git :** Sur Git, la branche `main` contient toujours le commit qui demande de déployer l'image buggée `2.1.0` ! Le cluster et Git sont donc désynchronisés.
- **Ce qu'il faut faire ensuite :** Il faut impérativement faire un **`git revert`** (ou une Pull Request de rollback) sur Git pour remettre l'image `2.0.0` sur `main`. Dès que Git aura à nouveau la version 2.0.0, Argo CD va se resynchroniser, le Rollout sortira de l'état avorté et redeviendra **100% `Healthy`** (cœur vert). C'est la règle d'or du GitOps : Git doit toujours être corrigé pour refléter l'état voulu.

---

### Preuves Visuelles Canary :
- **PR #8 de mise en place Canary :**  
  ![Canary setup PR](docs/screenshots/19-canary-setup-pr-merged.png)
- **Rollout Canary initial (rev:2 actif) :**  
  ![Canary setup synced](docs/screenshots/20-canary-setup-synced.png)
- **Tableau de bord --watch au palier 25% (1 pod canary, 3 stable) :**  
  ![Canary watch 25](docs/screenshots/21-canary-25-watch.png)
- **Trafic partagé à 25% (26 en v1.1.0 / 14 en v2.0.0) :**  
  ![Canary observe split](docs/screenshots/22-canary-25-observe-split.png)
- **Argo CD suspended pendant le palier :**  
  ![Canary tree suspended](docs/screenshots/23-canary-tree-suspended.png)
- **Tests répétés sur observe.sh (31 en v1.1.0 / 9 en v2.0.0) :**  
  ![Canary multiple observe](docs/screenshots/24-canary-multiple-observe-split.png)
- **Déploiement 100% réussi avec pods échelonnés :**  
  ![Canary 100 percent healthy](docs/screenshots/25-canary-100-percent-healthy.png)
- **PR #10 de l'image 2.1.0 mergée :**  
  ![Canary 2.1.0 PR](docs/screenshots/26-canary-2.1.0-pr-merged.png)
- **Argo CD suspended en 2.1.0 :**  
  ![Canary 2.1.0 suspended](docs/screenshots/27-canary-2.1.0-argocd-suspended.png)
- **Pod 2.1.0 trompeur affiché Healthy par K8s :**  
  ![Canary 2.1.0 pod healthy](docs/screenshots/28-canary-2.1.0-pod-healthy.png)
- **Détection des erreurs HTTP 500 sur observe.sh :**  
  ![Canary HTTP 500](docs/screenshots/29-canary-2.1.0-http500-errors.png)
- **Abort d'urgence et retour instantané à 100% en 2.0.0 :**  
  ![Canary abort and recovery](docs/screenshots/30-canary-abort-and-recovery.png)
- **Rollout en statut Degraded après l'abort :**  
  ![Canary rollout degraded](docs/screenshots/31-canary-rollout-degraded-status.png)
- **Événement RolloutAborted et statut Degraded dans Argo CD :**  
  ![Argo CD Degraded Event](docs/screenshots/32-argocd-rollout-aborted-event-degraded.png)

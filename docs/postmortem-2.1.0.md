# Postmortem — Incident de Déploiement Canary v2.1.0

> Sans reproche : on cherche ce qui a permis l'erreur, pas qui l'a faite.

| Champ | Valeur |
| --- | --- |
| Date et heure | 08/10/2026 à 11:30 (11:30:24 – 11:31:28 heure locale) |
| Version en cause | `ghcr.io/9m7fjfpv9k-cyber/taskflow:2.1.0` |
| PR à l'origine | PR #14 (`feat: passage a l image 2.1.0 et ajout preuve A.4`) |
| Durée d'exposition | **0 seconde pour les utilisateurs finaux** (seul le trafic de test k6 a touché le pod canary) |
| Part du trafic touché | **0 % du trafic utilisateur réel** (100 % des requêtes de prod protégées sur la v2.0.0) |
| Détecté par | **Test de charge automatique k6** (`AnalysisRun` / métrique `test-de-charge-k6`) |
| Résolu par | **Abort automatique immédiat par le contrôleur Argo Rollouts**, puis `git revert` (PR #15) |

---

## Chronologie des Événements

| Heure locale | Événement | Détail technique |
| --- | --- | --- |
| **11:30:09** | Merge de la PR #14 | La branche `main` passe sur l'image `taskflow:2.1.0`. |
| **11:30:22** | Détection Argo CD | Synchronisation automatique vers la révision 6 du Rollout. |
| **11:30:24** | Démarrage du Canary (25 %) | Création du pod `taskflow-df976ccb5-x6qnt`. Argo Rollouts bascule le sélecteur du service `taskflow-canary` vers ce pod. |
| **11:30:24** | Déclenchement de l'`AnalysisRun` | Lancement du Job K8s `02d0294e-...test-de-charge-k6.1` basé sur le template `robustesse-k6`. |
| **11:30:25** | Exécution du test de charge k6 | 5 utilisateurs virtuels bombardent `http://taskflow-canary/tasks` pendant 60 secondes. |
| **11:31:22** | Franchissement des seuils k6 | k6 détecte **29.44 % d'erreurs HTTP 500** et une latence $p(95) = 315.74\text{ ms}$. k6 quitte avec une erreur de seuil (`thresholds crossed`). |
| **11:31:28** | Échec de l'AnalysisRun | Le Job Kubernetes passe en statut `Failed`. L'AnalysisRun est marqué `Failed`. |
| **11:31:28** | **Abort automatique (`RolloutAborted`)** | Le contrôleur Argo Rollouts avorte le déploiement : <br>1. Événement `RolloutAborted` émis.<br>2. Bascule immédiate du service canary (`SwitchService`) vers la révision 5 stable.<br>3. Destruction du pod 2.1.0 défaillant (`ScaledDown`).<br>4. Remise à l'échelle de la révision 5 (2.0.0) à 4 pods complets avec création du pod de secours `taskflow-c6cf57bd6-zbbsg` horodaté à 11:31:28. |
| **12:07:53** | Rollback GitOps (`git revert`) | Approbation et merge de la PR #15 (`Revert PR #14`). Git repasse en 2.0.0, Argo CD resynchronise et le Rollout redevient **`Healthy`**. |
| **12:26:04** | Livraison du correctif v2.2.0 | Merge de la PR #16 : l'AnalysisRun k6 valide 100 % de succès (code 200), promotion automatique progressive (50 %, 75 %) jusqu'à 100 % `Healthy`. |

---

## Composant défaillant et cause racine

### 1. Quel composant a échoué ?
Le composant défaillant est l'application **TaskFlow en version 2.1.0** sur la route métier `GET /tasks`.

**Preuve n°1 — Résumé k6 dans les logs du Job d'analyse :**
```text
  █ THRESHOLDS 
    ✗ 'p(95)<250' p(95)=315.74ms
    ✗ 'rate<0.02' rate=29.44%

  █ TOTAL RESULTS 
    checks_total.......: 591
    checks_succeeded...: 70.55% 417 out of 591
    checks_failed......: 29.44% 174 out of 591
    ✗ statut 200 (70% de succès / 30% d'erreurs 500)
```

**Preuve n°2 — Événements Kubernetes officiels enregistrés lors de l'incident :**
```text
2m28s   Warning   MetricFailed        analysisrun/taskflow-df976ccb5-6-1   Metric 'test-de-charge-k6' Completed. Result: Failed
2m28s   Warning   AnalysisRunFailed   analysisrun/taskflow-df976ccb5-6-1   Analysis Completed. Result: Failed
2m28s   Warning   RolloutAborted      rollout/taskflow                     Rollout aborted update to revision 6: Step-based analysis phase error/failed
2m28s   Normal    SwitchService       rollout/taskflow                     Switched selector for service 'taskflow-canary' from 'df976ccb5' to 'c6cf57bd6'
2m28s   Normal    ScalingReplicaSet   rollout/taskflow                     Scaled down ReplicaSet taskflow-df976ccb5 (revision 6) from 1 to 0
```

### 2. Pourquoi les probes Kubernetes ne l'ont-elles pas vu ?
Les sondes Kubernetes configurées dans le pod (`readinessProbe` et `livenessProbe`) interrogeaient uniquement le point de contrôle technique basique :
```yaml
httpGet:
  path: /health
  port: http
```
L'endpoint `/health` renvoyait `200 OK` car le serveur HTTP et le processus étaient en ligne. Les probes Kubernetes ont donc considéré le pod comme parfaitement sain (`Running 1/1`). Cependant, la logique métier sur `/tasks` plantait avec des erreurs 500 intermittentes. C'est l'illustration parfaite de l'insuffisance d'une simple probe de santé face à des bugs applicatifs réels.

### 3. Cause racine :
Une anomalie logicielle introduite dans la version 2.1.0 provoquait l'échec d'environ 30 % des requêtes métier réelles, non détectée par la probe basique `/health`, mais interceptée de façon déterminante par le test de charge k6 orchestré par l'AnalysisRun.

---

## Ce qui a bien fonctionné

1. **La porte de qualité automatique :** Aucun humain n'a eu besoin d'observer les dashboards ou de taper une commande d'urgence. Le pipeline a pris la décision seul en moins de 60 secondes.
2. **L'isolation étanche grâce au service canary :** En isolant la nouvelle version sur `taskflow-canary` et en dirigeant les utilisateurs uniquement sur `taskflow`, **0 % des clients réels n'ont été exposés aux erreurs 500**.
3. **Le repli instantané (Self-Recovery) :** En moins d'une seconde après l'échec de la métrique, Argo Rollouts a coupé le pod v2.1.0 et rétabli l'intégralité du trafic sur la version saine 2.0.0.
4. **La traçabilité médico-légale :** La conservation du Job en statut `Failed` dans Argo CD a permis de collecter toutes les métriques sans perte d'information.

---

## Actions correctives

| Action | Responsable | Échéance | Statut |
| --- | --- | --- | --- |
| Déploiement de la version corrective `2.2.0` | Yanis / Moustapha | Immédiat | **Fait (v2.2.0 à 100% Healthy)** |
| Remplacement de la révision avortée par un `git revert` officiel (PR #15) | Yanis | Immédiat | **Fait (PR #15 mergée)** |
| Enrichir les tests CI en amont (J1) pour vérifier l'endpoint `/tasks` avant build | Équipe DevOps | Fin de sprint | Planifié |
| Documenter l'incident et archiver les preuves dans le dossier MSPR | Yanis / Moustapha | J3 Matin | **Fait (`postmortem-2.1.0.md` & `README.md`)** |

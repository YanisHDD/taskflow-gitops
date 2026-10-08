# Mini-PSSI TaskFlow traduite en règles automatiques (Rego, lu par conftest).
# Lancer en local :  conftest test apps/ --policy policies/
package main

import rego.v1

charges_de_travail := {"Deployment", "Rollout", "StatefulSet", "DaemonSet"}

registre_autorise := "ghcr.io/9m7fjfpv9k-cyber/"

# Tous les conteneurs des objets qui font tourner des pods.
conteneurs contains c if {
	charges_de_travail[input.kind]
	some c in input.spec.template.spec.containers
}

# PSSI-R1 : tag explicite, jamais latest.
deny contains msg if {
	some c in conteneurs
	not contains(c.image, ":")
	msg := sprintf("PSSI-R1 : l'image du conteneur '%s' n'a pas de tag explicite (%s)", [c.name, c.image])
}

deny contains msg if {
	some c in conteneurs
	endswith(c.image, ":latest")
	msg := sprintf("PSSI-R1 : le conteneur '%s' utilise le tag latest (%s)", [c.name, c.image])
}

# PSSI-R2 : registre autorisé uniquement.
deny contains msg if {
	some c in conteneurs
	not startswith(c.image, registre_autorise)
	msg := sprintf("PSSI-R2 : l'image du conteneur '%s' ne vient pas du registre autorisé (%s)", [c.name, c.image])
}

# PSSI-R3 : À VOUS. Chaque conteneur doit avoir resources.limits.memory.
# Indice : sur le modèle des règles ci-dessus, utilisez « not c.resources.limits.memory ».

# PSSI-R4 : À VOUS. Le pod doit déclarer spec.template.spec.securityContext.runAsNonRoot: true.
# Indice : écrivez une règle « pod_non_root if { ... } » puis « not pod_non_root » dans un deny.

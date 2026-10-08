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

# PSSI-R3 : chaque conteneur doit avoir resources.limits.memory.
deny contains msg if {
	some c in conteneurs
	not c.resources.limits.memory
	msg := sprintf("PSSI-R3 : le conteneur '%s' n'a pas de limite de mémoire (resources.limits.memory)", [c.name])
}

# PSSI-R4 : le pod doit déclarer spec.template.spec.securityContext.runAsNonRoot: true.
pod_non_root if {
	charges_de_travail[input.kind]
	input.spec.template.spec.securityContext.runAsNonRoot == true
}

deny contains msg if {
	charges_de_travail[input.kind]
	not pod_non_root
	msg := sprintf("PSSI-R4 : la charge '%s' (%s) doit déclarer spec.template.spec.securityContext.runAsNonRoot: true", [input.metadata.name, input.kind])
}

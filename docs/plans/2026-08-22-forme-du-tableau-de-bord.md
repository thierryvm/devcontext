# Forme du tableau de bord (2.0) — dossier de décision

> **Statut : TRANCHÉ le 22 août 2026, portée comprise. Rien n'est encore
> implémenté.**
> La décision est en §0 ; les sections qui suivent sont l'analyse qui y a mené,
> conservée telle quelle. Une décision sans son raisonnement se rediscute à la
> première objection.

---

## 0. La décision — 22 août 2026

### Ce que Thierry a répondu

1. *« l'interface tout le monde doit pouvoir l'utiliser »*
2. *« oui pour la partie barre de système »*
3. *« probablement oui »* — d'autres l'utiliseront

Ces trois réponses désignent Tauri. **Elles ont été challengées à sa demande, et
le challenge a tenu sur trois points.**

### Ce que le challenge a trouvé

**La barre de système contredisait le produit.** Une icône de zone de
notification est globale à la machine et permanente : elle répond à *qui suis-je
en ce moment*. Or la thèse entière est **le dossier décide, jamais la session**.
Il n'existe pas de contexte courant au niveau machine. Une icône affichant
« Perso » réinstallerait dans l'interface le modèle mental que l'outil existe
pour détruire, et serait fausse dès qu'une seconde fenêtre est ouverte sur un
dossier client. Même raisonnement que le rejet du terminal embarqué.

**« Tout le monde » est bloqué par le module, pas par la coquille.** Mesuré le
même jour : 36 accès au registre, 81 points d'entrée `.cmd`, des raccourcis
`.lnk`, 30 chemins d'environnement Windows — contre **six** garde-fous de
plateforme en tout. Une fenêtre Tauri sur macOS surplomberait un module qui ne
peut pas y tourner.

**Un binaire dégrade une propriété de sécurité déjà acquise.** Le module se lit :
n'importe qui peut vérifier ce que fait l'outil qui tient ses identifiants avant
de l'exécuter. Compilé, « lis le source » devient « fais confiance à la
signature ». Pour un gestionnaire d'identités, c'est un recul.

**Et l'audience mesurée ne justifie pas encore le coût.** 17 versions,
72 téléchargements, 3 à 6 par version. `1.3.0` (dernière version pendant une
heure) et `1.9.5` (dernière depuis trois jours) en ont exactement cinq chacune.
**Aucun décalage vers la dernière version** : c'est la signature du miroir
automatique, pas d'un usage humain.

### La décision : deux produits, pas un

Les trois réponses tiennent toutes dès qu'on cesse de les faire porter par un
seul objet.

| | **Le tableau de bord (2.0)** | **Le veilleur (2.1)** |
| --- | --- | --- |
| Répond à | *ce qui est vrai de ce dossier* | *quelque chose ne va pas sur cette machine* |
| Ouvert | à la demande | jamais — il est là |
| Portée | le dossier | la machine |
| Forme | **dans le module** — rapport généré d'abord | **barre de système**, binaire séparé |
| Installation | `Install-Module DevContext`, rien de plus | téléchargement optionnel, Windows d'abord |
| Peut afficher le contexte « actif » | oui — celui du dossier ouvert | **non, jamais** |

Le veilleur donne la barre de système demandée, mais pour la seule chose qui
soit honnêtement globale : **la casse**, pas l'identité. Un jeton qui expire, un
raccourci cassé, un compte étranger dans une config globale. Et personne n'a
besoin de télécharger quoi que ce soit pour avoir le tableau de bord.

### La portée : Windows — tranché le 22 août 2026

*« On va faire pour Windows pour le moment, si j'ai un Mac plus tard, on
adaptera. »*

C'est le bon arbitrage, et pas seulement le pragmatique. La mesure du même jour
disait que **la portée est limitée par le port, pas par l'interface** : 36 accès
registre, 81 `.cmd`, 30 chemins Windows, contre six garde-fous de plateforme.
Choisir une coquille multi-plateforme n'aurait donc acheté **aucune portée
supplémentaire** — seulement une fenêtre qui s'ouvre sur un module incapable de
tourner là où elle s'ouvre.

Conséquences, dans l'ordre :

- **Le prochain chantier est l'interface**, pas le port.
- Le veilleur (2.1) n'aura **qu'une plateforme à signer**.
- Le port reste une **décision** — il se rouvre le jour où il existe une machine
  pour le vérifier, ce que la section *Deferred* du ROADMAP posait déjà comme
  condition. Il ne se rouvre pas par accident, parce qu'une interface l'aurait
  traîné derrière elle.

---

## 1. Ce qui est déjà tranché — non rediscuté ici

`ROADMAP.md` §2.0 pose cinq contraintes. Elles sont acquises.

| Contrainte | Ce qu'elle interdit |
| --- | --- |
| La CLI reste la source de vérité | Toute logique dans l'UI. Deux implémentations dérivent, et celle qu'on croit est celle qu'on a ouverte. |
| Il exécute des commandes, jamais un shell | Un terminal intégré. Console de commandes : montre, copie, exécute — commandes du module uniquement, jamais du texte libre. |
| Il reste local | Compte, cloud, télémétrie. |
| Chaque état vide nomme la commande suivante | Un tableau vide rendu sans rien dire. |
| Une section documentation, dont les notes personnelles | Un guide personnel versionné dans le dépôt public. |

---

## 2. Ce qui a été mesuré le 22 août 2026

| Fait | Mesure |
| --- | --- |
| Coutures de lecture annoncées « en place » | **2 sur 5 ne sortent pas du module** : `Get-CtxRaccourciChecks`, `Get-CtxMcpFacts` |
| Sortie lisible par un programme | **`-Json` sur `ctx doctor` seul.** Les autres lectures rendent des objets PowerShell |
| Poids des fichiers suivis | ~1 320 Ko |
| Ce document dans le paquet publié | **Non** — `docs/plans/` est exclu par `Build-Package.ps1` |

La deuxième ligne est celle qui départage. **Un tableau de bord hébergé PAR
PowerShell appelle les fonctions en mémoire et n'a besoin d'aucun `-Json`. Tout
ce qui n'est pas PowerShell doit lancer `pwsh` et lire sa sortie standard, donc
exiger `-Json` partout — et un module publié doit tenir chaque nom exporté
indéfiniment.**

---

## 3. Les options

### A — Interface web locale servie par PowerShell (`ctx dashboard`)

Un serveur HTTP sur la boucle locale, une page servie au navigateur par défaut.

- **Dette d'API** : les 2 exports manquants. Aucun `-Json`.
- **Distribution** : dans le module, quelques dizaines de Ko d'actifs statiques.
- **Outillage** : aucun. `System.Net.HttpListener` est dans .NET, et un préfixe
  `localhost` ne demande pas de réservation d'URL en administrateur.
- **Ce qu'elle rend possible** : tout, y compris le second clic qui exécute.
- **Ce qu'elle coûte** : *une socket en écoute dans l'outil qui porte les
  identifiants.* Voir §4.

### B — Tauri

Une fenêtre native, un pont IPC, du Rust qui lance `pwsh`.

- **Dette d'API** : les 2 exports **et** `-Json` sur chaque lecture, pour
  toujours.
- **Distribution** : un binaire signé **par plateforme**, hors PSGallery. Le
  module est Windows aujourd'hui ; l'argument du ROADMAP contre le port
  (« un port que personne ne peut vérifier n'est pas une fonctionnalité, c'est
  une promesse ») s'applique mot pour mot à un binaire.
- **Outillage** : une chaîne Rust en CI, et la règle du ROADMAP — *un port sans
  matrice est un port qui marche sur la machine qui l'a écrit*.
- **Ce qu'elle rend possible** : la barre système, une vraie fenêtre, pas de
  socket.
- **Ce qu'elle coûte** : le pont IPC devient la frontière à défendre, et le
  ROADMAP nomme déjà le risque : *le jour où un nom de dépôt, une branche ou un
  libellé de projet lu depuis une API peut atteindre cette entrée, il y a
  injection de commande dans l'outil qui tient les clés.*

### C — Rapport HTML statique (`ctx dashboard -Html`) — hors ROADMAP

PowerShell écrit un fichier HTML autonome et l'ouvre. Pas de serveur.

- **Dette d'API** : **aucune.** Tout se passe en mémoire, dans le module.
- **Distribution** : dans le module. Rien à compiler, rien à signer.
- **Outillage** : aucun.
- **Ce qu'elle rend possible** : tous les écrans de **lecture** — contextes,
  comptes, éditeurs, raccourcis, projets Supabase, serveurs MCP, jetons qui
  approchent de l'expiration — et la moitié « montre / copie » de la console.
- **Ce qu'elle coûte** : pas de second clic, pas de rafraîchissement. Et un
  fichier sur disque qui contient la **topologie des comptes** : c'est un
  document de reconnaissance, exactement ce que le ROADMAP a retiré du dépôt le
  15 août 2026. Il doit vivre dans un dossier d'état par utilisateur, jamais sur
  le Bureau ni dans un dossier de projet, et se réécrire à chaque appel.

### Écartée — interface en mode texte (TUI)

Pas de socket, pas de binaire, pas d'API. Mais elle ne rend ni la section
documentation ni les notes personnelles, qui sont une des cinq contraintes. Une
option qui échoue sur une contrainte acquise n'est pas une option.

---

## 4. La sécurité départage, et c'est le seul critère qui ne se rattrape pas

### A — ce qu'une socket en écoute exige, sans exception

Toute la boucle locale est accessible à **tout processus de la machine**, y
compris ceux qui ne sont pas à nous. Une interface non authentifiée sur
127.0.0.1 n'est pas « locale donc sûre ».

- Écoute sur `127.0.0.1` explicitement — jamais `0.0.0.0`, jamais `+`.
- Port éphémère, jamais fixe.
- Un secret par exécution, exigé sur **chaque** requête.
- Contrôle des en-têtes `Host` et `Origin` : sans lui, une page web quelconque
  peut faire pointer un domaine vers 127.0.0.1 et faire émettre les requêtes par
  le navigateur de l'utilisateur — **DNS rebinding**, que le profil global liste
  déjà parmi les protections obligatoires. La politique de même origine ne
  protège pas ici.
- Aucun en-tête CORS. Aucun.
- Et le fait qui pèse le plus : **le processus hôte porte les jetons dans son
  environnement**, puisque `work` les y exporte. La socket est donc un chemin
  vers une exécution qui les porte. C'est le même raisonnement qui a fait rejeter
  le terminal intégré ; il s'applique à la socket, en plus discret.

### B — ce qu'un pont IPC exige

Pas de socket, et c'est un vrai gain. En échange, la frontière se déplace :
`pwsh` doit être lancé avec un **tableau d'arguments**, jamais une ligne de
commande construite par concaténation, et l'appelable doit venir d'une **liste
fermée** de commandes du module. C'est faisable et c'est testable — mais c'est
du code à écrire dans un langage qui n'est pas celui du reste du projet.

### C — ce qu'un fichier sur disque exige

Le fichier est le risque, et il est simple à cadrer : dossier d'état par
utilisateur, permissions restreintes au propriétaire, réécrit à chaque appel.
Aucune socket, aucun processus qui survit à la commande, aucune exécution
déclenchable depuis la page.

---

## 5. Comparaison

| | A — web local | B — Tauri | C — rapport statique |
| --- | --- | --- | --- |
| Dette d'API publique | 2 exports | 2 exports + `-Json` partout | **aucune** |
| Socket en écoute | **oui** | non | non |
| Artefact hors PSGallery | non | **oui, par plateforme** | non |
| Nouvelle chaîne d'outils / CI | non | **oui (Rust)** | non |
| Second clic qui exécute | oui | oui | **non** |
| Barre système | non | oui | non |
| Rafraîchissement | oui | oui | **non** |
| Livrable aujourd'hui | semaines | mois | **jours** |

---

## 6. Recommandation

**C d'abord, et laisser l'usage réel dire si A ou B mérite d'être payé.**

Trois raisons, dans cet ordre.

1. **Elle ne crée aucune dette irréversible.** Aucun nom exporté, donc aucune
   promesse à tenir pour toujours. A et B en créent avant qu'un seul écran ait
   prouvé son utilité — et ce dépôt refuse déjà, explicitement, de promettre ce
   qu'il ne peut pas vérifier.
2. **Elle livre la part qui a de la valeur en premier.** *Quel dossier pointe où,
   quel jeton expire, quel projet est sur quel compte* — c'est de la lecture. La
   moitié « agir » existe déjà, elle s'appelle la CLI, et la console de commandes
   version C la sert quand même : elle montre la commande exacte et la copie.
3. **Elle est le seul choix qui n'ajoute pas de surface d'attaque** à un outil
   dont la fonction est de tenir des identifiants séparés.

Ce que la recommandation ne prétend pas : C n'est pas le tableau de bord du
ROADMAP. Il lui manque le second clic, la barre système et le rafraîchissement.
C'est un premier palier, pas la destination — et il faut le dire dans le
ROADMAP plutôt que laisser croire que 2.0 serait livré.

**Si la barre système est non négociable, la réponse est B, pas A.** Autant le
savoir tout de suite : dans ce cas `-Json` sur chaque lecture devient une
décision acquise, et elle se prend avant d'écrire l'UI, pas après.

---

## 7. Les questions, et ce qu'elles ont donné

1. ~~**Le tableau de bord doit-il AGIR, ou suffit-il qu'il MONTRE ?**~~ → il
   montre d'abord. Le second clic viendra si la lecture prouve son usage.
2. ~~**Doit-il vivre dans la barre système ?**~~ → **oui, mais ce n'est pas lui.**
   C'est le veilleur (2.1), qui ne montre que la casse et jamais l'identité.
3. ~~**Quelqu'un d'autre que toi l'utilisera-t-il ?**~~ → probablement. D'où
   l'installation en une commande pour le 2.0, et le binaire réservé au 2.1.

4. ~~**« Tout le monde » = Windows, ou multi-plateforme ?**~~ → **Windows**,
   tranché le 22/08/2026. Voir §0. Le port se rouvrira s'il y a un Mac pour le
   vérifier — jamais par accident.

**Plus aucune question ouverte sur la forme.** Le chantier suivant est du code :
la première tranche du 2.0.

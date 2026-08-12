# Isolation des contextes de travail

**Pourquoi ce dossier existe, et quel problème il résout**

*5 août 2026*

* * *

## Le problème

Le modèle de travail est le suivant : un client arrive, une boîte Gmail dédiée est créée pour son projet, et tous les comptes de service — GitHub, Vercel, Supabase — sont ouverts sous cette adresse. En fin de mission, l'ensemble est transféré au client. Le découpage est propre et la passation est nette.

Le coût de ce modèle, c'est que **chaque outil de développement ne sait tenir qu'une seule identité à la fois**. Passer d'un projet client à un projet personnel imposait donc une séquence de déconnexions et de reconnexions, sur chaque outil, à chaque changement de contexte.

Le point le plus bloquant était VS Code. Travailler sur les projets personnels exigeait de **déconnecter tous les comptes clients** — parce que les sessions d'authentification sont partagées au niveau de l'installation, pas du projet ouvert.

## Pourquoi ça arrive

Ces outils stockent l'authentification dans un **état global unique par machine** :

| Outil | Où vit l'identité |
| --- | --- |
| GitHub CLI | un seul dossier de configuration |
| Vercel CLI | un seul dossier de configuration |
| Supabase CLI | un seul jeton en session |
| VS Code | une base d'état par installation |

Un seul état actif à la fois, donc forcément du va\-et\-vient.

À noter : **les profils VS Code ne résolvent pas ce problème.** Ils isolent les réglages, les extensions et l'interface — mais pas les sessions d'authentification, qui restent communes. C'est la raison pour laquelle la déconnexion complète était nécessaire.

## Le principe retenu

Plutôt que de switcher plus vite, on supprime le switch.

Un **contexte** \= un dossier \+ un jeu de variables d'environnement.

Ces outils acceptent tous une authentification par variable d'environnement ou par dossier de configuration paramétrable. En rendant ces paramètres dépendants du contexte actif, l'identité devient **locale au terminal** au lieu d'être globale à la machine.

Concrètement : on tape `work acme`, et le terminal *est* l'identité Acme jusqu'à sa fermeture. Un autre terminal ouvert en parallèle peut être en personnel. Une fenêtre VS Code par contexte, chacune sur son propre compte, simultanément.

**Plus aucune déconnexion.**

## Il n'existe pas d'état neutre

C'est l'amendement du 5 août 2026, et il vient d'un incident réel.

La première version traitait le personnel comme un **état par défaut** : `ctx-off` effaçait toutes les variables et rendait la main. Or effacer `GH_CONFIG_DIR` ne rend pas la main à « personne » — ça la rend à la **configuration globale de la machine**, c'est-à-dire au dernier compte connecté, quel qu'il soit.

Conséquence : les projets clients étaient blindés, le projet personnel ne l'était pas. Et le garde-fou de réécriture d'URL n'était écrit que pour les racines clientes — rien ne protégeait `F:\PROJECTS\Apps`.

C'est le projet personnel qui a failli partir sur un compte client.

**Le personnel est donc un contexte comme les autres.** `ctx-off` bascule vers lui au lieu de tout vider. S'il n'existe pas encore, le module le dit en rouge plutôt que de laisser croire que l'état est propre : un état neutre, c'est l'identité du dernier qui a parlé.

## Rapporter ne suffit pas, il faut juger

Deuxième amendement du même jour.

La commande de vérification affichait l'identité git, le compte `gh`, la présence des jetons. Elle **rapportait** sans jamais **juger** — donc elle ne pouvait pas attraper le seul scénario qui compte réellement : *se tenir dans le dossier d'un contexte avec l'identité d'un autre*.

Elle rend maintenant un verdict, sur trois questions : le dossier courant appartient\-il au contexte actif, le compte GitHub authentifié est\-il celui que le manifeste attend, et un contexte est\-il seulement actif. `ctx-check` fait la même chose en levant, pour être branchable dans un script ou un hook.

Un affichage ne protège que celui qui le lit.

## Ce que contient ce dossier

**`DevContext.psm1`** — le module PowerShell. Il crée les contextes, les active, lance VS Code et Chrome sur le bon compte, vérifie la cohérence et gère la clôture de mission.

**`README.md`** — installation et commandes du quotidien.

**Ce document** — le raisonnement derrière l'outil, pour le jour où il faudra le modifier sans se souvenir des arbitrages d'origine.

## Ce que ça résout

**Le blocage VS Code.** Une base d'état par contexte, donc des comptes GitHub et Copilot indépendants, ouverts en même temps.

**Les allers\-retours de connexion.** Les jetons sont chargés depuis un coffre chiffré à l'activation du contexte. Les CLI ne se déconnectent jamais puisqu'ils ne partagent plus rien.

**Le risque de se tromper de projet.** C'est le point le plus important quand le code est produit par une IA. Chaque contexte réécrit les URL Git vers son propre alias SSH : depuis un dossier donné, pousser avec la mauvaise identité devient structurellement impossible, quelle que soit l'URL inscrite dans le remote. Le contexte personnel a désormais le sien — la protection joue **dans les deux sens**.

**La fin de mission.** Toute l'identité d'un client tient dans un seul dossier. La clôture affiche la liste de ce qui casse un transfert de comptes — double authentification encore liée au téléphone, moyen de paiement personnel, jetons non révoqués — puis efface l'identité de la machine sans toucher au dossier projet.

## Un mot sur les agents IA

Les jetons vivent en **variables d'environnement**. Tout processus enfant du terminal en hérite, y compris un agent lancé depuis ce terminal.

C'est voulu, et c'est la propriété centrale du dispositif : un agent lancé dans un contexte client peut travailler pour ce client, et **n'a jamais les secrets d'un autre**. Le corollaire est qu'un agent qui sort de la racine de son contexte emporte les jetons avec lui — d'où la vérification de correspondance dossier/contexte, qui est là exactement pour ça.

## Ce que ça ne résout pas

Il s'agit d'une isolation de **sessions**, pas d'une frontière cryptographique. Le chiffrement Windows utilisé est lié au compte utilisateur : les données restent déchiffrables par ce même utilisateur.

Contre le mélange accidentel de comptes, c'est efficace. Contre un attaquant ayant déjà la main sur la session Windows, non — cela demanderait des comptes Windows distincts ou des machines virtuelles par client.

Autre limite, à garder en tête pour un éventuel portage : sous Linux, le trousseau système est un service partagé, et cette approche n'y produirait pas la même isolation.

## Une brique autonome

Cet outillage ne dépend d'aucun autre projet et n'a pas vocation à en rejoindre un. Il s'installe, il tourne, il se modifie seul.

Ajouter un service supplémentaire — Stripe, Cloudflare, Resend — se résume à une ligne dans la table des secrets en tête du module : la commande de création la demandera, la commande d'activation la chargera.

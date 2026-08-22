# Tableau de bord — tranche 1 : le rapport généré

> **Pour les agents :** dérouler tâche par tâche, dans l'ordre. Les cases
> `- [ ]` servent au suivi. Lire `AGENTS.md` avant la première ligne de code.

**But :** `ctx dashboard` produit un rapport HTML autonome, l'écrit dans un
dossier d'état par utilisateur, et l'ouvre. Lecture seule.

**Ce que cette tranche ne fait pas**, et il faut le dire avant de commencer :
pas de second clic qui exécute, pas de rafraîchissement, pas de barre de
système. C'est le premier palier du 2.0, pas le 2.0.

**Coût en API publique : zéro.** Le rapport est généré *dans* le module, donc il
appelle `Get-CtxRaccourciChecks` et `Get-CtxMcpFacts` directement — les deux
fonctions internes que la mesure du 22/08 a trouvées non exportées. Aucun
`-Json` n'est requis, aucun nom nouveau ne sort. C'est exactement pourquoi cette
forme a été choisie.

**Architecture :** la séparation habituelle du module, dans cet ordre.

| Fonction | Rôle | Testable |
| --- | --- | --- |
| `Format-CtxDashboardHtml` | **pure** — des faits en entrée, une chaîne HTML en sortie | sans disque, sans machine configurée |
| `Get-CtxDashboardFacts` | rassemblement — appelle les fonctions existantes | avec des doublures |
| `Invoke-DevContextDashboard` | le seul effet de bord : écrire, ouvrir | avec `-NoOpen` |

**Pile :** PowerShell 7, Pester 6.1.0. Aucune dépendance nouvelle.

---

## Contraintes non négociables

Elles viennent du ROADMAP et de `SECURITY.md`. Chacune a sa tâche plus bas.

1. **Aucun secret dans la sortie.** Le rapport traverse les mêmes chemins que
   `ctx doctor`, qui n'imprime jamais la valeur d'une clé — seulement son nom.
2. **Le fichier écrit est un document de reconnaissance.** Il contient la
   topologie des comptes. Dossier d'état par utilisateur, permissions
   restreintes au propriétaire, réécrit à chaque appel. Jamais le Bureau,
   jamais un dossier de projet, jamais le dépôt.
3. **Aucune requête sortante depuis la page.** Pas de CDN, pas de police
   distante, pas d'image externe. Une page qui appelle le réseau depuis un
   outil d'identifiants annonce la topologie de son porteur à qui héberge la
   ressource.
4. **Échappement systématique.** Un nom de dossier, de branche, de compte ou de
   projet est une **donnée**, jamais du balisage.
5. **Aucune logique nouvelle.** Le rapport ne décide rien : il rend les verdicts
   que `ctx doctor` a déjà rendus. Deux implémentations dérivent, et celle qu'on
   croit est celle qu'on a ouverte.
6. **Chaque section vide nomme la commande suivante.** Une section vide est
   l'écran le plus important du produit.

---

## Phase 1 — le rendu pur

Rien ne touche le disque dans cette phase. C'est la moitié intéressante, donc
c'est celle qui se teste seule.

- [ ] `Format-CtxDashboardHtml` : signature et contrat. Prend les faits, rend
      une chaîne. Ne lit rien, n'écrit rien, ne résout aucun chemin.
- [ ] **L'échappement d'abord, avant le premier octet de mise en forme.** Un
      helper d'échappement, appelé sur *chaque* valeur interpolée.
- [ ] Test : un contexte nommé `<script>alert(1)</script>` ressort échappé.
      Un test **par type de champ** — nom de contexte, chemin, compte, libellé
      de projet, détail de verdict — pas un test global qui laisserait un champ
      oublié passer.
- [ ] Test : le HTML produit ne contient ni `http://`, ni `https://`, ni `src="//`.
      Contrainte 3, vérifiée sur la sortie et non sur l'intention.
- [ ] Test : pour chaque section, des faits vides produisent une phrase qui
      **nomme une commande**. Contrainte 6.
- [ ] `[System.IO.Path]::Combine` si un chemin doit être composé, jamais
      `Join-Path` — piège consigné dans `AGENTS.md` : c'est une applet de
      fournisseur, elle rend une chaîne vide sur un lecteur non monté.

## Phase 2 — le rassemblement

- [ ] `Get-CtxDashboardFacts` : appelle `Get-DevContextList`,
      `Get-DevContextDoctor`, `Get-DevEditorList`, `Get-CtxRaccourciChecks`,
      `Get-DevSupabaseMap`, `Get-CtxMcpFacts`. **Aucune décision recopiée.**
- [ ] `@()` au site d'appel de chaque fonction qui peut rendre zéro ou un
      élément — piège consigné : PowerShell déplie en traversant le flux, et un
      élément unique arrive en scalaire, en silence.
- [ ] Test : un verdict rendu par le rapport est **identique** à celui de
      `ctx doctor` sur les mêmes faits. C'est le garde-fou de la contrainte 5 ;
      sans lui, la dérive ne se verra qu'à l'usage.

## Phase 3 — l'écriture

- [ ] Emplacement : `$env:LOCALAPPDATA\DevContext\`, et **pas** le dossier
      courant. Résolu, jamais supposé.
- [ ] Permissions restreintes au propriétaire à la création.
- [ ] Réécriture à chaque appel — aucune accumulation d'anciens rapports, qui
      seraient autant de photographies périmées de la topologie.
- [ ] Test : le fichier n'atterrit ni dans le dossier courant, ni sur le
      Bureau, ni dans le dépôt. Vérifié sur le chemin réellement écrit.
- [ ] Test : deux appels successifs laissent **un** fichier.

## Phase 4 — la commande

- [ ] Sous-commande `dashboard` ajoutée à la table des sous-commandes.
      L'alias en `ctx-` s'en dérive : ne jamais l'ajouter à la main à côté —
      piège consigné, deux orthographes dont une morte.
- [ ] `-NoOpen` : produit le fichier sans lancer le navigateur. Nécessaire pour
      les tests et pour la CI.
- [ ] Test : la commande répond sous ses **deux** orthographes, la forme espacée
      et la forme à trait d'union, et les deux produisent le même fichier.
- [ ] Export : ajouter la fonction aux **deux** listes, psd1 et psm1. L'export
      réel est leur intersection.

## Phase 5 — sécurité, puis clôture

- [ ] Étendre `tests/Securite.Tests.ps1` : produire le rapport **avec les vrais
      jetons de la machine** chargés, et exiger qu'aucun caractère d'aucun
      d'eux n'apparaisse dans le fichier. C'est le test le plus sévère de la
      suite, et il existe déjà pour `ctx doctor` — il suffit de l'étendre.
- [ ] Vérifier sur la machine réelle, pas seulement dans le harnais : ouvrir le
      rapport produit et le lire.
- [ ] `Invoke-ScriptAnalyzer` propre sur les fichiers touchés.
- [ ] Suite verte, et **chaque nouveau test vu rougir** sur le défaut qu'il
      attrape.
- [ ] `CHANGELOG.md`, `README.md`, et `ROADMAP.md` §2.0 : première tranche
      livrée, avec ce qu'elle ne fait pas.

---

## Risques identifiés, et ce qui les couvre

| Risque | Ce qui l'attrape |
| --- | --- |
| Le rapport devient une seconde implémentation des règles | Test « même verdict que le diagnostic », phase 2 |
| Un champ échappé, un autre oublié | Un test **par type de champ**, phase 1 |
| Le fichier écrit devient un document de reconnaissance oublié sur le disque | ACL + emplacement + réécriture, phase 3 |
| Une ressource distante se glisse dans la page | Test sur la sortie produite, phase 1 |
| Un jeton finit dans le rapport | Extension du test de bout en bout, phase 5 |
| Deux orthographes de la commande dont une morte | Alias dérivé de la table, jamais recopié, phase 4 |

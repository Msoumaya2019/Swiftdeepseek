#!/usr/bin/env node
//
// verifier-flux.mjs — contrôle statique des flux GitHub Actions.
//
// POURQUOI
//   Ce dépôt n'a pas de Mac. La seule preuve qu'il compile est le flux
//   `.github/workflows/ios.yml`, qui tourne sur un exécuteur macOS : quinze
//   minutes par essai. Une faute de frappe dans un `run:` ne se découvre donc
//   qu'après un aller-retour complet — et c'est précisément ce que ce script
//   attrape en une seconde.
//
// PORTÉE — CE QUE CE CONTRÔLE VOIT, ET CE QU'IL NE VOIT PAS
//   Il lit le fichier de flux ligne à ligne, par indentation. Il n'analyse PAS
//   le YAML : un YAML mal formé est signalé par GitHub à la poussée, tout de
//   suite et gratuitement, donc ce n'est pas le défaut coûteux.
//
//   `bash -n` analyse sans évaluer les expansions. Mesuré sur bash 5.3 :
//     - `echo ${{ a }}`  est ACCEPTÉ par `bash -n` (et échoue à l'exécution) ;
//     - `echo ${x`       est REFUSÉ (accolade non fermée) ;
//     - un `then` manquant, un `fi` orphelin, une quote non fermée : REFUSÉS.
//   Autrement dit ce contrôle attrape la STRUCTURE du script, jamais la
//   validité d'une expansion. Une faute de frappe dans `${CHEMIN}` ne sera
//   signalée ni ici, ni par aucun autre contrôle statique.
//
// DÉPENDANCES
//   Aucune. Volontairement : le dépôt n'a pas de `package.json`, donc pas de
//   verrou à tenir, et pas de `npm ci` à casser. Node est déjà présent sur les
//   exécuteurs GitHub.
//
// LISTE FERMÉE
//   Les flux attendus sont nommés ci-dessous, dans les deux sens : un fichier
//   attendu qui disparaît échoue, un fichier ajouté et non déclaré échoue
//   aussi. Sans la liste fermée, un contrôle qui découvre ses sujets par
//   `readdir` mesure ce qui RESTE, jamais ce qui MANQUE.
//
//   LIMITE CONNUE : la liste ne compte qu'un élément. Un cas de banc qui
//   écrirait un seul fichier dans un dossier vide passerait donc au vert sans
//   rien mesurer. La falsification de ce contrôle a été faite par mutations
//   sur le fichier réel, pas sur un dossier fabriqué.
//
// Usage : node scripts/verifier-flux.mjs
// Sortie : 0 si aucun défaut, 1 au premier défaut (marqueur ASCII nommé).

import { readdirSync, readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

const RACINE = join(dirname(fileURLToPath(import.meta.url)), '..');
const DOSSIER = join(RACINE, '.github', 'workflows');

// ── La liste fermée ────────────────────────────────────────────────────────
const FLUX_ATTENDUS = ['ios.yml'];

let verifications = 0;
const defauts = [];

function signaler(marqueur, fichier, detail) {
  defauts.push(`${marqueur} ${fichier} — ${detail}`);
}

// ── Petits outils de lecture ───────────────────────────────────────────────
const indentDe = (l) => l.match(/^(\s*)/)[1].length;
const estVide = (l) => l.trim() === '';
const estCommentaire = (l) => l.trim().startsWith('#');
const significative = (l) => !estVide(l) && !estCommentaire(l);

/**
 * Les chaînes d'une structure, sans passer par une sérialisation.
 *
 * Mesuré ailleurs : inspecter `JSON.stringify(etape)` fait entrer les accolades
 * du JSON dans le sujet mesuré, et une expression laissée non fermée peut
 * alors trouver la fermeture d'un objet voisin. On travaille donc ligne par
 * ligne, sur du texte brut.
 */
function verifierExpressions(texte, fichier, ou) {
  // Ligne par ligne, et non sur le bloc entier. Une expression `${{ … }}` ne
  // s'étale jamais sur deux lignes dans un flux réel ; l'inspecter bloc à bloc
  // ferait trouver la fermeture d'une AUTRE expression située plus bas, et une
  // accolade manquante passerait alors inaperçue. Mesuré : sur l'étape qui écrit
  // Config/Secrets.xcconfig, retirer une accolade de la première expression
  // laisse la seconde fermer à sa place — le contrôle se taisait.
  texte.split(/\r?\n/).forEach((ligne, i) => {
    let depart = 0;
    for (;;) {
      const ouverture = ligne.indexOf('${{', depart);
      if (ouverture === -1) return;
      verifications += 1;
      const fermeture = ligne.indexOf('}}', ouverture + 3);
      if (fermeture === -1) {
        signaler('[expression-non-fermee]', fichier, `${ou}, ligne ${i + 1} — ouverture « \${{ » sans fermeture « }} »`);
        return;
      }
      depart = fermeture + 2;
    }
  });
}

/** Extrait un bloc scalaire (`run: |`) ou une valeur en ligne. */
function lireScript(lignes, i, indentCle) {
  const valeur = lignes[i].replace(/^\s*(?:-\s+)?run:[ \t]?/, '');
  if (valeur !== '|' && valeur !== '|-' && valeur !== '>' && valeur !== '>-') {
    return { script: valeur, fin: i };
  }
  const corps = [];
  let j = i + 1;
  for (; j < lignes.length; j += 1) {
    const l = lignes[j];
    if (significative(l) && indentDe(l) <= indentCle) break;
    corps.push(l);
  }
  return { script: corps.join('\n'), fin: j - 1 };
}

function bashNAccepte(script) {
  const neutralise = script.replace(/\$\{\{[^}]*\}\}/g, 'VALEUR');
  const dossier = mkdtempSync(join(tmpdir(), 'bashn-'));
  const chemin = join(dossier, 'script.sh');
  try {
    writeFileSync(chemin, neutralise, 'utf8');
    const r = spawnSync('bash', ['-n', chemin], { encoding: 'utf8' });
    if (r.error) return { ok: true, note: `bash indisponible (${r.error.code})` };
    return { ok: r.status === 0, message: (r.stderr || '').trim().split('\n')[0] || '' };
  } finally {
    rmSync(dossier, { recursive: true, force: true });
  }
}

// ── Liste fermée, dans les deux sens ───────────────────────────────────────
const presents = readdirSync(DOSSIER)
  .filter((n) => n.endsWith('.yml') || n.endsWith('.yaml'))
  .sort();

for (const nom of FLUX_ATTENDUS) {
  verifications += 1;
  if (!presents.includes(nom)) {
    signaler('[flux-absent]', nom, 'flux attendu absent du dossier .github/workflows');
  }
}
for (const nom of presents) {
  verifications += 1;
  if (!FLUX_ATTENDUS.includes(nom)) {
    signaler('[flux-non-declare]', nom, 'flux présent mais absent de FLUX_ATTENDUS');
  }
}

// ── Analyse de chaque flux ─────────────────────────────────────────────────
for (const nom of presents) {
  if (!FLUX_ATTENDUS.includes(nom)) continue;
  const chemin = join(DOSSIER, nom);
  const brut = readFileSync(chemin, 'utf8');
  const lignes = brut.split(/\r?\n/);

  // (1) Ligne à la colonne 0 qui n'est pas une clé de premier niveau : le
  //     défaut classique d'un extrait Python ou JS multiligne collé dans un
  //     `run: |`. Le bloc scalaire se termine à la colonne 0, et GitHub répond
  //     alors « Implicit keys need to be on a single line » — un message qui
  //     nomme une ligne du YAML, jamais la cause.
  lignes.forEach((l, i) => {
    if (!significative(l)) return;
    if (indentDe(l) !== 0) return;
    if (l.trim() === '---') return;
    verifications += 1;
    if (!/^[A-Za-z_][A-Za-z0-9_-]*:/.test(l)) {
      signaler('[colonne-zero]', nom, `ligne ${i + 1} : « ${l.trim().slice(0, 40)} » — un bloc scalaire s'arrête à la colonne 0`);
    }
  });

  // (2) Déclencheur `on:` au premier niveau.
  verifications += 1;
  if (!lignes.some((l) => /^on:/.test(l))) {
    signaler('[declencheur-absent]', nom, 'aucune clé « on: » au premier niveau');
  }

  // (3) Permissions : déclarées à la racine ou sur le travail.
  //     Le drapeau `m` est indispensable : sans lui, `^` ne teste que la
  //     position 0 du fichier — c'est-à-dire la première ligne, qui est un
  //     commentaire. Le bloc `permissions:` du premier niveau était alors
  //     invisible, et le contrôle accusait un flux qui venait d'être corrigé.
  const racinePermissions = /^permissions:/m.test(brut);
  verifications += 1;
  if (!racinePermissions && !/^\s+permissions:/m.test(brut)) {
    signaler('[permissions-absentes]', nom, 'aucun bloc « permissions: » — le jeton reçoit des droits plus larges que nécessaire');
  }

  // (4) Travaux : `runs-on` présent, et permissions effectives.
  //     Sémantique du piège : un `permissions` de travail REMPLACE celui de la
  //     racine, il ne s'y ajoute pas.
  const iJobs = lignes.findIndex((l) => /^jobs:/.test(l));
  if (iJobs === -1) {
    signaler('[travaux-absents]', nom, 'aucune clé « jobs: »');
  } else {
    let finJobs = lignes.length;
    for (let i = iJobs + 1; i < lignes.length; i += 1) {
      if (significative(lignes[i]) && indentDe(lignes[i]) === 0) { finJobs = i; break; }
    }
    const nomsTravaux = [];
    for (let i = iJobs + 1; i < finJobs; i += 1) {
      if (significative(lignes[i]) && indentDe(lignes[i]) === 2 && /^[A-Za-z0-9_-]+:/.test(lignes[i].trim())) {
        nomsTravaux.push({ nom: lignes[i].trim().replace(/:$/, ''), ligne: i });
      }
    }
    nomsTravaux.forEach((travail, k) => {
      const debut = travail.ligne + 1;
      const fin = k + 1 < nomsTravaux.length ? nomsTravaux[k + 1].ligne : finJobs;
      const corps = lignes.slice(debut, fin);
      const ou = `travail « ${travail.nom} »`;

      verifications += 1;
      if (!corps.some((l) => /^\s+runs-on:/.test(l))) {
        signaler('[runs-on-absent]', nom, `${ou} : aucune clé « runs-on: »`);
      }

      // Permissions effectives.
      const iP = corps.findIndex((l) => /^\s+permissions:/.test(l));
      let effectives = racinePermissions ? 'racine' : null;
      let contenuEcriture = false;
      if (iP !== -1) {
        const indentP = indentDe(corps[iP]);
        if (/permissions:\s*(read-all|write-all)/.test(corps[iP])) {
          contenuEcriture = /write-all/.test(corps[iP]);
        } else {
          for (let i = iP + 1; i < corps.length; i += 1) {
            if (significative(corps[i]) && indentDe(corps[i]) <= indentP) break;
            if (/^\s+contents:\s*write/.test(corps[i])) contenuEcriture = true;
          }
        }
        effectives = 'travail';
      } else if (/^permissions:\s*write-all/m.test(brut)) {
        contenuEcriture = true;
      } else if (racinePermissions) {
        const iR = lignes.findIndex((l) => /^permissions:/.test(l));
        for (let i = iR + 1; i < lignes.length; i += 1) {
          if (significative(lignes[i]) && indentDe(lignes[i]) === 0) break;
          if (/^\s+contents:\s*write/.test(lignes[i])) contenuEcriture = true;
        }
      }

      // (5) Une étape qui publie une version exige `contents: write`.
      const texteTravail = corps.join('\n');
      if (/gh\s+release\s+create/.test(texteTravail)) {
        verifications += 1;
        if (!contenuEcriture) {
          signaler(
            '[permissions-insuffisantes]',
            nom,
            `${ou} : « gh release create » exige « contents: write » (permissions effectives : ${effectives ?? 'aucune'})`,
          );
        }
      }

      // (6) Étapes : chacune fait quelque chose, les actions sont épinglées.
      const iSteps = corps.findIndex((l) => /^\s+steps:/.test(l));
      if (iSteps === -1) {
        signaler('[etapes-absentes]', nom, `${ou} : aucune clé « steps: »`);
        return;
      }
      const indentSteps = indentDe(corps[iSteps]);
      const items = [];
      for (let i = iSteps + 1; i < corps.length; i += 1) {
        const l = corps[i];
        if (significative(l) && indentDe(l) <= indentSteps) break;
        if (/^\s*-\s/.test(l) && indentDe(l) === indentSteps + 2) {
          items.push({ ligne: i, nom: `étape ${items.length + 1}` });
        }
      }

      items.forEach((item, n) => {
        const debutItem = item.ligne;
        const finItem = n + 1 < items.length ? items[n + 1].ligne : corps.length;
        const bloc = corps.slice(debutItem, finItem);
        const texteBloc = bloc.join('\n');

        // Le nom lisible, pour que le message désigne l'étape.
        const mNom = texteBloc.match(/^\s*(?:-\s+)?name:\s*(.+)$/m);
        const etiquette = mNom ? `${item.nom} « ${mNom[1].trim()} »` : item.nom;

        const aUses = /^\s*(?:-\s+)?uses:/m.test(texteBloc);
        const aRun = /^\s*(?:-\s+)?run:/m.test(texteBloc);

        verifications += 1;
        if (!aUses && !aRun) {
          signaler('[etape-vide]', nom, `${ou} › ${etiquette} : ni « uses: » ni « run: »`);
        }

        if (aUses) {
          const mUses = texteBloc.match(/^\s*(?:-\s+)?uses:\s*(\S+)\s*$/m);
          if (mUses) {
            verifications += 1;
            const ref = mUses[1];
            const epinglee = ref.includes('@') || ref.startsWith('./') || ref.startsWith('docker://');
            if (!epinglee) {
              signaler('[action-non-epinglee]', nom, `${ou} › ${etiquette} : « ${ref} » sans « @version »`);
            }
          }
        }

        // Les expressions sont vérifiées pour TOUTES les étapes, y compris
        // celles qui n'ont qu'un `uses:` — c'est là que se trouvent souvent
        // `retention-days:` ou `if:`.
        verifierExpressions(texteBloc, nom, `${ou} › ${etiquette}`);

        if (aRun) {
          // Chaque `run:` du bloc, y compris sous forme d'élément de liste.
          for (let i = 0; i < bloc.length; i += 1) {
            const m = bloc[i].match(/^(\s*)(?:-\s+)?run:[ \t]?/);
            if (!m) continue;
            const indentCle = m[1].length;
            const { script, fin } = lireScript(bloc, i, indentCle);
            verifications += 1;
            const verdict = bashNAccepte(script);
            if (!verdict.ok) {
              signaler('[script-invalide]', nom, `${ou} › ${etiquette} : refusé par \`bash -n\` — ${verdict.message}`);
            }
            i = fin;
          }
        }
      });
    });
  }
}

// ── Verdict ────────────────────────────────────────────────────────────────
const nbFlux = presents.filter((n) => FLUX_ATTENDUS.includes(n)).length;
console.log(`verifier-flux : ${nbFlux} flux analysé(s), ${verifications} vérification(s).`);

if (defauts.length > 0) {
  console.log('');
  for (const d of defauts) console.log(`  ${d}`);
  console.log('');
  console.log(`${defauts.length} défaut(s) — code de sortie 1.`);
  process.exit(1);
}
console.log('Aucun défaut.');

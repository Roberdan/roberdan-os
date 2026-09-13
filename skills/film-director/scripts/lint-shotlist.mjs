#!/usr/bin/env node
/**
 * lint-shotlist.mjs — enforces the film-director shot grammar (R1-R11 + structure).
 * Usage: node lint-shotlist.mjs shotlist.json
 * Exit 0 = pass, 1 = violations, 2 = bad input.
 */
import { readFileSync } from 'node:fs';

const SCALES = ['WS', 'MS', 'MCU', 'CU', 'ECU', 'INSERT', 'TEXT'];
const RANK = { WS: 0, MS: 1, MCU: 2, CU: 3, ECU: 4 };
const MOTIONS = ['static', 'pan', 'tilt', 'dolly in', 'dolly out', 'track', 'handheld', 'crane', 'rack focus'];
const SOURCES = ['live', 'screen', 'sora', 'remotion', 'blender', 'stock'];

const path = process.argv[2];
if (!path) {
  console.error('usage: lint-shotlist.mjs <shotlist.json>');
  process.exit(2);
}

let film;
try {
  film = JSON.parse(readFileSync(path, 'utf8'));
} catch (err) {
  console.error(`cannot parse ${path}: ${err.message}`);
  process.exit(2);
}

const errors = [];
const warnings = [];
const fail = (rule, where, msg) => errors.push([rule, where, msg]);
const warn = (rule, where, msg) => warnings.push([rule, where, msg]);

const scenes = Array.isArray(film.scenes) ? film.scenes : [];
const shots = scenes.flatMap((s) => (s.shots || []).map((sh) => ({ ...sh, scene: s })));

if (shots.length === 0) {
  console.error('shot list contains no shots');
  process.exit(2);
}

// ---- field validity -------------------------------------------------------
for (const sh of shots) {
  const at = sh.id || '(unnamed shot)';
  if (!SCALES.includes(sh.scale)) fail('FIELD', at, `scale "${sh.scale}" not in ${SCALES.join('|')}`);
  if (!MOTIONS.includes(sh.motion)) fail('FIELD', at, `motion "${sh.motion}" not in ${MOTIONS.join('|')}`);
  if (!SOURCES.includes(sh.source)) fail('FIELD', at, `source "${sh.source}" not in ${SOURCES.join('|')}`);
  if (typeof sh.duration !== 'number' || sh.duration <= 0) fail('FIELD', at, 'duration must be a positive number');
  if (typeof sh.azimuth !== 'number') fail('FIELD', at, 'azimuth (degrees) is required');
  if (!['mid-action', 'on-hold'].includes(sh.cutPoint)) fail('FIELD', at, 'cutPoint must be mid-action or on-hold');
}

// ---- R6 motivated moves ---------------------------------------------------
for (const sh of shots) {
  const m = String(sh.motivation || '').trim().toLowerCase();
  if (!m || m === 'none' || m === 'n/a') fail('R6', sh.id, 'every shot needs a motivation; decorative movement is banned');
  if (m.includes('ken burns')) fail('R6', sh.id, 'Ken Burns on a still is not a camera move');
}

// ---- R10 depth ------------------------------------------------------------
for (const sh of shots) {
  if (sh.scale !== 'TEXT' && !String(sh.foreground || '').trim()) {
    fail('R10', sh.id, 'non-text shots must name a foreground element (depth)');
  }
}

// ---- per-scene checks -----------------------------------------------------
for (const scene of scenes) {
  const list = scene.shots || [];
  const where = scene.id || scene.name || '(unnamed scene)';

  // R4 180 degree rule
  const sides = new Set(list.map((s) => s.axisSide || scene.axisSide).filter(Boolean));
  if (sides.size > 1) {
    const crossing = list.some((s) => /cross|neutral|axis/i.test(String(s.motivation || '')));
    if (!crossing) fail('R4', where, `mixes axis sides (${[...sides].join(', ')}) with no motivated crossing shot`);
  }

  // R8 coverage
  if (!scene.textOnly && list.length >= 2) {
    const ranks = new Set(list.map((s) => s.scale));
    const hasWide = ranks.has('WS');
    const hasMedium = ranks.has('MS') || ranks.has('MCU');
    const hasDetail = ranks.has('CU') || ranks.has('ECU') || ranks.has('INSERT');
    if (!(hasWide && hasMedium && hasDetail)) {
      fail('R8', where, 'coverage incomplete: needs establishing (WS) + medium (MS/MCU) + detail (CU/ECU/INSERT)');
    }
    if (list.length < 4) warn('R8', where, `only ${list.length} setups; four is the planned minimum`);
  }

  // adjacency rules inside the scene
  for (let i = 1; i < list.length; i++) {
    const a = list[i - 1];
    const b = list[i];
    const at = `${a.id} -> ${b.id}`;
    if (a.scale === 'TEXT' || b.scale === 'TEXT') continue;

    if (a.scale === b.scale && a.motion === 'static' && b.motion === 'static') {
      fail('R1', at, 'cut between two static compositions of the same scale');
    }

    const azDiff = Math.abs(((b.azimuth - a.azimuth + 540) % 360) - 180);
    if (azDiff < 30) fail('R2', at, `azimuth changes only ${azDiff.toFixed(0)} deg; the 30 deg rule needs >= 30`);

    if (RANK[a.scale] !== undefined && RANK[b.scale] !== undefined && Math.abs(RANK[a.scale] - RANK[b.scale]) < 1) {
      fail('R3', at, 'no size change between consecutive shots of the same subject');
    }
  }
}

// ---- R7 adjacent text-only shots -----------------------------------------
for (let i = 1; i < shots.length; i++) {
  if (shots[i - 1].scale === 'TEXT' && shots[i].scale === 'TEXT') {
    fail('R7', `${shots[i - 1].id} -> ${shots[i].id}`, 'two adjacent text-only shots: this is a slideshow');
  }
}

// ---- R5 cut on action -----------------------------------------------------
const cuttable = shots.filter((s) => s.scale !== 'TEXT');
const midAction = cuttable.filter((s) => s.cutPoint === 'mid-action').length;
const midRatio = cuttable.length ? midAction / cuttable.length : 0;
if (midRatio < 0.4) fail('R5', 'film', `only ${(midRatio * 100).toFixed(0)}% of cuts land mid-action; need >= 40%`);

// ---- R9 J/L cuts ----------------------------------------------------------
const transitions = shots.length - 1;
const offset = shots.slice(1).filter((s) => typeof s.audioLead === 'number' && Math.abs(s.audioLead) >= 0.1).length;
const jlRatio = transitions ? offset / transitions : 0;
if (jlRatio < 0.3) fail('R9', 'film', `only ${(jlRatio * 100).toFixed(0)}% of transitions are J/L cuts; need >= 30%`);

// ---- R11 crossfade budget -------------------------------------------------
for (const sh of shots) {
  if (/dissolve|crossfade|cross fade/i.test(String(sh.transitionIn || ''))) {
    if (!/time|place|elsewhere|later|jump/i.test(String(sh.motivation || ''))) {
      fail('R11', sh.id, 'dissolve without a jump in time or place');
    }
  }
}

// ---- structure ------------------------------------------------------------
const total = shots.reduce((n, s) => n + (s.duration || 0), 0);
const target = film.targetDuration || total;
const asl = total / shots.length;
const per120 = (shots.length / total) * 120;

if (Math.abs(total - target) > Math.max(3, target * 0.05)) {
  fail('STRUCT', 'film', `shot durations sum to ${total.toFixed(1)}s but targetDuration is ${target}s`);
}
if (per120 < 30) fail('STRUCT', 'film', `${per120.toFixed(0)} shots per 120s: under 30 is a slideshow (target 45-55)`);
if (per120 > 80) warn('STRUCT', 'film', `${per120.toFixed(0)} shots per 120s: over 80 reads as a trailer`);
if (asl < 1.5 || asl > 4) fail('STRUCT', 'film', `ASL ${asl.toFixed(2)}s outside the 1.5-4s band`);

const mean = total / shots.length;
const sd = Math.sqrt(shots.reduce((n, s) => n + ((s.duration || 0) - mean) ** 2, 0) / shots.length);
if (sd / mean < 0.25) fail('STRUCT', 'film', `rhythm is mechanical (duration CV ${(sd / mean).toFixed(2)}); vary shot lengths`);

let elapsed = 0;
for (const sh of shots) {
  if (elapsed < 12 && (sh.scale === 'TEXT' || String(sh.text || '').trim())) {
    fail('STRUCT', sh.id, 'typography inside the first 12s: the hook is one image and one sound');
  }
  elapsed += sh.duration || 0;
}

const last = shots[shots.length - 1];
if (last.scale !== 'TEXT' || !String(last.text || '').trim()) {
  warn('STRUCT', last.id, 'film does not end on a text card with the ask');
} else if ((last.duration || 0) < 2.5) {
  fail('STRUCT', last.id, `end card held ${last.duration}s; hold >= 2.5s`);
}

const generated = shots.filter((s) => ['sora', 'stock'].includes(s.source)).length;
const real = shots.filter((s) => ['live', 'screen'].includes(s.source)).length;
if (real === 0) fail('STRUCT', 'film', 'no live or screen shots: the product never appears');
if (generated > real * 2) warn('STRUCT', 'film', 'generated atmosphere outweighs real footage 2:1');

// ---- report ---------------------------------------------------------------
for (const [rule, where, msg] of warnings) console.log(`warn  ${rule.padEnd(6)} ${where}: ${msg}`);
for (const [rule, where, msg] of errors) console.log(`FAIL  ${rule.padEnd(6)} ${where}: ${msg}`);

console.log(
  `\n${shots.length} shots  ${total.toFixed(1)}s  ASL ${asl.toFixed(2)}s  ` +
    `${per120.toFixed(0)}/120s  mid-action ${(midRatio * 100).toFixed(0)}%  J/L ${(jlRatio * 100).toFixed(0)}%`
);
console.log(`${errors.length} violations, ${warnings.length} warnings`);
process.exit(errors.length ? 1 : 0);

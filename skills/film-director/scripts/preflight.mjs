#!/usr/bin/env node
import {
  accessSync, constants, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync,
  rmdirSync, statSync, unlinkSync, writeFileSync,
} from 'node:fs';
import { dirname, isAbsolute, join } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const fail = (message) => { throw new Error(message); };
const requireThat = (condition, message) => { if (!condition) fail(message); };
const text = (value) => typeof value === 'string' && value.trim().length > 0;
const digest = (value) => createHash('sha256').update(value).digest('hex');
const hash = (path) => digest(readFileSync(path));
const json = (path) => JSON.parse(readFileSync(path, 'utf8'));
function pathCheck(path, directory = false) {
  requireThat(text(path) && isAbsolute(path), 'path must be absolute');
  requireThat(realpathSync(path) === path, `path must be canonical: ${path}`);
  const stat = statSync(path);
  requireThat(directory ? stat.isDirectory() : stat.isFile() && stat.size > 0, `invalid path: ${path}`);
  requireThat(stat.uid === process.getuid(), `filesystem owner mismatch: ${path}`);
  accessSync(path, constants.R_OK | (directory ? constants.X_OK : 0));
  return path;
}
function ref(value) {
  requireThat(value && /^[a-f0-9]{64}$/.test(value.sha256), 'missing content hash');
  pathCheck(value.path);
  requireThat(hash(value.path) === value.sha256, `stale content hash: ${value.path}`);
  return value.path;
}
function media(path, pilot = false) {
  const result = spawnSync('ffprobe', ['-v', 'error', '-show_format', '-show_streams', '-of', 'json', path],
    { encoding: 'utf8', timeout: 30000 });
  requireThat(!result.error && result.status === 0, `ffprobe failed: ${result.error?.message || result.stderr}`);
  const data = JSON.parse(result.stdout);
  const duration = Number(data.format?.duration);
  requireThat(Number.isFinite(duration) && duration > 0, 'invalid media duration');
  requireThat(data.streams.some((s) => s.codec_type === 'audio'), 'media missing audio');
  if (pilot) {
    requireThat(path.endsWith('.mp4') && data.format.format_name.split(',').includes('mp4'), 'pilot must be MP4');
    requireThat(duration >= 10 && duration <= 15, 'pilot must be 10-15 seconds');
    requireThat(data.streams.some((s) => s.codec_type === 'video'), 'pilot missing video');
  }
  return duration;
}
function save(path, value) {
  const tmp = `${path}.${randomUUID()}.tmp`;
  try {
    writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    renameSync(tmp, path);
  } finally {
    try { unlinkSync(tmp); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}
function review(value, bindings, fields) {
  const data = json(ref(value));
  requireThat(text(data.reviewedBy), 'review requires named reviewer');
  for (const [key, expected] of Object.entries(bindings)) {
    requireThat(data[key] === expected, `review mismatch: ${key}`);
  }
  for (const field of fields) requireThat(text(data[field]), `review requires written ${field}, not a Boolean`);
}

const [command, manifestPath, arg, extra] = process.argv.slice(2);
try {
  requireThat(['probe', 'check', 'reserve', 'accept', 'reconcile', 'observe'].includes(command),
    'usage: preflight.mjs probe|check|reserve|accept|reconcile|observe /absolute/manifest.json [args]');
  pathCheck(manifestPath);
  const m = json(manifestPath);
  requireThat(m.version === 1 && text(m.owner) && text(m.revision) && text(m.worker), 'manifest needs version/owner/revision/worker');
  requireThat(['prototype', 'production'].includes(m.phase), 'phase must be prototype or production');
  pathCheck(m.outputDir, true);
  const statePath = join(m.outputDir, '.film-preflight-state.json');
  const probePath = join(m.outputDir, '.film-worker-probe.json');
  const identity = { manifestPath, owner: m.owner, outputDir: m.outputDir };
  function state() {
    const s = json(pathCheck(statePath));
    for (const [key, value] of Object.entries(identity)) requireThat(s[key] === value, `state mismatch: ${key}`);
    requireThat(Array.isArray(s.jobs) && Array.isArray(s.artifacts) &&
      Number.isInteger(s.noProgress) && s.noProgress >= 0, 'invalid durable state');
    const keys = s.jobs.map((j) => j.key), fingerprints = s.jobs.map((j) => j.fingerprint);
    requireThat(new Set(keys).size === keys.length && new Set(fingerprints).size === fingerprints.length,
      'duplicate jobs in durable state');
    const ids = s.jobs.map((j) => j.id).filter(Boolean);
    requireThat(new Set(ids).size === ids.length, 'duplicate accepted job IDs');
    for (const j of s.jobs) requireThat(text(j.key) && /^[a-f0-9]{64}$/.test(j.fingerprint) &&
      ['uncertain', 'accepted', 'running', 'completed', 'failed', 'cancelled', 'rejected'].includes(j.status),
    'invalid job state');
    return s;
  }
  function locked(fn) {
    const lock = `${statePath}.lock`;
    mkdirSync(lock); // A crashed writer leaves a visible lock; inspect before removing it.
    try { return fn(); } finally { rmdirSync(lock); }
  }
  function timing() {
    const duration = media(ref(m.narration));
    const t = json(ref(m.timing));
    requireThat(t.narrationSha256 === m.narration.sha256 && t.revision === m.revision &&
      text(t.lockedBy) && Number.isFinite(t.durationSeconds) &&
      Math.abs(t.durationSeconds - duration) <= 0.1, 'narration timing must be fixed for this revision');
  }
  function binding() {
    return digest(JSON.stringify({ ...identity, revision: m.revision, worker: m.worker,
      narration: m.narration, timing: m.timing }));
  }
  function check() {
    timing();
    const p = json(pathCheck(probePath));
    requireThat(p.kind === 'worker-execution-v1' && p.binding === binding() &&
      p.worker === m.worker && Number.isInteger(p.pid) && text(p.node), 'missing or stale execution evidence');
    ref(p.write);
    review(m.executionReview, { probeSha256: hash(probePath) }, ['notes']);
    const s = state();
    requireThat(s.noProgress < 2, 'two no-progress observations: stop expansion; inspect a new artifact');
    requireThat(!s.jobs.some((j) => ['uncertain', 'accepted', 'running'].includes(j.status)),
      'unresolved job: resume/reconcile existing work, never recreate');
    if (m.phase === 'prototype') {
      requireThat(s.jobs.filter((j) => j.phase === 'prototype').length < 2, 'prototype acquisition limited to two clips');
    } else {
      requireThat(m.pilot && dirname(m.pilot.path || '') === m.outputDir, 'pilot must be in authoritative outputDir');
      media(ref(m.pilot), true);
      ref(m.captions);
      review(m.pilotReview, { pilotSha256: m.pilot.sha256, narrationSha256: m.narration.sha256,
        captionsSha256: m.captions.sha256, timingSha256: m.timing.sha256, revision: m.revision },
      ['captions', 'privacy', 'legibility', 'voice']);
    }
    return s;
  }
  if (command === 'probe') {
    timing();
    locked(() => {
      try { state(); } catch (error) {
        if (error.code !== 'ENOENT' || error.path !== statePath) throw error;
        save(statePath, { ...identity, jobs: [], artifacts: [], noProgress: 0 });
      }
      const writePath = join(m.outputDir, `.film-worker-write-${randomUUID()}`);
      const challenge = randomUUID();
      const run = spawnSync(process.execPath, ['-e',
        'require("node:fs").writeFileSync(process.argv[1],process.argv[2],{flag:"wx",mode:0o600});console.log(process.version)',
        writePath, challenge], { encoding: 'utf8', timeout: 10000 });
      requireThat(!run.error && run.status === 0 && readFileSync(writePath, 'utf8') === challenge,
        `worker execution/write probe failed: ${run.error?.message || run.stderr}`);
      save(probePath, { kind: 'worker-execution-v1', binding: binding(), worker: m.worker,
        pid: run.pid, node: run.stdout.trim(), at: new Date().toISOString(),
        write: { path: writePath, sha256: hash(writePath) } });
    });
    console.log(probePath);
  } else if (command === 'check') {
    check();
    if (arg) {
      requireThat(isAbsolute(arg) && dirname(arg) === m.outputDir, 'shot output must be absolute in authoritative outputDir');
      pathCheck(dirname(arg), true);
      const output = lstatSync(arg, { throwIfNoEntry: false });
      if (output) {
        requireThat(!output.isSymbolicLink(), 'shot output must not be a symlink');
        pathCheck(arg);
      }
    }
    console.log('preflight passed (consistency only; not spending approval)');
  } else if (command === 'reserve') {
    locked(() => {
      const s = check();
      requireThat(text(arg) && text(extra), 'reserve requires request key and exact request body');
      const fingerprint = digest(extra);
      requireThat(!s.jobs.some((j) => j.key === arg || j.fingerprint === fingerprint), 'duplicate request: inspect existing job');
      s.jobs.push({ key: arg, fingerprint, phase: m.phase, revision: m.revision,
        status: 'uncertain', at: new Date().toISOString() });
      save(statePath, s); // Persist BEFORE dispatch; even a lost response cannot become a fresh attempt.
    });
  } else if (command === 'accept' || command === 'reconcile') {
    locked(() => {
      const s = state(), job = s.jobs.find((j) => j.key === arg);
      requireThat(job, 'unknown request key');
      if (command === 'accept') {
        requireThat(job.status === 'uncertain' && text(extra), 'accept requires uncertain request and returned ID');
        requireThat(!s.jobs.some((j) => j.id === extra), 'duplicate accepted job ID');
        job.id = extra;
        job.status = 'accepted';
      } else {
        const receipt = json(pathCheck(extra));
        requireThat(receipt.key === arg && text(receipt.reviewedBy) && text(receipt.notes) &&
          ['completed', 'failed', 'cancelled', 'rejected'].includes(receipt.status), 'invalid reconciliation receipt');
        requireThat(receipt.status === 'rejected' ? !job.id && !receipt.id : text(receipt.id) &&
          (!job.id || job.id === receipt.id), 'reconciliation ID mismatch');
        requireThat(!receipt.id || !s.jobs.some((j) => j !== job && j.id === receipt.id), 'duplicate reconciliation ID');
        Object.assign(job, { status: receipt.status, id: receipt.id,
          reconciliation: { path: extra, sha256: hash(extra) } });
      }
      save(statePath, s);
    });
  } else {
    locked(() => {
      const s = state();
      requireThat(text(arg), 'observe requires absolute inspectable MP4 or "-" for no artifact');
      let sha256;
      if (arg !== '-') {
        requireThat(dirname(arg) === m.outputDir, 'artifact must be in authoritative outputDir');
        media(pathCheck(arg), true);
        sha256 = hash(arg);
      }
      if (!sha256 || s.artifacts.some((a) => a.sha256 === sha256)) s.noProgress++;
      else { s.artifacts.push({ path: arg, sha256 }); s.noProgress = 0; }
      save(statePath, s);
      console.log(`no-progress observations: ${s.noProgress}`);
    });
  }
} catch (error) {
  console.error(`film preflight: ${error.message}`);
  process.exitCode = 1;
}

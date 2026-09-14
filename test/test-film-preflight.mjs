#!/usr/bin/env node
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  appendFileSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync,
  realpathSync, rmSync, symlinkSync, unlinkSync, writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const root = realpathSync(join(dirname(fileURLToPath(import.meta.url)), '..'));
const cli = join(root, 'skills/film-director/scripts/preflight.mjs');
const adapter = join(root, 'skills/film-director/scripts/sora-azure.sh');
const tmp = mkdtempSync(join(root, '.film-preflight-test-'));
after(() => rmSync(tmp, { recursive: true }));
const sha = (path) => createHash('sha256').update(readFileSync(path)).digest('hex');
const ref = (path) => ({ path, sha256: sha(path) });
const read = (path) => JSON.parse(readFileSync(path, 'utf8'));
const write = (path, value) => writeFileSync(path, JSON.stringify(value));
function run(program, args, options = {}) {
  const result = spawnSync(program, args, { encoding: 'utf8', timeout: 30000, ...options });
  assert.ifError(result.error);
  return result;
}
function ok(result) {
  assert.equal(result.status, 0, result.stderr);
  return result;
}
function bad(result, pattern) {
  assert.notEqual(result.status, 0, 'unexpected success');
  assert.match(result.stderr, pattern);
}
const ffmpeg = (...args) => ok(run('ffmpeg', ['-v', 'error', '-nostdin', '-y', ...args]));
const seed = join(tmp, 'seed.mp4'), voice = join(tmp, 'voice.wav');
ffmpeg('-f', 'lavfi', '-i', 'color=c=black:s=160x90:r=10',
  '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=16000',
  '-t', '12', '-c:v', 'mpeg4', '-c:a', 'aac', seed);
ffmpeg('-i', seed, '-vn', '-c:a', 'pcm_s16le', voice);
const noAudio = join(tmp, 'no-audio.mp4');
ffmpeg('-i', seed, '-an', '-c:v', 'copy', noAudio);
const noVideo = join(tmp, 'no-video.mp4');
ffmpeg('-i', seed, '-vn', '-c:a', 'copy', noVideo);
let serial = 0;
function fixture(phase = 'production') {
  const dir = join(tmp, `case-${serial++}`), out = join(dir, 'output');
  mkdirSync(out, { recursive: true });
  const manifest = join(dir, 'manifest.json'), narration = join(dir, 'voice.wav');
  copyFileSync(voice, narration);
  const timing = join(dir, 'timing.json');
  write(timing, { narrationSha256: sha(narration), revision: 'r1', durationSeconds: 12, lockedBy: 'owner' });
  const m = { version: 1, owner: 'owner', revision: 'r1', worker: 'fixture-worker',
    phase, outputDir: out, narration: ref(narration), timing: ref(timing) };
  const call = (cmd, ...args) => run(process.execPath, [cli, cmd, manifest, ...args]);
  const save = () => write(manifest, m);
  save();
  ok(call('probe'));
  const probePath = join(out, '.film-worker-probe.json');
  const executionReview = join(dir, 'worker-review.json');
  write(executionReview, { probeSha256: sha(probePath), reviewedBy: 'test-parent',
    notes: 'Fixture parent inspected the actual child execution/write receipt.' });
  m.executionReview = ref(executionReview);
  const pilot = join(out, 'pilot.mp4'), captions = join(dir, 'captions.srt');
  copyFileSync(seed, pilot);
  writeFileSync(captions, '1\n00:00:00,000 --> 00:00:12,000\nSynthetic test media, not a human-approved film.\n');
  m.pilot = ref(pilot);
  m.captions = ref(captions);
  const pilotReview = join(dir, 'pilot-review.json');
  write(pilotReview, { pilotSha256: sha(pilot), narrationSha256: sha(narration),
    timingSha256: sha(timing), captionsSha256: sha(captions), revision: 'r1', reviewedBy: 'test-fixture',
    captions: 'Synthetic fixture review; semantic correctness is not asserted.',
    privacy: 'Synthetic color source.', legibility: 'Fixture only, not aesthetic evidence.',
    voice: 'Synthetic tone substitutes for voice solely for structural testing.' });
  m.pilotReview = ref(pilotReview);
  save();
  const statePath = join(out, '.film-preflight-state.json');
  const reconcile = (key, id, status = 'completed') => {
    const receipt = join(dir, `reconcile-${key}.json`);
    write(receipt, { key, id, status, reviewedBy: 'test-operator', notes: 'Synthetic service evidence; no network.' });
    return call('reconcile', key, receipt);
  };
  return { m, dir, out, manifest, call, save, probePath, statePath, reconcile };
}

test('real CLI child probe, write receipt, production pilot and prototype without pilot', () => {
  const f = fixture();
  const p = read(f.probePath);
  assert.ok(p.pid > 0);
  assert.match(p.node, /^v\d/);
  assert.equal(sha(p.write.path), p.write.sha256);
  ok(f.call('check'));
  ok(f.call('check', join(f.out, 'next.mp4')));
  const p0 = fixture('prototype');
  delete p0.m.pilot; delete p0.m.pilotReview; delete p0.m.captions; p0.save();
  ok(p0.call('check'));
});

test('rejects missing execution, uninspected receipts and stale revisions', () => {
  const f = fixture();
  unlinkSync(f.probePath);
  bad(f.call('check'), /ENOENT/);
  const g = fixture();
  delete g.m.executionReview; g.save();
  bad(g.call('check'), /missing content hash/);
  const h = fixture();
  h.m.revision = 'r2'; h.save();
  bad(h.call('check'), /timing must be fixed/);
  const i = fixture();
  const p = read(i.probePath); p.worker = 'author-only'; write(i.probePath, p);
  bad(i.call('check'), /execution evidence/);
});

test('rejects relative, missing, aliased and wrong authoritative paths', () => {
  const f = fixture();
  bad(run(process.execPath, [cli, 'check', 'manifest.json']), /absolute/);
  bad(f.call('check', 'relative.mp4'), /absolute/);
  bad(f.call('check', join(f.dir, 'wrong.mp4')), /outputDir/);
  const link = join(f.out, 'linked.mp4');
  symlinkSync(f.m.pilot.path, link);
  bad(f.call('check', link), /symlink/);
  const dangling = join(f.out, 'dangling.mp4');
  symlinkSync(join(f.dir, 'outside-missing.mp4'), dangling);
  bad(f.call('check', dangling), /symlink/);
  f.m.narration.path = 'relative.wav'; f.save();
  bad(f.call('check'), /absolute/);
  const g = fixture();
  g.m.outputDir = g.dir; g.save();
  bad(g.call('check'), /ENOENT/);
  const h = fixture();
  h.m.narration.path = join(h.dir, 'missing.wav'); h.save();
  bad(h.call('check'), /ENOENT/);
});

test('requires real 10-15s MP4 with both video and audio, plus written reviews', () => {
  for (const source of [noAudio, noVideo]) {
    const f = fixture();
    copyFileSync(source, f.m.pilot.path); f.m.pilot = ref(f.m.pilot.path); f.save();
    bad(f.call('check'), /missing audio|missing video/);
  }
  const f = fixture();
  delete f.m.pilot; f.save();
  bad(f.call('check'), /pilot/);
  const g = fixture();
  const review = read(g.m.pilotReview.path); review.legibility = true;
  write(g.m.pilotReview.path, review); g.m.pilotReview = ref(g.m.pilotReview.path); g.save();
  bad(g.call('check'), /written legibility/);
  for (const seconds of ['9', '16']) {
    const h = fixture();
    ffmpeg('-stream_loop', '-1', '-i', seed, '-t', seconds, '-c', 'copy', h.m.pilot.path);
    h.m.pilot = ref(h.m.pilot.path); h.save();
    bad(h.call('check'), /10-15 seconds/);
  }
});

test('content changes invalidate narration timing, probe and pilot/caption review links', () => {
  const f = fixture();
  appendFileSync(f.m.narration.path, 'changed');
  bad(f.call('check'), /stale content hash/);
  f.m.narration = ref(f.m.narration.path); f.save();
  bad(f.call('check'), /timing must be fixed/);
  const timing = read(f.m.timing.path); timing.narrationSha256 = f.m.narration.sha256;
  write(f.m.timing.path, timing); f.m.timing = ref(f.m.timing.path); f.save();
  bad(f.call('check'), /stale execution evidence/);
  for (const field of ['pilot', 'captions']) {
    const g = fixture(); appendFileSync(g.m[field].path, '\nchanged');
    bad(g.call('check'), /stale content hash/);
    g.m[field] = ref(g.m[field].path); g.save();
    bad(g.call('check'), /review mismatch/);
  }
});

test('two no-progress observations stop expansion; old hashes cannot reset it', () => {
  const f = fixture();
  ok(f.call('observe', f.m.pilot.path));
  ok(f.call('observe', '-'));
  ok(f.call('check'));
  ok(f.call('observe', f.m.pilot.path));
  bad(f.call('check'), /two no-progress/);
  ok(f.call('probe'));
  assert.equal(read(f.statePath).noProgress, 2);
  ok(f.call('observe', f.m.pilot.path));
  assert.equal(read(f.statePath).noProgress, 3);
});

test('durable uncertain/accepted jobs resume; duplicates and third prototype attempt block', () => {
  const f = fixture('prototype');
  ok(f.call('reserve', 'first', '{"prompt":"one"}'));
  assert.equal(read(f.statePath).jobs[0].status, 'uncertain');
  bad(f.call('check'), /unresolved job/);
  bad(f.call('reserve', 'second', '{"prompt":"two"}'), /unresolved job/);
  ok(f.call('accept', 'first', 'remote-1'));
  bad(f.call('check'), /unresolved job/);
  bad(f.reconcile('first', 'wrong-id'), /ID mismatch/);
  ok(f.reconcile('first', 'remote-1'));
  bad(f.call('reserve', 'first', '{"prompt":"changed"}'), /duplicate request/);
  bad(f.call('reserve', 'new-key', '{"prompt":"one"}'), /duplicate request/);
  ok(f.call('reserve', 'second', '{"prompt":"two"}'));
  bad(f.call('accept', 'second', 'remote-1'), /duplicate accepted/);
  ok(f.reconcile('second', undefined, 'rejected'));
  bad(f.call('reserve', 'third', '{"prompt":"three"}'), /two clips/);
  const s = read(f.statePath); s.jobs.push(s.jobs[0]); write(f.statePath, s);
  bad(f.call('check'), /duplicate jobs/);
});

test('missing-manifest adapter rejects create/shot/remix before auth/network; reads skip guard', () => {
  const env = { ...process.env };
  delete env.FILM_MANIFEST; delete env.FILM_REQUEST_KEY; delete env.AZURE_OPENAI_ENDPOINT;
  for (const [cmd, ...args] of [['create', 'x'], ['shot', 'x', '/unused.mp4'], ['remix', 'id', 'x']]) {
    const r = run('bash', [adapter, cmd, ...args], { env });
    bad(r, /new generation requires FILM_MANIFEST/);
    assert.doesNotMatch(r.stderr, /set AZURE_OPENAI_ENDPOINT|az:|curl:/);
  }
  for (const cmd of ['status', 'wait', 'get']) {
    const r = run('bash', [adapter, cmd, 'existing-id', '/unused.mp4'], { env });
    bad(r, /set AZURE_OPENAI_ENDPOINT/);
    assert.doesNotMatch(r.stderr, /FILM_MANIFEST|preflight/);
  }
  const f = fixture();
  ok(f.call('reserve', 'pending', '{"prompt":"pending"}'));
  bad(run('bash', [adapter, 'create', 'x'], { env: { ...env,
    FILM_MANIFEST: f.manifest, FILM_REQUEST_KEY: 'next' } }), /unresolved job/);
  assert.ok(existsSync(f.statePath));
});

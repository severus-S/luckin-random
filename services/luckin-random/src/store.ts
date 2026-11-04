import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { defaults, type Configuration, type Intent, type Job } from './domain.js';

export class Store {
  db: DatabaseSync;
  constructor(path: string, private key: Buffer) {
    if (key.length !== 32) throw new Error('ENCRYPTION_KEY must be 32 bytes');
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this.db.exec('PRAGMA busy_timeout=5000;');
    const directory=new URL('../../migrations/', import.meta.url);
    const files=readdirSync(directory).filter(f=>/^\d{3}_.+\.sql$/.test(f)).sort();
    this.db.exec('CREATE TABLE IF NOT EXISTS migrations(version INTEGER PRIMARY KEY)');
    const version=(this.db.prepare('SELECT COALESCE(MAX(version),0) AS v FROM migrations').get() as {v:number}).v;
    if(version>Math.max(...files.map(f=>Number(f.slice(0,3))))){this.db.close();throw new Error('Database is newer than this server; migration required');}
    for(const f of files)if(Number(f.slice(0,3))>version)this.db.exec(readFileSync(new URL(f,directory),'utf8'));
    this.db.prepare('INSERT OR IGNORE INTO config VALUES(1,?)').run(JSON.stringify(defaults()));
    // A process crash may have interrupted a mutation. Never send it again.
    for (const i of this.intents()) if (i.state === 'creating' || i.state === 'validating') {
      i.state = i.state === 'creating' ? 'unknown' : 'failed';
      i.reason = i.state === 'unknown' ? '服务重启时订单创建结果不明；禁止重试，请核对瑞幸官方订单' : '服务重启中止了只读校验，可重新发起'; this.save(i);
    }
  }
  config(): Configuration { return JSON.parse((this.db.prepare('SELECT json FROM config WHERE id=1').get() as { json: string }).json); }
  setConfig(c: Configuration) { this.db.prepare('UPDATE config SET json=? WHERE id=1').run(JSON.stringify(c)); }
  intents(): Intent[] { return (this.db.prepare('SELECT json FROM intents ORDER BY created_at DESC,rowid DESC').all() as { json: string }[]).map(r => JSON.parse(r.json)); }
  get(id: string): Intent | undefined { const r = this.db.prepare('SELECT json FROM intents WHERE id=?').get(id) as { json: string } | undefined; return r && JSON.parse(r.json); }
  fingerprint(id: string): string | undefined { return (this.db.prepare('SELECT fingerprint FROM intents WHERE id=?').get(id) as { fingerprint: string } | undefined)?.fingerprint; }
  insert(i: Intent, fingerprint: string) { this.db.prepare('INSERT INTO intents VALUES(?,?,?,?,?)').run(i.id, fingerprint, i.state, i.createdAt, JSON.stringify(i)); this.event(i); }
  save(i: Intent) { this.db.prepare('UPDATE intents SET state=?,json=? WHERE id=?').run(i.state, JSON.stringify(i), i.id); this.event(i); }
  event(i: Intent) { this.db.prepare('INSERT INTO events(intent_id,at,state,detail) VALUES(?,?,?,?)').run(i.id, new Date().toISOString(), i.state, i.reason ?? ''); }
  events() { return this.db.prepare('SELECT seq,intent_id AS intentId,at,state,detail FROM events ORDER BY seq DESC LIMIT 500').all(); }
  jobs(): Job[] { return (this.db.prepare('SELECT json FROM jobs ORDER BY id').all() as { json: string }[]).map(r => JSON.parse(r.json)); }
  job(j: Job) { this.db.prepare('INSERT INTO jobs VALUES(?,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json').run(j.id, JSON.stringify(j)); }
  deleteJob(id: string) { this.db.prepare('DELETE FROM jobs WHERE id=?').run(id); }
  claim(job: string, slot: string, intent: string): boolean { return this.db.prepare('INSERT OR IGNORE INTO job_runs VALUES(?,?,?)').run(job, slot, intent).changes === 1; }
  runs() { return this.db.prepare('SELECT job_id AS jobId,slot,intent_id AS intentId FROM job_runs ORDER BY slot DESC LIMIT 300').all(); }
  notify(message: string) { this.db.prepare('INSERT INTO outbox(at,message) VALUES(?,?)').run(new Date().toISOString(), message); }
  notifications() { return this.db.prepare('SELECT id,at,message,read FROM outbox ORDER BY id DESC LIMIT 100').all(); }
  secret(name: string, text?: string) {
    if (text !== undefined) {
      const iv = randomBytes(12), c = createCipheriv('aes-256-gcm', this.key, iv); c.setAAD(Buffer.from(name));
      const data = Buffer.concat([c.update(text, 'utf8'), c.final()]);
      this.db.prepare('INSERT INTO secrets VALUES(?,?) ON CONFLICT(name) DO UPDATE SET encrypted=excluded.encrypted').run(name, Buffer.concat([iv,c.getAuthTag(),data]).toString('base64')); return;
    }
    const r = this.db.prepare('SELECT encrypted FROM secrets WHERE name=?').get(name) as { encrypted: string } | undefined;
    if (!r) return;
    const b = Buffer.from(r.encrypted, 'base64'), d = createDecipheriv('aes-256-gcm', this.key, b.subarray(0,12));
    d.setAAD(Buffer.from(name)); d.setAuthTag(b.subarray(12,28)); return Buffer.concat([d.update(b.subarray(28)),d.final()]).toString('utf8');
  }
  revoke() { this.db.prepare("DELETE FROM secrets WHERE name='mcp'").run(); const c = this.config(); c.realOrdersEnabled=false; c.emergencyStop=true; this.setConfig(c); }
  close() { this.db.close(); }
}

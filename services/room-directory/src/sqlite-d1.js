import { DatabaseSync } from "node:sqlite";

export class SqliteD1 {
  constructor(path = ":memory:") {
    this.db = new DatabaseSync(path);
    this.db.exec("PRAGMA foreign_keys = ON");
  }
  prepare(sql) {
    const db = this.db;
    let params = {};
    const statement = {
      bind(...args) { params = Object.fromEntries(args.map((v, i) => [`p${i + 1}`, v])); return statement; },
      async first() { return db.prepare(sql.replace(/\?(\d+)/g, ":p$1")).get(params) || null; },
      async all() { return { results: db.prepare(sql.replace(/\?(\d+)/g, ":p$1")).all(params) }; },
      async run() { return db.prepare(sql.replace(/\?(\d+)/g, ":p$1")).run(params); }
    };
    return statement;
  }
  async batch(statements) {
    this.db.exec("BEGIN");
    try { const values = []; for (const s of statements) values.push(await s.run()); this.db.exec("COMMIT"); return values; }
    catch (e) { this.db.exec("ROLLBACK"); throw e; }
  }
}

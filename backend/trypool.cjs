const { Client } = require("pg");

const ref = process.env.REF;
const pw = process.env.PW;

async function tryRegion(region, user) {
  return new Promise((resolve) => {
    const c = new Client({
      host: `aws-0-${region}.pooler.supabase.com`,
      port: 6543,
      user,
      password: pw,
      database: "postgres",
      ssl: { rejectUnauthorized: false },
      connectionTimeoutMillis: 8000,
    });
    c.connect()
      .then(async () => {
        try {
          await c.query("select 1");
          resolve("OK region=" + region + " user=" + user);
        } catch (e) {
          resolve("QUERY ERR region=" + region + ": " + (e.code || e.message));
        } finally {
          c.end().catch(() => {});
        }
      })
      .catch((e) => {
        resolve(
          "CONNECT ERR region=" + region + " user=" + user + ": " + (e.code || (e.message || "").split("\n")[0])
        );
      });
  });
}

const regions = ["eu-west-1","eu-west-2","eu-central-1","eu-north-1","us-east-1","us-east-2","us-west-1","us-west-2","ap-south-1","ap-southeast-1","ap-northeast-1"];
const users = [`postgres.${ref}`];

async function main() {
  for (const region of regions) {
    for (const user of users) {
      const res = await tryRegion(region, user);
      console.log(res);
      if (res.startsWith("OK ")) process.exit(0);
    }
  }
  process.exit(1);
}
main();
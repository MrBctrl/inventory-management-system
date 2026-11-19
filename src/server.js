import app from './app.js';
import { env } from './config/env.js';
import { connectPostgres, postgresPool } from './config/postgres.js';
import { connectMongo, mongoClient } from './config/mongodb.js';

let server;
let shuttingDown = false;

async function startServer() {
  // Fail fast: do not report the API as ready unless both required databases connect.
  await connectPostgres();
  await connectMongo();

  server = app.listen(env.port, () => {
    console.log(`Inventory Management API listening on http://localhost:${env.port}`);
  });
}

async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`${signal} received. Closing server and database connections...`);

  if (server) {
    await new Promise((resolve) => server.close(resolve));
  }

  await Promise.allSettled([
    postgresPool.end(),
    mongoClient.close()
  ]);

  process.exit(0);
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));

startServer().catch(async (error) => {
  console.error('Failed to start the API:', error.message);
  await Promise.allSettled([
    postgresPool.end(),
    mongoClient.close()
  ]);
  process.exit(1);
});

import pg from 'pg';
import { env } from './env.js';

const { Pool } = pg;

export const postgresPool = new Pool({
  connectionString: env.databaseUrl,
  ssl: env.databaseSsl ? { rejectUnauthorized: true } : false,
  max: 10,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000
});

postgresPool.on('error', (error) => {
  console.error('Unexpected PostgreSQL pool error:', error.message);
});

export async function connectPostgres() {
  const result = await postgresPool.query('SELECT NOW() AS connected_at');
  console.log('PostgreSQL connected:', result.rows[0].connected_at);
}

import { postgresPool } from '../config/postgres.js';
import { getMongoDatabase } from '../config/mongodb.js';

export async function getHealth(_req, res, next) {
  try {
    const checks = {
      api: 'ok',
      postgres: 'unknown',
      mongodb: 'unknown'
    };

    try {
      await postgresPool.query('SELECT 1');
      checks.postgres = 'ok';
    } catch {
      checks.postgres = 'error';
    }

    try {
      await getMongoDatabase().command({ ping: 1 });
      checks.mongodb = 'ok';
    } catch {
      checks.mongodb = 'error';
    }

    const healthy = checks.postgres === 'ok' && checks.mongodb === 'ok';
    return res.status(healthy ? 200 : 503).json({
      success: healthy,
      message: healthy ? 'API and databases are healthy.' : 'A database health check failed.',
      checks,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    return next(error);
  }
}

import jwt from 'jsonwebtoken';
import { postgresPool } from '../config/postgres.js';
import { env } from '../config/env.js';
import { AppError } from '../utils/app-error.js';

export async function authenticate(req, _res, next) {
  try {
    const authorization = req.headers.authorization;
    if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) {
      throw new AppError('Authentication is required. Provide a Bearer access token.', 401);
    }

    const token = authorization.slice('Bearer '.length).trim();
    if (!token) {
      throw new AppError('Authentication is required. Provide a Bearer access token.', 401);
    }

    let payload;
    try {
      payload = jwt.verify(token, env.jwtSecret, {
        algorithms: ['HS256'],
        issuer: 'inventory-management-api',
        audience: 'inventory-management-client'
      });
    } catch {
      throw new AppError('Your access token is invalid or expired. Please log in again.', 401);
    }

    if (!payload || typeof payload !== 'object' || !payload.sub || !payload.businessId) {
      throw new AppError('Your access token is invalid. Please log in again.', 401);
    }

    // Recheck membership and account status on every protected request.
    // This means disabling a user or removing business access takes effect immediately.
    const result = await postgresPool.query(
      `SELECT
         u.id AS user_id,
         u.full_name,
         u.email,
         bm.business_id,
         bm.role,
         b.name AS business_name,
         b.slug AS business_slug,
         b.currency,
         b.timezone
       FROM users u
       JOIN business_members bm ON bm.user_id = u.id
       JOIN businesses b ON b.id = bm.business_id
       WHERE u.id = $1
         AND bm.business_id = $2
         AND u.status = 'active'
         AND bm.status = 'active'
         AND b.status = 'active'
       LIMIT 1`,
      [payload.sub, payload.businessId]
    );

    if (result.rowCount === 0) {
      throw new AppError('Your account or business access is no longer active.', 401);
    }

    const row = result.rows[0];
    req.auth = {
      user: {
        id: row.user_id,
        fullName: row.full_name,
        email: row.email
      },
      business: {
        id: row.business_id,
        name: row.business_name,
        slug: row.business_slug,
        currency: row.currency,
        timezone: row.timezone
      },
      role: row.role
    };

    return next();
  } catch (error) {
    return next(error);
  }
}

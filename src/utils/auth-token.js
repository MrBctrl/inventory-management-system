import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

export function createAccessToken({ userId, businessId, role }) {
  return jwt.sign(
    { businessId, role },
    env.jwtSecret,
    {
      subject: userId,
      expiresIn: env.jwtExpiresIn,
      issuer: 'inventory-management-api',
      audience: 'inventory-management-client',
      algorithm: 'HS256'
    }
  );
}

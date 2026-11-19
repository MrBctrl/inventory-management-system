import { randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { postgresPool } from '../config/postgres.js';
import { env } from '../config/env.js';
import { AppError } from '../utils/app-error.js';
import { createAccessToken } from '../utils/auth-token.js';
import { validateLoginInput, validateRegisterInput } from '../validators/auth.validator.js';

function createBusinessSlug(name) {
  const base = name
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80)
    .replace(/-+$/g, '') || 'business';
  return `${base}-${randomBytes(8).toString('hex')}`;
}

export async function registerBusinessOwner(body) {
  const input = validateRegisterInput(body);
  const passwordHash = await bcrypt.hash(input.password, 12);
  const client = await postgresPool.connect();

  try {
    await client.query('BEGIN');
    const existingUser = await client.query(
      'SELECT id FROM users WHERE LOWER(email) = $1 LIMIT 1',
      [input.email]
    );
    if (existingUser.rowCount > 0) {
      throw new AppError('An account with this email address already exists.', 409);
    }

    const businessResult = await client.query(
      `INSERT INTO businesses (name, slug, business_type)
       VALUES ($1, $2, $3)
       RETURNING id, name, slug, currency, timezone, created_at`,
      [input.businessName, createBusinessSlug(input.businessName), 'general']
    );
    const business = businessResult.rows[0];

    const userResult = await client.query(
      `INSERT INTO users (full_name, email, password_hash)
       VALUES ($1, $2, $3)
       RETURNING id, full_name, email, created_at`,
      [input.fullName, input.email, passwordHash]
    );
    const user = userResult.rows[0];

    await client.query(
      `INSERT INTO business_members (business_id, user_id, role, status, joined_at)
       VALUES ($1, $2, 'owner', 'active', NOW())`,
      [business.id, user.id]
    );

    await client.query(
      `INSERT INTO outbox_events
         (business_id, aggregate_type, aggregate_id, event_type, payload)
       VALUES ($1, 'business', $1, 'business.owner_registered', $2::jsonb)`,
      [business.id, JSON.stringify({
        businessId: business.id,
        ownerId: user.id,
        ownerEmail: user.email
      })]
    );

    const accessToken = createAccessToken({
      userId: user.id,
      businessId: business.id,
      role: 'owner'
    });

    await client.query('COMMIT');

    return {
      user: {
        id: user.id,
        fullName: user.full_name,
        email: user.email,
        role: 'owner'
      },
      business: {
        id: business.id,
        name: business.name,
        slug: business.slug,
        currency: business.currency,
        timezone: business.timezone
      },
      accessToken,
      tokenType: 'Bearer',
      expiresIn: env.jwtExpiresIn
    };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (rollbackError) {
      console.error('Registration rollback failed:', rollbackError.message);
    }
    if (error.code === '23505' && error.constraint === 'users_email_unique_ci') {
      throw new AppError('An account with this email address already exists.', 409);
    }
    throw error;
  } finally {
    client.release();
  }
}

export async function loginUser(body) {
  const input = validateLoginInput(body);

  const userResult = await postgresPool.query(
    `SELECT id, full_name, email, password_hash, status
     FROM users
     WHERE LOWER(email) = $1
     LIMIT 1`,
    [input.email]
  );

  const user = userResult.rows[0];
  // Keep the failure message generic so the endpoint does not reveal whether an email exists.
  const passwordMatches = user
    ? await bcrypt.compare(input.password, user.password_hash)
    : false;

  if (!user || !passwordMatches || user.status !== 'active') {
    throw new AppError('Invalid email or password.', 401);
  }

  const membershipsResult = await postgresPool.query(
    `SELECT
       bm.business_id,
       bm.role,
       b.name AS business_name,
       b.slug AS business_slug,
       b.currency,
       b.timezone
     FROM business_members bm
     JOIN businesses b ON b.id = bm.business_id
     WHERE bm.user_id = $1
       AND bm.status = 'active'
       AND b.status = 'active'
     ORDER BY bm.created_at ASC`,
    [user.id]
  );

  const memberships = membershipsResult.rows;
  if (memberships.length === 0) {
    throw new AppError('This account does not have an active business membership.', 403);
  }

  const selectedMembership = input.businessId
    ? memberships.find((membership) => membership.business_id === input.businessId)
    : memberships[0];

  if (!selectedMembership) {
    throw new AppError('You do not have access to the selected business.', 403);
  }

  await postgresPool.query(
    'UPDATE users SET last_login_at = NOW() WHERE id = $1',
    [user.id]
  );

  const accessToken = createAccessToken({
    userId: user.id,
    businessId: selectedMembership.business_id,
    role: selectedMembership.role
  });

  return {
    user: {
      id: user.id,
      fullName: user.full_name,
      email: user.email
    },
    business: {
      id: selectedMembership.business_id,
      name: selectedMembership.business_name,
      slug: selectedMembership.business_slug,
      currency: selectedMembership.currency,
      timezone: selectedMembership.timezone,
      role: selectedMembership.role
    },
    availableBusinesses: memberships.map((membership) => ({
      id: membership.business_id,
      name: membership.business_name,
      role: membership.role
    })),
    accessToken,
    tokenType: 'Bearer',
    expiresIn: env.jwtExpiresIn
  };
}

export async function getCurrentUser(auth) {
  return auth;
}

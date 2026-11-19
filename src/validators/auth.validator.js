import { AppError } from '../utils/app-error.js';

export function validateRegisterInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError('A JSON request body is required.', 400);
  }

  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  const businessName = typeof body.businessName === 'string' ? body.businessName.trim() : '';

  if (fullName.length < 2 || fullName.length > 150) {
    throw new AppError('Full name must be between 2 and 150 characters.', 400);
  }
  if (email.length > 255 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new AppError('A valid email address is required.', 400);
  }
  if (password.length < 8 || Buffer.byteLength(password, 'utf8') > 72) {
    throw new AppError('Password must be at least 8 characters and no more than 72 bytes.', 400);
  }
  if (businessName.length < 2 || businessName.length > 150) {
    throw new AppError('Business name must be between 2 and 150 characters.', 400);
  }

  return { fullName, email, password, businessName };
}

export function validateLoginInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError('A JSON request body is required.', 400);
  }

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  const businessId = body.businessId === undefined ? null : body.businessId;

  if (email.length > 255 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new AppError('A valid email address is required.', 400);
  }
  if (!password || Buffer.byteLength(password, 'utf8') > 72) {
    throw new AppError('Password is required and must not exceed 72 bytes.', 400);
  }
  if (businessId !== null && (typeof businessId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(businessId))) {
    throw new AppError('businessId must be a valid UUID.', 400);
  }

  return { email, password, businessId };
}

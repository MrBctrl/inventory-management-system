import { getCurrentUser, loginUser, registerBusinessOwner } from '../services/auth.service.js';

export async function register(req, res, next) {
  try {
    const result = await registerBusinessOwner(req.body);
    return res.status(201).json({
      success: true,
      message: 'Business account created successfully.',
      data: result
    });
  } catch (error) {
    return next(error);
  }
}

export async function login(req, res, next) {
  try {
    const result = await loginUser(req.body);
    return res.status(200).json({
      success: true,
      message: 'Login successful.',
      data: result
    });
  } catch (error) {
    return next(error);
  }
}

export async function me(req, res, next) {
  try {
    const result = await getCurrentUser(req.auth);
    return res.status(200).json({
      success: true,
      message: 'Authenticated user retrieved successfully.',
      data: result
    });
  } catch (error) {
    return next(error);
  }
}

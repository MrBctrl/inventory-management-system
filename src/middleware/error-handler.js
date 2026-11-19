export function errorHandler(error, _req, res, _next) {
  console.error(error);

  const statusCode = Number.isInteger(error.statusCode) ? error.statusCode : 500;
  const message = statusCode === 500 && process.env.NODE_ENV === 'production'
    ? 'Internal server error.'
    : error.message;

  return res.status(statusCode).json({
    success: false,
    message
  });
}

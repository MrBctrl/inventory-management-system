import { MongoClient } from 'mongodb';
import { env } from './env.js';

export const mongoClient = new MongoClient(env.mongoUri, {
  serverSelectionTimeoutMS: 5_000
});

let database;

export async function connectMongo() {
  await mongoClient.connect();
  database = mongoClient.db(env.mongoDbName);
  await database.command({ ping: 1 });
  console.log(`MongoDB connected: ${env.mongoDbName}`);
  return database;
}

export function getMongoDatabase() {
  if (!database) {
    throw new Error('MongoDB has not been connected.');
  }
  return database;
}

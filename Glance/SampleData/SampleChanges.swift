//
//  SampleChanges.swift
//  Glance
//

import Foundation

extension SampleData {
    static let rateLimitChanges: [ChangedFile] = [
        ChangedFile(
            diff: FileDiff("src/middleware/rateLimit.ts", .added, hunks: [
                RawHunk(oldStart: 0, newStart: 1, lines: [
                    "+import type { Request, Response, NextFunction } from 'express';",
                    "+",
                    "+type Options = { windowMs: number; max: number };",
                    "+type Bucket = { count: number; resetAt: number };",
                    "+",
                    "+const buckets = new Map<string, Bucket>();",
                    "+",
                    "+export function rateLimit({ windowMs, max }: Options) {",
                    "+  return (req: Request, res: Response, next: NextFunction) => {",
                    "+    const key = req.ip ?? 'unknown';",
                    "+    const now = Date.now();",
                    "+    const bucket = buckets.get(key);",
                    "+",
                    "+    if (!bucket || bucket.resetAt <= now) {",
                    "+      buckets.set(key, { count: 1, resetAt: now + windowMs });",
                    "+      return next();",
                    "+    }",
                    "+",
                    "+    if (bucket.count >= max) {",
                    "+      const retry = Math.ceil((bucket.resetAt - now) / 1000);",
                    "+      res.setHeader('Retry-After', String(retry));",
                    "+      return res.status(429).json({ error: 'Too many requests' });",
                    "+    }",
                    "+",
                    "+    bucket.count += 1;",
                    "+    next();",
                    "+  };",
                    "+}",
                ]),
            ]),
            agentEditedAgo: "4s",
            isStaged: true
        ),
        ChangedFile(
            diff: FileDiff("src/server.ts", .modified, hunks: [
                RawHunk(oldStart: 1, newStart: 1, lines: [
                    " import express from 'express';",
                    " import { env } from './config/env';",
                    "-import { throttle } from './legacy/throttle';",
                    "+import { rateLimit } from './middleware/rateLimit';",
                    " import { checkoutRouter } from './routes/checkout';",
                    " ",
                    " const app = express();",
                    " app.use(express.json());",
                    "-app.use(throttle(100));",
                    "+app.use(rateLimit({",
                    "+  windowMs: env.RATE_LIMIT_WINDOW_MS,",
                    "+  max: env.RATE_LIMIT_MAX,",
                    "+}));",
                    " app.use('/checkout', checkoutRouter);",
                ]),
            ]),
            isStaged: true,
            isViewed: true
        ),
        ChangedFile(
            diff: FileDiff("src/config/env.ts", .modified, hunks: [
                RawHunk(oldStart: 4, newStart: 4, context: "export const env = {", lines: [
                    "   PORT: Number(process.env.PORT ?? 3000),",
                    "   DATABASE_URL: required('DATABASE_URL'),",
                    "-  THROTTLE_PER_MIN: Number(process.env.THROTTLE_PER_MIN ?? 100),",
                    "+  RATE_LIMIT_WINDOW_MS: Number(",
                    "+    process.env.RATE_LIMIT_WINDOW_MS ?? 60_000,",
                    "+  ),",
                    "+  RATE_LIMIT_MAX: Number(process.env.RATE_LIMIT_MAX ?? 100),",
                    "   STRIPE_KEY: required('STRIPE_KEY'),",
                    " };",
                ]),
            ]),
            isStaged: true
        ),
        ChangedFile(
            diff: FileDiff("src/routes/checkout.ts", .modified, hunks: [
                RawHunk(oldStart: 1, newStart: 1, lines: [
                    " import { Router } from 'express';",
                    "+import { rateLimit } from '../middleware/rateLimit';",
                    " import { createOrder } from '../services/orders';",
                    " import { requireAuth } from '../middleware/auth';",
                ]),
                RawHunk(oldStart: 18, newStart: 19, context: "const checkoutRouter = Router();", lines: [
                    " checkoutRouter.use(requireAuth);",
                    " ",
                    "-checkoutRouter.post('/', async (req, res) => {",
                    "-  const order = await createOrder(req.body);",
                    "-  res.json(order);",
                    "-});",
                    "+checkoutRouter.post(",
                    "+  '/',",
                    "+  rateLimit({ windowMs: 60_000, max: 10 }),",
                    "+  async (req, res) => {",
                    "+    const order = await createOrder(req.body);",
                    "+    res.status(201).json(order);",
                    "+  },",
                    "+);",
                    " ",
                    " export { checkoutRouter };",
                ]),
            ]),
            isStaged: true
        ),
        ChangedFile(
            diff: FileDiff("test/rateLimit.test.ts", .added, hunks: [
                RawHunk(oldStart: 0, newStart: 1, lines: [
                    "+import request from 'supertest';",
                    "+import express from 'express';",
                    "+import { rateLimit } from '../src/middleware/rateLimit';",
                    "+",
                    "+const app = express();",
                    "+app.use(rateLimit({ windowMs: 1000, max: 2 }));",
                    "+app.get('/', (_req, res) => res.send('ok'));",
                    "+",
                    "+test('blocks the third request in a window', async () => {",
                    "+  await request(app).get('/').expect(200);",
                    "+  await request(app).get('/').expect(200);",
                    "+  const res = await request(app).get('/').expect(429);",
                    "+  expect(res.headers['retry-after']).toBeDefined();",
                    "+});",
                ]),
            ]),
            agentEditedAgo: "11s"
        ),
        ChangedFile(
            diff: FileDiff("package.json", .modified, hunks: [
                RawHunk(oldStart: 14, newStart: 14, context: #""devDependencies": {"#, lines: [
                    #"     "jest": "^29.7.0","#,
                    #"+    "supertest": "^7.0.0","#,
                    #"+    "@types/supertest": "^6.0.2","#,
                    #"     "ts-jest": "^29.1.2","#,
                    #"     "typescript": "^5.6.3""#,
                ]),
            ]),
            isStaged: true,
            isViewed: true
        ),
        ChangedFile(
            diff: FileDiff("src/legacy/throttle.js", .deleted, hunks: [
                RawHunk(oldStart: 1, newStart: 0, lines: [
                    "-// Deprecated: replaced by middleware/rateLimit",
                    "-module.exports.throttle = function (perMin) {",
                    "-  const hits = {};",
                    "-  return function (req, res, next) {",
                    "-    const k = req.ip;",
                    "-    hits[k] = (hits[k] || 0) + 1;",
                    "-    if (hits[k] > perMin) return res.sendStatus(429);",
                    "-    next();",
                    "-  };",
                    "-};",
                ]),
            ]),
            isStaged: true
        ),
    ]

    static let checkoutTestsChanges: [ChangedFile] = [
        ChangedFile(
            diff: FileDiff("test/checkout.test.ts", .added, hunks: [
                RawHunk(oldStart: 0, newStart: 1, lines: [
                    "+import request from 'supertest';",
                    "+import { app } from '../src/server';",
                    "+import { cart } from './fixtures/cart';",
                    "+",
                    "+describe('POST /checkout', () => {",
                    "+  it('creates an order for a valid cart', async () => {",
                    "+    const res = await request(app).post('/checkout').send(cart);",
                    "+    expect(res.status).toBe(201);",
                    "+    expect(res.body.total).toBe(cart.total);",
                    "+  });",
                    "+",
                    "+  it('rejects an empty cart', async () => {",
                    "+    await request(app).post('/checkout').send({ items: [] }).expect(400);",
                    "+  });",
                    "+});",
                ]),
            ]),
            agentEditedAgo: "9s"
        ),
        ChangedFile(
            diff: FileDiff("test/fixtures/cart.ts", .added, hunks: [
                RawHunk(oldStart: 0, newStart: 1, lines: [
                    "+export const cart = {",
                    "+  items: [{ sku: 'TSHIRT-M', qty: 2, priceCents: 2_400 }],",
                    "+  subtotal: 4_800,",
                    "+  tax: 384,",
                    "+  total: 5_184,",
                    "+};",
                ]),
            ]),
            isStaged: true
        ),
        ChangedFile(
            diff: FileDiff("jest.config.js", .modified, hunks: [
                RawHunk(oldStart: 1, newStart: 1, lines: [
                    " module.exports = {",
                    "   preset: 'ts-jest',",
                    "   testEnvironment: 'node',",
                    "+  setupFiles: ['dotenv/config'],",
                    "+  testTimeout: 10_000,",
                    " };",
                ]),
            ])
        ),
    ]
}

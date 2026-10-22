//
//  SampleHistory.swift
//  Glance
//

import SwiftUI

extension SampleData {
    static let you = Author(name: "You", initial: "Y", color: Color(hex: 0x2563EB))
    static let maya = Author(name: "Maya Chen", initial: "M", color: Color(hex: 0xB9400B))
    static let arif = Author(name: "Arif Rahman", initial: "A", color: Color(hex: 0x0F766E))

    static let commits: [Commit] = [
        Commit(
            title: "Fix rounding in tax calculation",
            body: """
            Tax was rounded after converting to dollars, so totals could drift a cent from Stripe.
            Round half-to-even on integer cents instead, and cover exact halves in tests.
            """,
            author: you,
            isAgentCoAuthored: true,
            relativeTime: "18 min",
            date: "Today at 6:15 AM",
            sha: "4e1c9a2",
            isUnpushed: true,
            files: [
                FileDiff("src/services/tax.ts", .modified, hunks: [
                    RawHunk(oldStart: 8, newStart: 8, context: "import { TAX_RATES } from './rates';", lines: [
                        " export function calculateTax(subtotalCents: number, rate: number) {",
                        "-  const tax = subtotalCents * rate;",
                        "-  return Math.round(tax) / 100;",
                        "+  // Round half-to-even on integer cents to match Stripe's totals.",
                        "+  const raw = subtotalCents * rate;",
                        "+  return bankersRound(raw);",
                        " }",
                        "+",
                        "+function bankersRound(value: number): number {",
                        "+  const floor = Math.floor(value);",
                        "+  const diff = value - floor;",
                        "+  if (diff > 0.5) return floor + 1;",
                        "+  if (diff < 0.5) return floor;",
                        "+  return floor % 2 === 0 ? floor : floor + 1;",
                        "+}",
                        " ",
                        " export function formatTax(cents: number) {",
                    ]),
                ]),
                FileDiff("test/tax.test.ts", .modified, hunks: [
                    RawHunk(oldStart: 20, newStart: 20, context: "describe('calculateTax', () => {", lines: [
                        "   it('applies the rate to the subtotal', () => {",
                        "     expect(calculateTax(10_000, 0.08)).toBe(800);",
                        "   });",
                        "+",
                        "+  it('rounds exact halves to the even cent', () => {",
                        "+    expect(calculateTax(25, 0.1)).toBe(2);",
                        "+    expect(calculateTax(35, 0.1)).toBe(4);",
                        "+  });",
                        " });",
                    ]),
                ]),
            ]
        ),
        Commit(
            title: "Extract price helpers from checkout service",
            author: you,
            isAgentCoAuthored: true,
            relativeTime: "41 min",
            date: "Today at 5:52 AM",
            sha: "b7d03f5",
            isUnpushed: true,
            files: [
                FileDiff("src/services/price.ts", .added, additions: 44, deletions: 0),
                FileDiff("src/services/checkout.ts", .modified, additions: 14, deletions: 37),
            ]
        ),
        Commit(
            title: "Merge pull request #212 from fix/webhook-retry",
            author: maya,
            relativeTime: "Yesterday",
            date: "Yesterday at 4:10 PM",
            sha: "91aa6e0",
            startsRemoteHistory: true,
            files: []
        ),
        Commit(
            title: "Retry Stripe webhooks with exponential backoff",
            author: maya,
            relativeTime: "Yesterday",
            date: "Yesterday at 2:47 PM",
            sha: "2f4b8c1",
            files: [
                FileDiff("src/webhooks/stripe.ts", .modified, additions: 39, deletions: 12),
                FileDiff("src/lib/backoff.ts", .added, additions: 32, deletions: 0),
            ]
        ),
        Commit(
            title: "Bump stripe to 15.2.0",
            author: you,
            relativeTime: "2 days",
            date: "Monday at 11:03 AM",
            sha: "c6e7d19",
            files: [
                FileDiff("package.json", .modified, additions: 1, deletions: 1),
                FileDiff("package-lock.json", .modified, additions: 2, deletions: 2),
            ]
        ),
        Commit(
            title: "Release 2.4.0",
            author: you,
            relativeTime: "3 days",
            date: "Sunday at 9:30 PM",
            sha: "0d3b5a7",
            tag: "v2.4.0",
            files: [
                FileDiff("CHANGELOG.md", .modified, additions: 11, deletions: 0),
                FileDiff("package.json", .modified, additions: 1, deletions: 1),
            ]
        ),
        Commit(
            title: "Add order confirmation emails",
            author: arif,
            relativeTime: "4 days",
            date: "Saturday at 1:18 PM",
            sha: "8a91f2e",
            files: [
                FileDiff("src/emails/orderConfirmed.ts", .added, additions: 88, deletions: 0),
                FileDiff("src/services/orders.ts", .modified, additions: 8, deletions: 4),
            ]
        ),
    ]
}

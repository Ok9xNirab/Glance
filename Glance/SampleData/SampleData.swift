//
//  SampleData.swift
//  Glance
//

import Foundation

/// Static content for the design flow until Glance reads real repositories.
enum SampleData {
    static let repositoryName = "storefront-api"

    static let worktrees: [Worktree] = [
        Worktree(name: "storefront-api", branch: "main", path: "~/dev/storefront-api"),
        Worktree(
            name: "rate-limit",
            branch: "agent/rate-limit",
            path: "~/.worktrees/storefront-api/rate-limit",
            isAgentActive: true,
            aheadCount: 2,
            changes: rateLimitChanges
        ),
        Worktree(
            name: "checkout-tests",
            branch: "agent/checkout-tests",
            path: "~/.worktrees/storefront-api/checkout-tests",
            isAgentActive: true,
            changes: checkoutTestsChanges
        ),
        Worktree(name: "webhook-retry", branch: "fix/webhook-retry", path: "~/.worktrees/storefront-api/webhook-retry"),
    ]

    static let initialWorktreeID = "rate-limit"

    static let branches: [Branch] = [
        Branch(name: "release/2.4", lastUpdated: "3 days ago", remote: "origin", isRecent: true),
        Branch(name: "feat/gift-cards", lastUpdated: "1 week ago", remote: "origin", isRecent: true),
        Branch(name: "chore/deps", lastUpdated: "2 days ago", isRecent: true),
        Branch(name: "feat/checkout-coupons", lastUpdated: "5 days ago", remote: "origin"),
        Branch(name: "fix/checkout-currency", lastUpdated: "2 weeks ago"),
    ]
}

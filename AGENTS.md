# AGENTS.md

Project conventions for the Henriable Solidity codebase.

## If statements

- Never put a negated expression directly in an `if` condition.
- Compute the condition into a clearly named `bool` variable on the line before, then
  test that variable in the `if`.
- The variable name should read as the thing being tested; any negation lives in the
  assignment, not in the `if`.

```solidity
// Avoid
if (!isInvestmentStatus(inv.investmentId, allowedStatuses)) {
    revert HAssetHasNonPendingInvestments(_assetId);
}

// Prefer
bool investmentNotPending = !isInvestmentStatus(inv.investmentId, allowedStatuses);
if (investmentNotPending) {
    revert HAssetHasNonPendingInvestments(_assetId);
}
```

## Reverts

- Use custom errors (never `require` / `require` strings).
- Define every error, fully documented with `@notice`/`@param`, in the `Errors`
  editor-fold of `src/types/common.sol`, then use it in the contract.

## Organisation

- Group related declarations with `//<editor-fold desc="...">` sections
  (e.g. Imports, States, Constructor, Is..., Getters, Actions).
- Fully document public/external functions and state with NatSpec.

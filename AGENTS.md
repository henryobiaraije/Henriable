# AGENTS.md

Conventions and context for the Henriable Solidity codebase. Follow these every session.

## Source of truth and workflow

- The product/spec document is `Henriable.md`. Implement it one item at a time, in the
  order the user asks, and let the user review each piece before moving on.
- `Henriable.md` is an initial draft. Normalize snake_case to camelCase
  (e.g. `cost_price` -> `costPrice`), fix obvious typos, and treat the "Avoid" examples
  below as authoritative style. Surface deviations and ambiguities instead of guessing
  silently.
- Preserve the author's whitespace in `Henriable.md` exactly: keep the blank lines and the
  trailing two-space markdown line breaks they use for readability. When editing that
  document, never strip, trim, or reflow that spacing — a tool that rewrites the file must
  carry it over unchanged.

## Tooling

- Foundry project. Verify every change with `forge build` (must compile clean).
- OpenZeppelin Contracts is installed at `lib/openzeppelin-contracts` and remapped in
  `foundry.toml` as `@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/`.
  (Re)install with: `forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 --no-commit`.
- `forge-std` is remapped as `forge-std/=lib/forge-std/src/`.

## Layout

- `src/types/common.sol` — all structs, enums and errors, in editor-folds.
- `src/helpers/HHelper.sol` — inherited states, constructor, `is...` predicates, getters.
- `src/Henriable.sol` — `contract Henriable is HHelper`; the external `action...`
  functions live here.
- `HHelper is Ownable` (OpenZeppelin). The constructor sets `ownerUsdToken` and calls
  `Ownable(initialOwner)`. Do NOT declare an `_owner` state — Ownable owns it.

## If statements

- Never put a negated expression directly in an `if` condition.
- Compute the condition into a clearly named `bool` variable on the line before, then
  test that variable in the `if`.
- The variable name reads as the thing being tested; any negation lives in the
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

- Use custom errors only (never `require` / string messages).
- Define every error, fully documented with `@notice`/`@param`, in the `Errors`
  editor-fold of `src/types/common.sol`, then use it in the contract.
- Error names are prefixed `H` (e.g. `HAssetInvalidId`).
- Access control uses OpenZeppelin's `onlyOwner` (its `OwnableUnauthorizedAccount`
  error is fine to rely on).

## Organisation and documentation

- Group related declarations with `//<editor-fold desc="...">` sections, e.g.
  Imports, States (with sub-groups like `State: Owner`, `State: Assets`), Constructor,
  `Is...`, Getters, Actions.
- Fully document public/external functions and state with NatSpec (`@notice`, `@param`,
  `@return`); document every struct field.
- Naming: getters `getX`, actions `actionX`, internal predicates `isX` (in the `Is...`
  fold), constants `H...`.

## Types (`src/types/common.sol`)

- Every struct, enum and error lives here. Keep the editor-fold sections
  (Constants, Structs, Enums, Errors, Helper Functions).
- Use camelCase field names; document each field with NatSpec.
- Solidity structs cannot inherit: combine the source struct's fields into the target
  struct and demarcate the groups with editor-folds instead of splitting structs (e.g.
  `HInvestment` has `Fields: Admin Supplied` and `Fields: Contract Filled`).
- A struct containing a mapping cannot be an external/public parameter or return value.
  Pass its individual fields as external arguments instead (do not add a mapping-free
  input struct unless the user approves it).

## States and getters (`src/helpers/HHelper.sol`)

- Declare states `internal`; expose them via explicit `external view` getters grouped in
  the `Getters` fold. (Note: `external` getters cannot be called by name from inside the
  contract; internal code reads the state directly.)
- Lists are `Type[]` arrays plus a `mapping(id => index + 1)`, so `0` means "not
  registered" for an O(1) existence check and lookup. After `push`, store
  `array.length` (which equals `index + 1`).
- For writes, add an `internal view` accessor returning a storage reference that hides
  the index math, e.g. `getAssetStorage(id) returns (HAsset storage)`, so callers do
  `getAssetStorage(id).active = false;`. A `memory`-returning getter cannot be assigned
  to.
- Cascading admin actions (e.g. disabling an asset also disables its still-pending
  investments) mutate inherited internal state directly in the same transaction — no
  external call is involved.

## Deliberate decisions so far

- Currency is USDC; the token is stored as `IERC20 ownerUsdToken`.
- No events for now; the user will decide where events go when building the frontend.
- Asset ids are caller-supplied; uniqueness is enforced via the index mapping.
- A newly added asset is always forced `active = true`.

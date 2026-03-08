# JIT Model

## Deterministic Band Logic
For each swap-triggered JIT activation:
- `tickLower = tick - bandWidth`
- `tickUpper = tick + bandWidth`
- `token0ToUse = min(freeToken0, freeQuote, maxUsage)`
- `quoteToUse = token0ToUse`

The model is bounded and constant-time (no loops over users or positions).

## Inventory Rules
- Free and reserved balances are tracked separately.
- Add operation moves balances from free to reserved.
- Remove operation releases a deterministic fraction:
  - `released = reserved * releaseBps / 10_000`

## Example
Inputs:
- `freeToken0 = 100`
- `freeQuote = 60`
- `maxUsage = 25`

Result:
- `token0ToUse = quoteToUse = 25`
- post-add: free/reserved token0 = `75/25`, quote reserved +25.

If quote availability is lower than expected, token0 reservation is downscaled to keep symmetric usage.

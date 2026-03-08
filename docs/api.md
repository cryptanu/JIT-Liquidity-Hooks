# API

## JITLaunchHook
- `setPoolRegistration(PoolKey,bool)`
- `setIssuanceModule(IssuanceModule)`
- `beforeSwap/afterSwap` via `BaseHook`

## LaunchController
- `registerPool(PoolId,address,LaunchConfig)`
- `setPoolHook(PoolId,address)`
- `setAllowlist(PoolId,address,bool)`
- `queueConfigUpdate/executeConfigUpdate`
- `enforceSwapGuardrails`
- `consumeJitAction`
- `getGuardrails/getPhase/getLaunchConfig`

## JITLiquidityVault
- `depositToken0/withdrawToken0`
- `quoteAddLiquidityForTick`
- `executeJITAdd/executeJITRemove`
- `creditIssuedToken0`
- `inventoryState`

## QuoteInventoryVault
- `depositQuote/withdrawQuote`
- `reserveQuote/releaseQuote`
- `availableQuote/reservedQuote`

## IssuanceModule
- `configureSchedule`
- `availableToMint`
- `streamToVault`

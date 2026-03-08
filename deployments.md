# Deployments

## Unichain Sepolia (1301)

- Explorer base: `https://unichain-sepolia.blockscout.com`
- Latest deploy+setup artifact: `broadcast/01_DemoCompare.s.sol/1301/run-1772868921185.json`
- Latest existing-stack demo artifact: `broadcast/02_DemoCompareExisting.s.sol/1301/run-1772869710206.json`

### Core Launch Stack (Latest Active)

| Contract | Address | Tx Hash | Explorer URL |
|---|---|---|---|
| LaunchToken (`MockNewAssetToken`) | `0x0ee3E3c313cD51e3C3B09e9831C1a84dFe89CC48` | `0xac22028fc32bb1ab72d5a613c40817a5408950f470d14b48986aa6b6c02ae1b7` | https://unichain-sepolia.blockscout.com/tx/0xac22028fc32bb1ab72d5a613c40817a5408950f470d14b48986aa6b6c02ae1b7 |
| QuoteToken (`MockNewAssetToken`) | `0x180896366174318f5BD64d8320576A488400115a` | `0x174f434f1387ec708ddae573938c8c9bd901f903c852f360d3def581f75c05d9` | https://unichain-sepolia.blockscout.com/tx/0x174f434f1387ec708ddae573938c8c9bd901f903c852f360d3def581f75c05d9 |
| LaunchController | `0xd1819EfaC0a57E70BEa119727cE51b88191F3A70` | `0x9035f80ae606e57c7acebac0431f5c0d6979890f49a8fdd57f7585e20516795f` | https://unichain-sepolia.blockscout.com/tx/0x9035f80ae606e57c7acebac0431f5c0d6979890f49a8fdd57f7585e20516795f |
| QuoteInventoryVault | `0x1C2A9aBe3d3a4FBaD2FA0c795c311E670CE792C6` | `0xca8865459c9a6802ff7315a5baab4d1bcd8f69873414a646b685377a09aa210b` | https://unichain-sepolia.blockscout.com/tx/0xca8865459c9a6802ff7315a5baab4d1bcd8f69873414a646b685377a09aa210b |
| JITLiquidityVault | `0x034e2BF5C2c91788E7E85170644c4fB79073888d` | `0xd052277e1cb66d7fb156abb7776a05166d360134ee127d21440102bcc63ec686` | https://unichain-sepolia.blockscout.com/tx/0xd052277e1cb66d7fb156abb7776a05166d360134ee127d21440102bcc63ec686 |
| IssuanceModule | `0x49d0C37CFbEFc27994e784BA542E4F1f6A1a892A` | `0x74a0f926ee88d3dfa67de40e5439363d42236cb471d5bd76d8c4e8c818f3224a` | https://unichain-sepolia.blockscout.com/tx/0x74a0f926ee88d3dfa67de40e5439363d42236cb471d5bd76d8c4e8c818f3224a |
| JITLaunchHook | `0x9146Bf7b6e8Ef3508AE74ec9C0d3E2d042D080C0` | `0xbb682d130478bb4f4a3a5993141859579755dd35fb24b26bf90cb5c73b4ca8c7` | https://unichain-sepolia.blockscout.com/tx/0xbb682d130478bb4f4a3a5993141859579755dd35fb24b26bf90cb5c73b4ca8c7 |

### Launch Setup / Pool Wiring (Latest Active Stack)

| Action | Tx Hash | Explorer URL |
|---|---|---|
| Register pool config in `LaunchController` | `0x795a7d6ed6f653f50e2ecfce79041233f71af83a0864418dcc602ee4b6f4a92b` | https://unichain-sepolia.blockscout.com/tx/0x795a7d6ed6f653f50e2ecfce79041233f71af83a0864418dcc602ee4b6f4a92b |
| Register hook pool key in `JITLaunchHook` | `0x4dfe2309f3ed7a3085ac8a30f09947f2aae6f230001b0c990f657626430791d7` | https://unichain-sepolia.blockscout.com/tx/0x4dfe2309f3ed7a3085ac8a30f09947f2aae6f230001b0c990f657626430791d7 |
| Configure issuance schedule | `0x47221c2275a9eb127e060c93f3ca045786687db1aad75ecfb6ee2034732250e9` | https://unichain-sepolia.blockscout.com/tx/0x47221c2275a9eb127e060c93f3ca045786687db1aad75ecfb6ee2034732250e9 |
| Deposit token0 inventory | `0x9f9f9ef2ab96e427437ea3a4dcb31e8a571335f09a24d85c8850ebf047fd503e` | https://unichain-sepolia.blockscout.com/tx/0x9f9f9ef2ab96e427437ea3a4dcb31e8a571335f09a24d85c8850ebf047fd503e |
| Deposit quote inventory | `0xd14f0c6568ef6ccb8c5eac4423002061813f4ee751e8433163624cd1b86e0de0` | https://unichain-sepolia.blockscout.com/tx/0xd14f0c6568ef6ccb8c5eac4423002061813f4ee751e8433163624cd1b86e0de0 |
| Initialize baseline pool | `0x2cd720a953b20f63a5bd40f8bbb248fbbc6f70b21b13d6b0114e76dc5b5ad94e` | https://unichain-sepolia.blockscout.com/tx/0x2cd720a953b20f63a5bd40f8bbb248fbbc6f70b21b13d6b0114e76dc5b5ad94e |
| Add baseline liquidity | `0x316187d8384be2a11f09d1adeb1893c19472ea3a5abb4df7c01f4ea0727153ee` | https://unichain-sepolia.blockscout.com/tx/0x316187d8384be2a11f09d1adeb1893c19472ea3a5abb4df7c01f4ea0727153ee |
| Initialize JIT pool | `0x267e6bb3456494a0b9c30108a247b35f381c6209c3d4afecf405f562f0492c54` | https://unichain-sepolia.blockscout.com/tx/0x267e6bb3456494a0b9c30108a247b35f381c6209c3d4afecf405f562f0492c54 |
| Add JIT pool liquidity | `0x3d8d12fa04673a662722da9acc7c09d533d81d84b56e005be3f77593d59bd241` | https://unichain-sepolia.blockscout.com/tx/0x3d8d12fa04673a662722da9acc7c09d533d81d84b56e005be3f77593d59bd241 |

### Latest Existing-Stack Demo (No New Deployments)

- Script: `script/02_DemoCompareExisting.s.sol:DemoCompareExistingScript`
- Broadcast: `broadcast/02_DemoCompareExisting.s.sol/1301/run-1772869710206.json`
- Transaction type profile: `CALL` only (no `CREATE`/`CREATE2`)

Demo summary values:
- `Baseline avg execution price (1e18)`: `1156130977667181232`
- `JIT avg execution price (1e18)`: `1116224157354681232`
- `Baseline max slippage bps`: `852`
- `JIT max slippage bps`: `868`
- `Baseline blocked swaps`: `0`
- `JIT blocked swaps`: `0`

#### Tx URLs (Ordered)

- Token0 approve to Permit2: https://unichain-sepolia.blockscout.com/tx/0x1bec5e416a62dcc19d0e6958d685c8825455ed2a6d8cd732082020259c0dc945
- Token0 approve to SwapRouter: https://unichain-sepolia.blockscout.com/tx/0xccc56ce0c05e7c04970bd5df56bd44f94aa3f5e364cee5dccdaa59f956b64023
- Permit2 approve token0 to PositionManager: https://unichain-sepolia.blockscout.com/tx/0xbcc8190e0128bfba05d6f9051a800fbc123abf5801fa6ed8029bc91166a64602
- Permit2 approve token0 to PoolManager: https://unichain-sepolia.blockscout.com/tx/0x88db4c64570d868641ed825df6fc3fd3d5578ca9e3d0ae6de4cf9621ff27ff00
- Token1 approve to Permit2: https://unichain-sepolia.blockscout.com/tx/0xedddfc0a6a68eb6a1b191c80473beebdb597e587b19b12b8ab08d280889d78c3
- Token1 approve to SwapRouter: https://unichain-sepolia.blockscout.com/tx/0x2eef7893f0243cc874aa9badb49d63bc1f487d9f7844eed10c9f5d9c4ebd5954
- Permit2 approve token1 to PositionManager: https://unichain-sepolia.blockscout.com/tx/0x1df940a7b107d90ee3748fb66be91be28a99e131137cacec5ae79eb99c8e0a84
- Permit2 approve token1 to PoolManager: https://unichain-sepolia.blockscout.com/tx/0x0599bc14606a200b45e3170ef8a175a814da6c638c383b6a718887833e995fcb
- Baseline swap #1: https://unichain-sepolia.blockscout.com/tx/0xdd020f37ac6299c136215674f1542a2cea9bb0553cfa2c599230d33ed18835a0
- Baseline swap #2: https://unichain-sepolia.blockscout.com/tx/0x64d06a180eb5647861e181d86ac840be50128af57775d498ee9a9768ad8582ce
- Baseline swap #3: https://unichain-sepolia.blockscout.com/tx/0x3fef10486fb608aba8f1c8a10b89d232e59a7e6cd22af96c5ea754bd458b97ba
- Baseline swap #4: https://unichain-sepolia.blockscout.com/tx/0xa742dc62fabb943175d92648056b5c1769bccdce768f3722fdb6e260dff2f414
- Baseline swap #5: https://unichain-sepolia.blockscout.com/tx/0xdfc182afa947c24dd54f1d617b5a486f3da588b2fde86f7178138024366115c3
- Baseline swap #6: https://unichain-sepolia.blockscout.com/tx/0xd4e4f4ea083fcb5c4db2aac5dcdc758839d8ff05a8ed73c784821ecb6222fa98
- JIT swap #1: https://unichain-sepolia.blockscout.com/tx/0xb5dc08d2cb6b2eb664d70e9b53a9e95555b85f6e9a97a7b7878506b5326b67cd
- JIT swap #2: https://unichain-sepolia.blockscout.com/tx/0x6ed262119a90cc07db6f4eac8d5cf5f081ffc1185718adf8fb21371d1f07f864
- JIT swap #3: https://unichain-sepolia.blockscout.com/tx/0x5d4702438ea61459d3eb1a3739418312b913cedf42a706af307fa4d08f86ff34
- JIT swap #4: https://unichain-sepolia.blockscout.com/tx/0x7fe0e6e8011e3a59901793e548682250a78b9c7e6140aa4615c49a2847dcc12a
- JIT swap #5: https://unichain-sepolia.blockscout.com/tx/0xe200523b98cefad694e751e404e0bfbdaec449eb329b5b316f96531ee32a79c1
- JIT swap #6: https://unichain-sepolia.blockscout.com/tx/0xbe3c913b3a5e1f1cddc5997f022b83d05e9c1f6cb3c87fe50ae00ca1b8de900c

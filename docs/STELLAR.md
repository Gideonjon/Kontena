# Kontena on Stellar

Kontena's escrow runs in a Soroban smart contract, so buyers don't have to trust Kontena to hold their money.

| What | How |
|---|---|
| Escrow | `contracts/escrow` holds USDC per order. Funding locks the money; accepting pays the 30% deposit; passing inspection pays the 70%; failing inspection or missing a deadline sends it back. |
| Trust | Money can only go to the order's supplier or back to the buyer. The contract has no function that pays Kontena, can't change an order after funding, and can't be upgraded. Deadline refunds (`expire`) can be called by anyone, so they still happen if Kontena is offline. |
| Proof | Each step is a Stellar transaction. Order screens show it with a "View on Stellar" link to stellar.expert. |
| Naira → dollars | Naira orders are converted to USDC with a path payment on Stellar's built-in exchange (`pathPaymentStrictReceive`). The supplier gets USD, and the buyer never touches dollars. |
| No crypto UX | Wallets are custodial: no seed phrase. Payments, releases and withdrawals are confirmed with a fingerprint or face (passkeys / WebAuthn). Kontena's operator key signs every escrow step and pays every network fee. `POST /stellar/sponsor` fee-bumps transactions users sign themselves. |

## Files
- `contracts/escrow/src/lib.rs`: the contract; `src/test.rs` has 5 tests (`cd contracts && cargo test`)
- `backend/src/lib/stellar.ts`: contract calls, path payment and fee sponsorship (fetch-only, runs in the Worker)
- `backend/src/lib/chain.ts`: keeps each order's on-chain state in step with the app; failed steps retry from the cron
- `backend/src/lib/passkeys.ts`: passkey registration and verification; `X-Passkey-Token` gate on money endpoints
- `backend/test/chain.ts`: end-to-end test with Stellar faked at the network layer (`npx tsx test/chain.ts`)
- `scripts/stellar/deploy-testnet.sh`: test assets, liquidity pool and contract deployment, in one command
- App: `order_detail.dart` (Protected on Stellar card), `profile.dart` (fingerprint toggle), `core/passkeys.dart`, `web/index.html`

## Set up (testnet)
```bash
rustup target add wasm32v1-none
cargo install --locked stellar-cli
bash scripts/stellar/deploy-testnet.sh     # follow the 4 steps it prints
```

## Rules for orders
- An order goes on-chain when the supplier has a Stellar wallet. Without one it stays on the existing off-chain escrow and is paid in the app, as before.
- On-chain orders pay the supplier's Stellar wallet directly (no internal ledger credit, so nothing is paid twice).
- USDC-paid orders refund straight to the buyer's Stellar wallet. Naira-paid orders refund to Kontena's naira rail and then to the buyer's Naira wallet.
- The protection fee stays off-chain.
- Retry a stuck step: `POST /admin/orders/:id/chain/sync` or `POST /admin/chain/sync`.

## Demo script (3 minutes)
1. **Profile → "Confirm payments with your fingerprint"**: set up a passkey (Touch ID / Android fingerprint / Windows Hello).
2. Buyer opens the demo store, orders, **pays from the Naira wallet**, then confirms with a fingerprint.
3. The order shows **Protected on Stellar**: "Naira converted to USDC" and "Locked in the smart contract". Tap **View on Stellar** for the path payment and the `fund` call on stellar.expert.
4. Switch to the supplier and tap **Accept**. "30% deposit paid to supplier" appears with a new transaction. Show the USDC landing in the supplier's wallet on the explorer.
5. Supplier uploads proof. Buyer approves the inspection with a fingerprint. The 70% is released, with a new transaction.
6. Tap **Check the escrow contract yourself**. Say: "Kontena can't run off with your money either. The contract holds it, and anyone can check."

Backup: a second order where the inspection fails shows the contract's `refund`.

## Mainnet checklist
- Use Circle USDC and a licensed NGN anchor asset; set `STELLAR_NETWORK = "public"`.
- Get the contract reviewed before it holds real money.
- Keep the operator key in a secret store, and limit its float.
- Licensing for holding and converting customer funds in Nigeria and Ghana.

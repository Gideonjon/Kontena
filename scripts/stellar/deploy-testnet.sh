#!/usr/bin/env bash
# One-shot: test assets + liquidity pool, then build and deploy the Kontena escrow contract to Stellar TESTNET.
# Needs: Rust (rustup target add wasm32v1-none), the Stellar CLI (cargo install --locked stellar-cli), Node 20+.
# Run from the repo root:  bash scripts/stellar/deploy-testnet.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

(cd backend && npm install --silent)
node scripts/stellar/setup-testnet.mjs
OUT=scripts/stellar/.testnet-out.json
j() { node -e "console.log(require('./$OUT').$1)"; }
USDC_ASSET=$(j USDC_ASSET); OP_SECRET=$(node -e "console.log(require('./scripts/stellar/.testnet-keys.json').operator)"); OP_PUBLIC=$(j OPERATOR_PUBLIC)

echo "Deploying the USDC token contract (Stellar Asset Contract)…"
TOKEN=$(stellar contract asset deploy --asset "$USDC_ASSET" --source-account "$OP_SECRET" --network testnet 2>/dev/null \
  || stellar contract id asset --asset "$USDC_ASSET" --network testnet)

echo "Building the escrow contract…"
(cd contracts && stellar contract build)
WASM=contracts/target/wasm32v1-none/release/kontena_escrow.wasm

echo "Deploying the escrow contract…"
ESCROW=$(stellar contract deploy --wasm "$WASM" --source-account "$OP_SECRET" --network testnet -- --admin "$OP_PUBLIC" --token "$TOKEN")

cat <<MSG

Done. Escrow contract: https://stellar.expert/explorer/testnet/contract/$ESCROW

1) Add these to backend/wrangler.toml under [vars]:
STELLAR_NETWORK = "testnet"
ESCROW_CONTRACT_ID = "$ESCROW"
USDC_ASSET = "$USDC_ASSET"
NGN_ASSET = "$(j NGN_ASSET)"

2) Save the operator key as a Worker secret (paste it when asked):
   cd backend && npx wrangler secret put ESCROW_OPERATOR_SECRET
   value: (the "operator" entry in scripts/stellar/.testnet-keys.json)

3) Apply the migration and deploy:
   npx wrangler d1 migrations apply kontena --remote && npx wrangler deploy

4) Point your demo supplier at the demo Stellar wallet (it already trusts test USDC):
   npx wrangler d1 execute kontena --remote --command "UPDATE users SET stellar_address='$(j DEMO_SELLER)' WHERE email='YOUR_DEMO_SUPPLIER_EMAIL'"
   (optional, for USDC-paid demo orders) buyer: $(j DEMO_BUYER)
MSG

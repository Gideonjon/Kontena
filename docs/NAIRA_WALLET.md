# Naira wallet

Customers in Nigeria get a Naira wallet inside Kontena.

| Action | How it works |
|---|---|
| Add money (card, transfer, USSD) | `POST /naira/topup` opens Paystack checkout. `charge.success` with `metadata.type = wallet_topup` credits the wallet. |
| Add money (bank transfer) | Each user can request a personal account number (`POST /naira/account`). Paystack assigns a dedicated virtual account (webhook `dedicatedaccount.assign.success`). Transfers into it arrive as `charge.success` with `channel = dedicated_nuban` and credit the wallet. |
| Pay for an order | `POST /orders/:id/pay {method: "wallet"}`. The debit and the escrow funding happen together. |
| Refunds | Naira orders (wallet-paid, or card-paid with the default preference) are refunded **into the wallet**, instantly. Users can switch to "refund to original payment" with `PATCH /naira/refund-to`. USDC and Ghana orders keep their old refund rails. |
| Withdraw | `POST /naira/withdraw` sends money to the user's saved Nigerian bank account by Paystack transfer. If it fails, the money comes back to the wallet. |

## Money model
Every movement is a row in `wallet_entries` (kobo, signed). The balance is the sum of a user's rows. A unique index on `(kind, ref)` makes every credit idempotent, so a repeated webhook never pays twice. Debits are a single `INSERT ... WHERE balance >= amount`, so two taps cannot overdraw.

## Set-up checklist
1. `npx wrangler d1 migrations apply kontena --remote` (adds migration `0003_naira_wallet.sql`).
2. Paystack dashboard > Settings > API & Webhooks: webhook URL `https://api.kontena.store/webhooks/paystack`.
3. Test mode: keep `PAYSTACK_DVA_BANK = "test-bank"`. For live, ask Paystack to enable Dedicated Virtual Accounts for your business, then set `wema-bank` or `titan-paystack`. Depending on your business category Paystack may require the customer's BVN; `POST /naira/account` already accepts `bvn`, `accountNumber` and `bankCode`.
4. Fund your Paystack balance: payouts and withdrawals are paid from it.
5. Run the tests: `npx tsx test/escrow.ts` and `npx tsx test/naira.ts` (reset the local DB between runs: delete `backend/.wrangler/state/v3/d1`, then migrate).

## Compliance: read before taking real customer money
A wallet that holds customers' naira is regulated activity in Nigeria. Today the balance is a ledger on top of Kontena's own Paystack balance, so Kontena is holding customer funds. Before launching to the public: speak to a Nigerian fintech lawyer about the CBN licence or partnership route (for example operating under a licensed partner), safeguarding of customer funds, KYC tiers and balance limits (`WALLET_MAX_NGN` is a placeholder), and NDPC registration. The Terms and Privacy pages are plain-language drafts and need legal review.

# Kontena: product flow

One app (Android, iOS, web). One account. After sign-up the person picks **"I'm buying"** or **"I'm selling"**, and can switch from Profile at any time.

## Website
The landing page at `kontena.app` is the front door. **Log in** and **Create account** open real pages on the same site (`/login`, `/signup`) that do exactly what the app's sign-in does, then open the web app at `/app` already signed in. Phones use the app's own screens.

## Customer (buyer)
1. **Open a store**: browse *Explore*, search, or open a supplier's share link (`kontena.app/s/their-store`, also scannable as a QR code). Links work without an account; the person is asked to sign up only at checkout (on the web this opens the site's sign-up page, then returns to the same store).
2. **Add goods** (each product has a minimum order) or **join a group order** a supplier opened for a product.
3. **Checkout**: sees subtotal, a 1.5% protection fee and the 30/70 payment schedule, then pays with
   - **Paystack**: card, bank transfer or USSD in naira; card or Mobile Money in cedis, or
   - **USDC** from their in-app Stellar wallet.
4. **Escrow**: money is held. Order status: *In escrow*.
5. Supplier accepts, so **30% deposit is released** to the supplier. The other 70% stays locked.
6. Supplier uploads photos/documents, status becomes *Inspection*. The buyer approves (orders up to $1,000) or a Kontena inspector approves. **70% is released.** A failed inspection **refunds the 70%** to the buyer (the supplier keeps the deposit).
7. Buyer taps **"I received my goods"**. Done.
8. **Automatic refunds** (cron every 15 min): supplier doesn't accept within 3 days, refund of everything; supplier misses the ship-by date, refund of the locked 70%.

## Vendor (supplier)
1. Choose "I'm selling", then **create store** (name, about, city, logo).
2. Gets a **share link + QR** immediately; shares it on WhatsApp, Instagram or in person.
3. **Add products** (price in USD, minimum order, lead time in days, photo). Optionally **open a group order** on a product (target quantity and closing date).
4. New paid order, push notification. **Accept** to receive the 30% deposit.
5. When goods are ready, **upload proof**. After inspection passes, the balance lands in the wallet.
6. **Withdraw** to a bank account or Mobile Money (naira or cedis), or to any Stellar address as USDC.

## Money rails
| Step | Provider |
|---|---|
| Buyer pays in naira/cedis | Paystack (charge, webhook `charge.success`, refund API) |
| Buyer/vendor USDC wallet on Stellar | FossaPay (customer + `network: stellar` wallet, custodial) |
| Buyer pays in USDC | FossaPay transfer to the platform treasury wallet, webhook `transfer.completed` |
| Vendor withdraws to bank/MoMo | Paystack transfer; if the Paystack balance is short, falls back to the USDC off-ramp |
| USDC to naira/cedis conversion | Off-ramp adapter (Yellow Card Payments API, or `manual` queue). **Unverified, see README** |
| Identity, push | Firebase Auth (email, Google) and FCM on the free plan |
| API, database, images, cron | Cloudflare Worker, D1, R2, Cron Trigger |

## Order states
`awaiting_payment` → `funded` → `accepted` → `inspection` → `shipped` → `delivered`
Exits: `cancelled` (unpaid only), `refunded` (failed inspection, missed deadlines).

## Admin (Kontena team)
Admins are Firebase UIDs listed in `ADMIN_UIDS`. They get an admin console from the Profile tab: **Overview** (revenue, GMV, escrow held, refund problems), **Inspections** (pass releases the 70% balance, fail refunds the buyer), **Payouts** (manual withdrawal queue) and **Stores** (verified badge, take a store offline).

## How Kontena earns
1. **Buyer protection fee** (default 1.5% of the order), recognised when the supplier accepts.
2. **Seller commission** (optional, default 0%), taken from the balance at release.
3. **Withdrawal FX spread** (default 1.5%) when a supplier cashes out USDC to naira or cedis. It is reversed if the payout fails.

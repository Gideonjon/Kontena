//! Kontena trade escrow.
//!
//! Holds a buyer's payment for one order and enforces Kontena's rules on-chain:
//! * the supplier gets the deposit (30% by default) only after accepting,
//! * the balance (70%) is released only after inspection passes,
//! * a failed inspection or a missed deadline sends the locked money back to the buyer.
//!
//! Money can only ever move to the order's `seller` or its `refund_to` address. There is no
//! function that pays the admin, no way to change an order's amounts or addresses after it is
//! funded, and no upgrade function. Deadline refunds can be triggered by anyone, so they still
//! happen if Kontena's servers are down.
#![no_std]
use soroban_sdk::{contract, contracterror, contractevent, contractimpl, contracttype, panic_with_error, token, Address, BytesN, Env};

#[contracterror]
#[derive(Copy, Clone, Debug, Eq, PartialEq, PartialOrd, Ord)]
#[repr(u32)]
pub enum Error {
    OrderExists = 1,
    NoOrder = 2,
    BadState = 3,
    BadAmount = 4,
    NotAllowed = 5,
    TooEarly = 6,
}

#[contracttype]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Status {
    Funded = 0,
    Accepted = 1,
    Released = 2,
    Refunded = 3,
}

#[contracttype]
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Order {
    pub buyer: Address,
    pub seller: Address,
    pub refund_to: Address,
    pub amount: i128,
    pub deposit: i128,
    pub paid_to_seller: i128,
    pub refunded: i128,
    pub accept_by: u64,
    pub lead_secs: u64,
    pub ship_by: u64,
    pub status: Status,
}

/// Emitted when an order's money is locked.
#[contractevent]
pub struct Funded { #[topic] pub id: BytesN<32>, pub amount: i128, pub deposit: i128 }
/// Emitted when the supplier accepts and receives the deposit.
#[contractevent]
pub struct Accepted { #[topic] pub id: BytesN<32>, pub deposit_paid: i128 }
/// Emitted when the balance is released to the supplier after inspection.
#[contractevent]
pub struct Released { #[topic] pub id: BytesN<32>, pub balance_paid: i128 }
/// Emitted when locked money goes back to the buyer (failed inspection or missed deadline).
#[contractevent]
pub struct Refunded { #[topic] pub id: BytesN<32>, pub amount: i128, pub deadline: bool }

#[contracttype]
enum Key {
    Admin,
    Token,
    Order(BytesN<32>),
}

const DAY_LEDGERS: u32 = 17_280;
const KEEP: u32 = DAY_LEDGERS * 120;

#[contract]
pub struct Escrow;

fn admin(e: &Env) -> Address { e.storage().instance().get(&Key::Admin).unwrap() }
fn tok(e: &Env) -> token::Client<'_> { token::Client::new(e, &e.storage().instance().get::<_, Address>(&Key::Token).unwrap()) }
fn load(e: &Env, id: &BytesN<32>) -> Order {
    e.storage().persistent().get(&Key::Order(id.clone())).unwrap_or_else(|| panic_with_error!(e, Error::NoOrder))
}
fn save(e: &Env, id: &BytesN<32>, o: &Order) {
    let k = Key::Order(id.clone());
    e.storage().persistent().set(&k, o);
    e.storage().persistent().extend_ttl(&k, KEEP, KEEP);
    e.storage().instance().extend_ttl(KEEP, KEEP);
}
fn pay(e: &Env, to: &Address, amount: i128) {
    if amount > 0 { tok(e).transfer(&e.current_contract_address(), to, &amount); }
}

#[contractimpl]
impl Escrow {
    /// `admin` is Kontena's escrow operator, `token` the USDC token contract.
    pub fn __constructor(e: Env, admin: Address, token: Address) {
        e.storage().instance().set(&Key::Admin, &admin);
        e.storage().instance().set(&Key::Token, &token);
    }

    /// Locks `amount` from `from` for order `id`. `deposit_bps` is the deposit share in basis points (3000 = 30%).
    pub fn fund(e: Env, id: BytesN<32>, from: Address, buyer: Address, seller: Address, refund_to: Address,
                amount: i128, deposit_bps: u32, accept_by: u64, lead_secs: u64) {
        from.require_auth();
        if e.storage().persistent().has(&Key::Order(id.clone())) { panic_with_error!(&e, Error::OrderExists); }
        if amount <= 0 || deposit_bps > 10_000 { panic_with_error!(&e, Error::BadAmount); }
        if accept_by <= e.ledger().timestamp() { panic_with_error!(&e, Error::TooEarly); }
        tok(&e).transfer(&from, &e.current_contract_address(), &amount);
        let deposit = amount * deposit_bps as i128 / 10_000;
        let o = Order { buyer, seller, refund_to, amount, deposit, paid_to_seller: 0, refunded: 0, accept_by, lead_secs, ship_by: 0, status: Status::Funded };
        save(&e, &id, &o);
        Funded { id, amount, deposit }.publish(&e);
    }

    /// Supplier accepts (Kontena signs for custodial suppliers). Releases the deposit to the supplier.
    pub fn accept(e: Env, id: BytesN<32>, by: Address) {
        by.require_auth();
        let mut o = load(&e, &id);
        if by != o.seller && by != admin(&e) { panic_with_error!(&e, Error::NotAllowed); }
        if o.status != Status::Funded { panic_with_error!(&e, Error::BadState); }
        if e.ledger().timestamp() > o.accept_by { panic_with_error!(&e, Error::TooEarly); }
        o.status = Status::Accepted;
        o.ship_by = e.ledger().timestamp() + o.lead_secs;
        o.paid_to_seller = o.deposit;
        pay(&e, &o.seller, o.deposit);
        save(&e, &id, &o);
        Accepted { id, deposit_paid: o.deposit }.publish(&e);
    }

    /// Inspection passed: the buyer or Kontena's inspector releases the balance to the supplier.
    pub fn release(e: Env, id: BytesN<32>, by: Address) {
        by.require_auth();
        let mut o = load(&e, &id);
        if by != o.buyer && by != admin(&e) { panic_with_error!(&e, Error::NotAllowed); }
        if o.status != Status::Accepted { panic_with_error!(&e, Error::BadState); }
        let bal = o.amount - o.paid_to_seller;
        o.status = Status::Released;
        o.paid_to_seller = o.amount;
        pay(&e, &o.seller, bal);
        save(&e, &id, &o);
        Released { id, balance_paid: bal }.publish(&e);
    }

    /// Inspection failed: Kontena's inspector sends the locked balance back to the buyer.
    pub fn refund(e: Env, id: BytesN<32>) {
        admin(&e).require_auth();
        let mut o = load(&e, &id);
        if o.status != Status::Accepted && o.status != Status::Funded { panic_with_error!(&e, Error::BadState); }
        let back = o.amount - o.paid_to_seller;
        o.status = Status::Refunded;
        o.refunded = back;
        pay(&e, &o.refund_to, back);
        save(&e, &id, &o);
        Refunded { id, amount: back, deadline: false }.publish(&e);
    }

    /// Anyone may call this once a deadline has passed: no acceptance by `accept_by` refunds everything,
    /// a missed ship-by date refunds the locked balance.
    pub fn expire(e: Env, id: BytesN<32>) {
        let mut o = load(&e, &id);
        let t = e.ledger().timestamp();
        let late = match o.status {
            Status::Funded => t > o.accept_by,
            Status::Accepted => t > o.ship_by,
            _ => panic_with_error!(&e, Error::BadState),
        };
        if !late { panic_with_error!(&e, Error::TooEarly); }
        let back = o.amount - o.paid_to_seller;
        o.status = Status::Refunded;
        o.refunded = back;
        pay(&e, &o.refund_to, back);
        save(&e, &id, &o);
        Refunded { id, amount: back, deadline: true }.publish(&e);
    }

    pub fn get(e: Env, id: BytesN<32>) -> Order { load(&e, &id) }
    pub fn admin(e: Env) -> Address { admin(&e) }
    pub fn token(e: Env) -> Address { e.storage().instance().get(&Key::Token).unwrap() }
}

#[cfg(test)]
mod test;

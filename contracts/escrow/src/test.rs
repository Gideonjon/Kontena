#![cfg(test)]
extern crate std;
use super::*;
use soroban_sdk::testutils::{Address as _, Ledger};
use soroban_sdk::{token::StellarAssetClient, token::TokenClient, BytesN, Env};

struct T { e: Env, c: EscrowClient<'static>, usdc: TokenClient<'static>, admin: Address, buyer: Address, seller: Address }

fn setup() -> T {
    let e = Env::default();
    e.mock_all_auths();
    e.ledger().with_mut(|l| l.timestamp = 1_000_000);
    let admin = Address::generate(&e);
    let sac = e.register_stellar_asset_contract_v2(Address::generate(&e));
    StellarAssetClient::new(&e, &sac.address()).mint(&admin, &1_000_000_000);
    let id = e.register(Escrow, (admin.clone(), sac.address()));
    let c = EscrowClient::new(&e, &id);
    let usdc = TokenClient::new(&e, &sac.address());
    let (buyer, seller) = (Address::generate(&e), Address::generate(&e));
    T { e, c, usdc, admin, buyer, seller }
}
fn oid(e: &Env, n: u8) -> BytesN<32> { BytesN::from_array(e, &[n; 32]) }
fn fund(t: &T, n: u8) -> BytesN<32> {
    let id = oid(&t.e, n);
    t.c.fund(&id, &t.admin, &t.buyer, &t.seller, &t.buyer, &10_000_000, &3000, &(1_000_000 + 3 * 86_400), &(7 * 86_400));
    id
}

#[test]
fn happy_path_30_then_70() {
    let t = setup(); let id = fund(&t, 1);
    assert_eq!(t.usdc.balance(&t.c.address), 10_000_000);
    t.c.accept(&id, &t.admin);
    assert_eq!(t.usdc.balance(&t.seller), 3_000_000);
    t.c.release(&id, &t.admin);
    assert_eq!(t.usdc.balance(&t.seller), 10_000_000);
    assert_eq!(t.usdc.balance(&t.c.address), 0);
    assert_eq!(t.c.get(&id).status, Status::Released);
}

#[test]
fn failed_inspection_refunds_70_to_buyer() {
    let t = setup(); let id = fund(&t, 2);
    t.c.accept(&id, &t.admin); t.c.refund(&id);
    assert_eq!(t.usdc.balance(&t.seller), 3_000_000);
    assert_eq!(t.usdc.balance(&t.buyer), 7_000_000);
}

#[test]
fn no_accept_anyone_can_refund_everything() {
    let t = setup(); let id = fund(&t, 3);
    assert!(t.c.try_expire(&id).is_err());
    t.e.ledger().with_mut(|l| l.timestamp += 3 * 86_400 + 1);
    t.c.expire(&id);
    assert_eq!(t.usdc.balance(&t.buyer), 10_000_000);
    assert!(t.c.try_accept(&id, &t.admin).is_err());
}

#[test]
fn missed_ship_date_refunds_balance() {
    let t = setup(); let id = fund(&t, 4);
    t.c.accept(&id, &t.seller);
    t.e.ledger().with_mut(|l| l.timestamp += 6 * 86_400);
    assert!(t.c.try_expire(&id).is_err());
    t.e.ledger().with_mut(|l| l.timestamp += 2 * 86_400);
    t.c.expire(&id);
    assert_eq!(t.usdc.balance(&t.buyer), 7_000_000);
    assert_eq!(t.usdc.balance(&t.seller), 3_000_000);
}

#[test]
fn rules_cannot_be_skipped() {
    let t = setup(); let id = fund(&t, 5);
    assert!(t.c.try_release(&id, &t.admin).is_err());          // no balance before acceptance
    let stranger = Address::generate(&t.e);
    assert!(t.c.try_accept(&id, &stranger).is_err());          // only seller or Kontena
    t.c.accept(&id, &t.admin);
    assert!(t.c.try_release(&id, &stranger).is_err());         // only buyer or Kontena
    assert!(t.c.try_accept(&id, &t.admin).is_err());           // no second deposit
    t.c.release(&id, &t.buyer);
    assert!(t.c.try_refund(&id).is_err());                     // nothing to refund after release
    assert!(t.c.try_fund(&id, &t.admin, &t.buyer, &t.seller, &t.buyer, &1, &3000, &2_000_000, &1).is_err()); // ids are one-shot
    assert_eq!(t.usdc.balance(&t.admin), 1_000_000_000 - 10_000_000); // admin never received anything
}

mod keccak;

global TREE_DEPTH: u32 = 8;

fn field_to_bytes32(x: Field) -> [u8; 32] {
    x.to_be_bytes::<32>()
}

fn bytes32_to_field(bytes: [u8; 32]) -> Field {
    let mut result: Field = 0;
    for i in 0..32 {
        result = result * 256 + bytes[i] as Field;
    }
    result
}

fn hash2(a: Field, b: Field) -> Field {
    let a_bytes = field_to_bytes32(a);
    let b_bytes = field_to_bytes32(b);
    let mut input: [u8; 64] = [0; 64];
    for i in 0..32 {
        input[i] = a_bytes[i];
        input[32 + i] = b_bytes[i];
    }
    bytes32_to_field(keccak::keccak256_single_block(input))
}

fn deposit_commitment(secret: Field, amount: u64) -> Field {
    let secret_bytes = field_to_bytes32(secret);
    let mut input: [u8; 40] = [0; 40];
    for i in 0..32 {
        input[i] = secret_bytes[i];
    }
    let amount_bytes = (amount as Field).to_be_bytes::<8>();
    for i in 0..8 {
        input[32 + i] = amount_bytes[i];
    }
    bytes32_to_field(keccak::keccak256_single_block(input))
}

fn merkle_root(leaf: Field, path: [Field; TREE_DEPTH], index: Field) -> Field {
    let bits: [bool; TREE_DEPTH] = index.to_le_bits();
    let mut node = leaf;
    for i in 0..TREE_DEPTH {
        node = if !bits[i] { hash2(node, path[i]) } else { hash2(path[i], node) };
    }
    node
}

fn main(
    pool_root: pub Field,
    trader: pub Field,
    epoch: pub u64,
    threshold_value: pub u64,
    secret: Field,
    deposit_amount: u64,
    path: [Field; TREE_DEPTH],
    index: Field,
) -> pub Field {
    assert(trader != 0);
    assert(deposit_amount >= threshold_value);

    let leaf = deposit_commitment(secret, deposit_amount);
    assert(merkle_root(leaf, path, index) == pool_root);

    hash2(secret, epoch as Field)
}

global TEST_SECRET: Field = 0x7a8b9c;
global TEST_AMOUNT: u64 = 5_000;
global TEST_INDEX: Field = 3;
global TEST_THRESHOLD: u64 = 1_000;
global TEST_EPOCH: u64 = 7;
global TEST_TRADER: Field = 0x1111;

fn test_path() -> [Field; TREE_DEPTH] {
    let mut path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];
    for i in 0..TREE_DEPTH {
        path[i] = (i as Field) + 200;
    }
    path
}

fn test_root() -> Field {
    let leaf = deposit_commitment(TEST_SECRET, TEST_AMOUNT);
    merkle_root(leaf, test_path(), TEST_INDEX)
}

fn run(root: Field, trader: Field, threshold: u64, amount: u64, epoch: u64) -> Field {
    main(root, trader, epoch, threshold, TEST_SECRET, amount, test_path(), TEST_INDEX)
}

#[test]
fn accepts_a_deposit_exactly_at_threshold() {
    let _ = run(test_root(), TEST_TRADER, TEST_AMOUNT, TEST_AMOUNT, TEST_EPOCH);
}

#[test]
fn accepts_a_deposit_above_threshold() {
    let _ = run(test_root(), TEST_TRADER, TEST_THRESHOLD, TEST_AMOUNT, TEST_EPOCH);
}

#[test(should_fail)]
fn refuses_a_deposit_below_threshold() {
    let _ = run(test_root(), TEST_TRADER, TEST_AMOUNT + 1, TEST_AMOUNT, TEST_EPOCH);
}

#[test(should_fail)]
fn refuses_a_root_the_deposit_is_not_part_of() {
    let _ = run(test_root() + 1, TEST_TRADER, TEST_THRESHOLD, TEST_AMOUNT, TEST_EPOCH);
}

#[test]
fn nullifier_is_stable_across_different_traders_for_the_same_deposit_and_epoch() {
    let a = run(test_root(), TEST_TRADER, TEST_THRESHOLD, TEST_AMOUNT, TEST_EPOCH);
    let b = run(test_root(), TEST_TRADER + 1, TEST_THRESHOLD, TEST_AMOUNT, TEST_EPOCH);
    assert(a == b);
}

#[test]
fn nullifier_changes_across_epochs() {
    let a = run(test_root(), TEST_TRADER, TEST_THRESHOLD, TEST_AMOUNT, TEST_EPOCH);
    let b = run(test_root(), TEST_TRADER, TEST_THRESHOLD, TEST_AMOUNT, TEST_EPOCH + 1);
    assert(a != b);
}

#[test]
fn print_hash2_of_one_and_two_for_solidity_cross_check() {
    let result = hash2(1, 2);
    println(f"hash2(1,2) = {result}");
}

#[test]
fn print_empty_tree_zero_hashes() {
    let mut z: Field = 0;
    println(f"zero[0] = {z}");
    for i in 1..TREE_DEPTH {
        z = hash2(z, z);
        println(f"zero[{i}] = {z}");
    }
}

fn empty_tree_path() -> [Field; TREE_DEPTH] {
    let mut path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];
    let mut z: Field = 0;
    for i in 1..TREE_DEPTH {
        z = hash2(z, z);
        path[i] = z;
    }
    path
}

#[test]
fn print_first_deposit_public_inputs_for_prover_toml() {
    let leaf = deposit_commitment(TEST_SECRET, TEST_AMOUNT);
    let root = merkle_root(leaf, empty_tree_path(), 0);
    println(f"leaf = {leaf}");
    println(f"pool_root = {root}");
}

#[test]
fn print_public_inputs_for_prover_toml() {
    let root = test_root();
    println(f"pool_root = {root}");
    println(f"trader = {TEST_TRADER}");
}
